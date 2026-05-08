const functions = require("firebase-functions"); // Trigger redeployment
const admin = require("firebase-admin");
const cors = require("cors")({ origin: true });
const ngeohash = require("ngeohash");

admin.initializeApp();

// ============================================================
// CONSTANTS
// ============================================================
const HEARTBEAT_MAX_AGE_SEC = 300; // 5 minutes (App sends heartbeat every 2m, needs buffer)
const RIDE_EXPIRY_MINUTES = 5;

/**
 * acceptBid (Callable)
 *
 * Server-authoritative ride matching. Called by the Rider app when they
 * choose a driver's bid. Runs a Firestore Transaction with 6 safety checks:
 *   1. Ride status ∈ [searching, bidding]
 *   2. Ride not locked (prevents double-tap / retry)
 *   3. Bid status == pending
 *   4. Driver state ∈ [ONLINE_IDLE, BIDDING]
 *   5. Driver heartbeat within 120 seconds
 *   6. Ride not expired
 *
 * On success: locks ride, sets matched, moves driver to ON_RIDE.
 * OTP is generated server-side.
 */
exports.acceptBid = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "You must be logged in."
    );
  }

  const { rideId, bidId } = data;
  if (!rideId || !bidId) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Missing rideId or bidId."
    );
  }

  const db = admin.firestore();
  const rideRef = db.collection("rides").doc(rideId);
  const bidRef = db.collection("bids").doc(bidId);

  try {
    await db.runTransaction(async (txn) => {
      const rideSnap = await txn.get(rideRef);
      const bidSnap = await txn.get(bidRef);

      if (!rideSnap.exists) {
        throw new functions.https.HttpsError("not-found", "Ride not found.");
      }
      if (!bidSnap.exists) {
        throw new functions.https.HttpsError("not-found", "Bid not found.");
      }

      const ride = rideSnap.data();
      const bid = bidSnap.data();
      const driverId = bid.driverId;
      const driverRef = db.collection("drivers").doc(driverId);
      const driverSnap = await txn.get(driverRef);

      if (!driverSnap.exists) {
        throw new functions.https.HttpsError("not-found", "Driver not found.");
      }
      const driver = driverSnap.data();

      // ── CHECK 1: Ride status ──
      if (ride.status !== "searching" && ride.status !== "bidding") {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "Ride is no longer available."
        );
      }

      // ── CHECK 2: Ride not locked ──
      if (ride.locked === true) {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "Ride is already being matched."
        );
      }

      // ── CHECK 3: Bid status ──
      if (bid.status !== "pending") {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "This bid has been withdrawn."
        );
      }

      // ── CHECK 4: Driver state ──
      const dState = driver.driverState || (driver.isOnline ? "ONLINE_IDLE" : "OFFLINE");
      if (dState !== "ONLINE_IDLE" && dState !== "BIDDING") {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "Driver is no longer available."
        );
      }

      // ── CHECK 5: Heartbeat ──
      const heartbeat = driver.lastHeartbeat || driver.lastLocationUpdate;
      if (heartbeat) {
        const hbDate = heartbeat.toDate ? heartbeat.toDate() : new Date(heartbeat);
        const ageSec = (Date.now() - hbDate.getTime()) / 1000;
        if (ageSec > HEARTBEAT_MAX_AGE_SEC) {
          throw new functions.https.HttpsError(
            "failed-precondition",
            "Driver appears to be unreachable."
          );
        }
      }
      // If no heartbeat at all, we still allow (new driver, first ride)

      // ── CHECK 6: Ride not expired ──
      if (ride.createdAt) {
        const created = ride.createdAt.toDate ? ride.createdAt.toDate() : new Date(ride.createdAt);
        const ageMin = (Date.now() - created.getTime()) / 60000;
        if (ageMin > RIDE_EXPIRY_MINUTES) {
          throw new functions.https.HttpsError(
            "failed-precondition",
            "This ride has expired."
          );
        }
      }

      // ── ALL CHECKS PASSED — ATOMIC UPDATES ──
      const otp = String(1000 + Math.floor(Math.random() * 9000));

      txn.update(rideRef, {
        locked: true,
        status: "matched",
        driverId: driverId,
        driverName: bid.driverName || "Driver",
        driverPhone: bid.driverPhone || "",
        vehicleNumber: bid.vehicleNumber || "",
        finalPrice: bid.price,
        rideOtp: otp,
        matchedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      txn.update(bidRef, { status: "accepted" });

      txn.update(driverRef, {
        driverState: "ON_RIDE",
        activeRideId: rideId,
        activeBidCount: 0,
      });
    });

    return { success: true };
  } catch (error) {
    // Re-throw HttpsErrors as-is, wrap others
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }
    console.error("acceptBid error:", error);
    throw new functions.https.HttpsError("internal", error.message || "Unknown error.");
  }
});

/**
 * sendBroadcastNotification
 *
 * Sends a push notification to all users or all drivers.
 * The admin app calls this function with:
 *   { title: string, body: string, target: "users" | "drivers" }
 *
 * It fetches FCM tokens from Firestore and sends notifications via
 * Firebase Cloud Messaging.
 */
exports.sendBroadcastNotification = functions.https.onRequest((req, res) => {
  cors(req, res, async () => {
    // Only allow POST
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed" });
      return;
    }

    const { title, body, target } = req.body;

    if (!title || !body || !target) {
      res.status(400).json({ error: "Missing title, body, or target" });
      return;
    }

    try {
      const topicName = target === "drivers" ? "drivers" : "riders";
      
      await admin.messaging().send({
        topic: topicName,
        notification: { title, body },
        data: { type: "broadcast", target },
      });

      // Also log the notification to Firestore
      await admin.firestore().collection("notifications_log").add({
        title,
        body,
        target,
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
        method: "topic",
        topic: topicName,
      });

      res.status(200).json({
        success: true,
        method: "topic",
        topic: topicName,
      });
    } catch (error) {
      console.error("Error sending notification:", error);
      res.status(500).json({ error: error.message });
    }
  });
});

/**
 * approveAccountDeletion
 *
 * An HTTPS callable function to approve a user's account deletion request.
 * It takes the requestId and uid.
 * Deletes the user from Firebase Auth and deletes their Firestore document.
 */
exports.approveAccountDeletion = functions.https.onCall(async (data, context) => {
  // Ensure the user calling this is authenticated (optionally check if they are admin)
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Only authenticated users can call this function."
    );
  }

  const uid = data.uid;
  const requestId = data.requestId;
  const role = data.role || "user";

  if (!uid || !requestId) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Missing uid or requestId."
    );
  }

  try {
    let shouldDeleteAuth = false;

    // 1. Delete user's document from Firestore and Storage (if driver) based on role
    if (role === "driver") {
      await admin.firestore().collection("drivers").doc(uid).delete();
      
      // Delete images from Firebase Storage
      const bucket = admin.storage().bucket();
      const filesToDelete = [
        `drivers/${uid}/selfie.jpg`,
        `drivers/${uid}/aadhar.jpg`,
        `drivers/${uid}/license.jpg`
      ];
      
      for (const filePath of filesToDelete) {
        try {
          await bucket.file(filePath).delete();
          console.log(`Deleted ${filePath}`);
        } catch (e) {
          console.log(`Failed to delete ${filePath}:`, e);
        }
      }

      // Check if user has a rider profile
      const userDoc = await admin.firestore().collection("users").doc(uid).get();
      if (!userDoc.exists) {
        shouldDeleteAuth = true;
      }
      
      // Notify driver via FCM
      try {
        await admin.messaging().send({
          topic: `driver_${uid}`,
          notification: {
            title: "Account Deleted",
            body: "Your driver account and all associated data have been permanently deleted.",
          },
          data: { type: "account_deleted" },
        });
      } catch (e) {
        console.log("Failed to send FCM to driver:", e);
      }
    } else {
      await admin.firestore().collection("users").doc(uid).delete();
      
      // Check if user has a driver profile
      const driverDoc = await admin.firestore().collection("drivers").doc(uid).get();
      if (!driverDoc.exists) {
        shouldDeleteAuth = true;
      }

      // Notify rider via FCM
      try {
        await admin.messaging().send({
          topic: `rider_${uid}`,
          notification: {
            title: "Account Deleted",
            body: "Your account and all associated data have been permanently deleted.",
          },
          data: { type: "account_deleted" },
        });
      } catch (e) {
        console.log("Failed to send FCM to rider:", e);
      }
    }

    // 2. Delete user from Firebase Auth if no other profiles exist
    if (shouldDeleteAuth) {
      try {
        await admin.auth().deleteUser(uid);
        console.log(`Deleted auth user: ${uid}`);
      } catch (e) {
        console.log(`Failed to delete auth user ${uid}:`, e);
      }
    }

    // 3. Mark the deletion request as approved
    await admin.firestore()
      .collection("account_deletion_requests")
      .doc(requestId)
      .update({
        status: "approved",
        approvedAt: admin.firestore.FieldValue.serverTimestamp(),
        approvedBy: context.auth.uid,
      });

    return { success: true, message: "Account deleted successfully." };
  } catch (error) {
    console.error("Error deleting account:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

/**
 * onDriverRegistered
 * Notifies admins when a new driver registers.
 */
exports.onDriverRegistered = functions.firestore
  .document("drivers/{driverId}")
  .onCreate(async (snap, context) => {
    const data = snap.data();
    const name = data.name || "A new driver";
    
    await admin.messaging().send({
      topic: "admins",
      notification: {
        title: "New Driver Registration",
        body: `${name} has registered and is pending approval.`,
      },
      data: { type: "driver_registered", driverId: context.params.driverId },
    });
  });

/**
 * onDriverApproved
 * Notifies the driver when their account is approved.
 */
exports.onDriverApproved = functions.firestore
  .document("drivers/{driverId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();

    const wasApproved = before.isApproved === true || before.isApproved === "true";
    const isApproved = after.isApproved === true || after.isApproved === "true";

    if (!wasApproved && isApproved) {
      await admin.messaging().send({
        topic: `driver_${context.params.driverId}`,
        notification: {
          title: "Account Approved!",
          body: "Your driver account has been approved. You can now accept rides.",
        },
        data: { type: "driver_approved" },
      });
    }
  });

/**
 * onRideStatusChanged
 * Tracks cancellations and notifies rider/driver about ride status changes.
 * Also cleans up RTDB signals, other bids, and manages activeBidCount.
 */
exports.onRideStatusChanged = functions.firestore
  .document("rides/{rideId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    const rideId = context.params.rideId;

    // 1. If ride matched/accepted, clean up driver bids on OTHER active rides
    // and delete the RTDB signal so no more drivers see it.
    if (before.status !== "matched" && before.status !== "accepted" &&
        (after.status === "accepted" || after.status === "matched")) {
      const driverId = after.driverId;
      if (driverId) {
        // Increment assigned rides for driver
        await admin.firestore().collection("drivers").doc(driverId).update({
          totalAssignedRides: admin.firestore.FieldValue.increment(1)
        });

        // Cancel this driver's bids on other active rides
        const otherBids = await admin.firestore().collection("bids")
          .where("driverId", "==", driverId)
          .where("status", "==", "pending")
          .get();
        
        const batch = admin.firestore().batch();
        otherBids.docs.forEach(doc => {
          if (doc.data().rideId !== rideId) {
            batch.update(doc.ref, { status: "withdrawn" });
          }
        });
        await batch.commit();

        // Reject all other pending bids for this ride and decrement their drivers' activeBidCount
        const otherRideBids = await admin.firestore().collection("bids")
          .where("rideId", "==", rideId)
          .where("status", "==", "pending")
          .get();
        
        const rejectBatch = admin.firestore().batch();
        const affectedDriverIds = new Set();
        otherRideBids.docs.forEach(doc => {
          rejectBatch.update(doc.ref, { status: "rejected" });
          affectedDriverIds.add(doc.data().driverId);
        });
        await rejectBatch.commit();

        // Decrement activeBidCount for each affected driver
        for (const affectedId of affectedDriverIds) {
          if (affectedId && affectedId !== driverId) {
            try {
              const driverDoc = await admin.firestore().collection("drivers").doc(affectedId).get();
              if (driverDoc.exists) {
                const dData = driverDoc.data();
                const newCount = Math.max(0, (dData.activeBidCount || 1) - 1);
                const updates = { activeBidCount: newCount };
                // If no more active bids, return to ONLINE_IDLE
                if (newCount === 0 && dData.driverState === "BIDDING") {
                  updates.driverState = "ONLINE_IDLE";
                }
                await admin.firestore().collection("drivers").doc(affectedId).update(updates);
              }
            } catch (e) {
              console.error(`Failed to update activeBidCount for driver ${affectedId}:`, e);
            }
          }
        }
      }

      // Cleanup RTDB signal
      await admin.database().ref(`ride_signals/${rideId}`).remove();
      console.log(`Cleaned up RTDB signal for matched ride ${rideId}`);
    }

    // 2. Cancellation and Expiration tracking
    if (before.status !== "cancelled" && after.status === "cancelled") {
      if (after.driverId) {
        // Increment total cancelled rides for driver and reset state
        await admin.firestore().collection("drivers").doc(after.driverId).update({
          totalCancelledRides: admin.firestore.FieldValue.increment(1),
          driverState: "ONLINE_IDLE",
          activeRideId: null,
          activeBidCount: 0,
        });
      }
      // Cleanup RTDB signal just in case
      await admin.database().ref(`ride_signals/${rideId}`).remove();
    } else if (before.status !== "expired" && after.status === "expired") {
      // Decrement activeBidCount for all drivers who had pending bids on this ride
      const pendingBids = await admin.firestore().collection("bids")
        .where("rideId", "==", rideId)
        .where("status", "==", "pending")
        .get();

      const expBatch = admin.firestore().batch();
      const expDriverIds = new Set();
      pendingBids.docs.forEach(doc => {
        expBatch.update(doc.ref, { status: "expired" });
        expDriverIds.add(doc.data().driverId);
      });
      await expBatch.commit();

      for (const dId of expDriverIds) {
        try {
          const dd = await admin.firestore().collection("drivers").doc(dId).get();
          if (dd.exists) {
            const d = dd.data();
            const nc = Math.max(0, (d.activeBidCount || 1) - 1);
            const upd = { activeBidCount: nc };
            if (nc === 0 && d.driverState === "BIDDING") {
              upd.driverState = "ONLINE_IDLE";
            }
            await admin.firestore().collection("drivers").doc(dId).update(upd);
          }
        } catch (e) {
          console.error(`Failed to update activeBidCount for driver ${dId}:`, e);
        }
      }

      // Cleanup RTDB signal
      await admin.database().ref(`ride_signals/${rideId}`).remove();
    }

    // 3. Status change notifications
    if (before.status !== after.status && after.status !== "expired") {
      if (after.riderId) {
        await admin.messaging().send({
          topic: `rider_${after.riderId}`,
          notification: {
            title: "Ride Update",
            body: `Your ride status is now: ${after.status}`,
          },
          data: { type: "ride_status", rideId, status: after.status },
        });
      }
      if (after.driverId) {
        await admin.messaging().send({
          topic: `driver_${after.driverId}`,
          notification: {
            title: "Ride Update",
            body: `Ride status updated to: ${after.status}`,
          },
          data: { type: "ride_status", rideId, status: after.status },
        });
      }
    }
  });

/**
 * onRideCreated (Dispatcher)
 * When a rider requests a ride, this function calculates the geohash-5 center,
 * computes the 8 neighbors, saves a signal to RTDB, and sends a wakeup push
 * notification to the 9 corresponding FCM topics.
 */
exports.onRideCreated = functions.firestore
  .document("rides/{rideId}")
  .onCreate(async (snap, context) => {
    const rideId = context.params.rideId;
    const data = snap.data();

    if (!data.pickup || !data.pickup.lat || !data.pickup.lng) {
      console.log("Missing pickup location for ride", rideId);
      return;
    }

    const lat = data.pickup.lat;
    const lng = data.pickup.lng;
    const vehicleType = data.vehicleType || "auto";

    // Compute geohash level 5 for pickup location (~4.9km x 4.9km)
    const centerHash = ngeohash.encode(lat, lng, 5);
    const neighbors = ngeohash.neighbors(centerHash);
    const targetHashes = [centerHash, ...neighbors];

    console.log(`Dispatching ride ${rideId} to hashes: ${targetHashes.join(", ")}`);

    // 1. Write the signal to RTDB so active drivers can see it immediately
    const signalData = {
      rideId,
      riderId: data.riderId,
      pickup: data.pickup,
      drop: data.drop,
      vehicleType,
      createdAt: admin.database.ServerValue.TIMESTAMP,
      status: "searching",
      geohash5: centerHash,
      targetHashes: targetHashes, // useful for multi-cell filtering
      distanceKm: data.distanceKm || 0,
      durationMin: data.durationMin || 0,
      riderBid: data.riderBid || 0,
    };


    await admin.database().ref(`ride_signals/${rideId}`).set(signalData);

    // 2. Send FCM wakeup to drivers in these 9 zones
    // Drivers subscribe to: zone_{geohash5}_{vehicleType}
    const topics = targetHashes.map(h => `'zone_${h}_${vehicleType}' in topics`).join(" || ");
    
    // FCM condition strings can only have up to 5 conditions. 
    // We have 9 hashes. So we send 2 messages.
    const chunk1 = targetHashes.slice(0, 5);
    const chunk2 = targetHashes.slice(5, 9);

    const pickupName = (data.pickup && data.pickup.short_name) || "Nearby";
    const dropName = (data.drop && data.drop.short_name) || "Destination";
    const fareLabel = data.riderBid ? `₹${data.riderBid}` : "Open bid";
    const distLabel = data.distanceKm ? `${data.distanceKm} km` : "";

    const sendWakeup = async (hashes) => {
      if (hashes.length === 0) return;
      const condition = hashes.map(h => `'zone_${h}_${vehicleType}' in topics`).join(" || ");
      try {
        await admin.messaging().send({
          condition: condition,
          notification: {
            title: `New ${vehicleType} ride — ${fareLabel}`,
            body: `${pickupName} → ${dropName}${distLabel ? " · " + distLabel : ""}`,
          },
          data: {
            type: "new_ride",
            rideId: rideId,
          },
          android: {
            priority: "high",
            notification: {
              channelId: "ride_alerts",
              sound: "default",
              priority: "high",
            },
          },
        });
      } catch (e) {
        console.error("FCM Send Error:", e);
      }
    };

    await sendWakeup(chunk1);
    await sendWakeup(chunk2);
  });

/**
 * expandRideSearch (Phase 2 — Wider Radius)
 *
 * Runs every minute. Finds rides that have been searching/bidding for 3+ minutes
 * but less than 5 minutes, and haven't been expanded yet.
 *
 * Re-broadcasts to geohash-4 FCM topics (~20km radius per cell) to reach
 * drivers farther away. Phase 1 uses geohash-5 (~5km).
 */
exports.expandRideSearch = functions.pubsub
  .schedule("* * * * *")
  .onRun(async (context) => {
    const now = Date.now();
    const phase2Start = new Date(now - (3 * 60 * 1000)); // 3 minutes ago
    const phase2End = new Date(now - (5 * 60 * 1000));   // 5 minutes ago (don't expand already expired)

    // Find rides in searching/bidding that are 3-5 min old and not yet expanded
    const searchingSnap = await admin.firestore().collection("rides")
      .where("status", "in", ["searching", "bidding"])
      .where("createdAt", "<", admin.firestore.Timestamp.fromDate(phase2Start))
      .where("createdAt", ">", admin.firestore.Timestamp.fromDate(phase2End))
      .get();

    if (searchingSnap.empty) return null;

    let expandedCount = 0;

    for (const doc of searchingSnap.docs) {
      const data = doc.data();

      // Skip if already expanded
      if (data.expandedSearch === true) continue;

      // Need pickup location for geohash
      if (!data.pickup || !data.pickup.lat || !data.pickup.lng) continue;

      const lat = data.pickup.lat;
      const lng = data.pickup.lng;
      const vehicleType = data.vehicleType || "auto";
      const rideId = doc.id;

      // Compute geohash-4 (wider area)
      const centerHash4 = ngeohash.encode(lat, lng, 4);
      const neighbors4 = ngeohash.neighbors(centerHash4);
      const expandedHashes = [centerHash4, ...neighbors4];

      // Update RTDB signal with expanded target hashes
      try {
        const signalRef = admin.database().ref(`ride_signals/${rideId}`);
        const signalSnap = await signalRef.once("value");
        if (signalSnap.exists()) {
          const existing = signalSnap.val();
          const allHashes = [...new Set([...(existing.targetHashes || []), ...expandedHashes])];
          await signalRef.update({ targetHashes: allHashes, expanded: true });
        }
      } catch (e) {
        console.error(`Failed to update RTDB signal for ride ${rideId}:`, e);
      }

      // Send FCM wakeup to wider geohash-4 zones
      const pickupName = (data.pickup && data.pickup.short_name) || "Nearby";
      const dropName = (data.drop && data.drop.short_name) || "Destination";
      const fareLabel = data.riderBid ? `₹${data.riderBid}` : "Open bid";

      // FCM condition: max 5 conditions per message, we have 9 hashes → 2 chunks
      const chunk1 = expandedHashes.slice(0, 5);
      const chunk2 = expandedHashes.slice(5, 9);

      const sendExpanded = async (hashes) => {
        if (hashes.length === 0) return;
        const condition = hashes.map(h => `'zone_${h}_${vehicleType}' in topics`).join(" || ");
        try {
          await admin.messaging().send({
            condition,
            notification: {
              title: `${vehicleType} ride nearby — ${fareLabel}`,
              body: `${pickupName} → ${dropName} (expanded search)`,
            },
            data: { type: "new_ride", rideId },
            android: {
              priority: "high",
              notification: {
                channelId: "ride_alerts",
                sound: "default",
                priority: "high",
              },
            },
          });
        } catch (e) {
          console.error("Expanded FCM Send Error:", e);
        }
      };

      await sendExpanded(chunk1);
      await sendExpanded(chunk2);

      // Mark as expanded in Firestore
      await doc.ref.update({ expandedSearch: true });
      expandedCount++;
    }

    if (expandedCount > 0) {
      console.log(`Expanded search for ${expandedCount} rides to geohash-4 zones.`);
    }
    return null;
  });

/**
 * cleanupExpiredRides
 * Runs every minute to find rides stuck in "searching" or "bidding" for more
 * than 5 minutes and marks them as "expired". Also cleans up the RTDB signal.
 */
exports.cleanupExpiredRides = functions.pubsub
  .schedule("* * * * *") // Every minute
  .onRun(async (context) => {
    const expiryTimeMs = Date.now() - (5 * 60 * 1000); // 5 minutes ago
    const expiryDate = new Date(expiryTimeMs);

    // Expire rides in both "searching" and "bidding" status
    const expiredSnapshot = await admin.firestore().collection("rides")
      .where("status", "in", ["searching", "bidding"])
      .where("createdAt", "<", admin.firestore.Timestamp.fromDate(expiryDate))
      .get();

    if (expiredSnapshot.empty) return null;

    const batch = admin.firestore().batch();
    const promises = [];

    expiredSnapshot.docs.forEach((doc) => {
      const rideId = doc.id;
      // Update firestore status
      batch.update(doc.ref, { status: "expired" });
      
      // Delete from RTDB
      promises.push(admin.database().ref(`ride_signals/${rideId}`).remove());
    });

    promises.push(batch.commit());
    await Promise.all(promises);
    console.log(`Cleaned up ${expiredSnapshot.size} expired rides.`);
    return null;
  });

/**
 * cleanupStaleAcceptedRides
 * Runs every 5 minutes. Finds rides stuck in "matched" for > 60 minutes
 * and marks them as "cancelled" due to staleness.
 */
exports.cleanupStaleAcceptedRides = functions.pubsub
  .schedule("*/5 * * * *") // Every 5 minutes
  .onRun(async (context) => {
    const staleTimeMs = Date.now() - (60 * 60 * 1000); // 60 minutes ago
    const staleDate = new Date(staleTimeMs);

    const staleSnapshot = await admin.firestore().collection("rides")
      .where("status", "==", "matched")
      .where("createdAt", "<", admin.firestore.Timestamp.fromDate(staleDate))
      .get();

    if (staleSnapshot.empty) return null;

    const batch = admin.firestore().batch();
    const promises = [];

    staleSnapshot.docs.forEach((doc) => {
      const data = doc.data();
      const rideId = doc.id;
      // Update firestore status
      batch.update(doc.ref, { 
        status: "cancelled",
        cancelReason: "server_stale_cleanup",
        cancelledAt: admin.firestore.FieldValue.serverTimestamp()
      });

      // Reset driver status if matched
      if (data.driverId) {
        batch.update(admin.firestore().collection("drivers").doc(data.driverId), {
          driverState: "ONLINE_IDLE",
          activeRideId: null,
          activeBidCount: 0,
        });
      }
      
      // Delete from RTDB just in case
      promises.push(admin.database().ref(`ride_signals/${rideId}`).remove());
    });

    promises.push(batch.commit());
    await Promise.all(promises);
    console.log(`Cleaned up ${staleSnapshot.size} stale matched rides and reset drivers.`);
    return null;
  });

/**
 * dailyEarningsSummary
 * Sends a daily earnings report to admins. Runs at 11:59 PM.
 */
exports.dailyEarningsSummary = functions.pubsub
  .schedule("59 23 * * *")
  .timeZone("Asia/Kolkata")
  .onRun(async (context) => {
    // Basic daily earnings summary notification
    await admin.messaging().send({
      topic: "admins",
      notification: {
        title: "Daily Earnings Summary",
        body: "Check the Admin Panel for today's earnings report.",
      },
      data: { type: "daily_earnings" },
    });
  });
