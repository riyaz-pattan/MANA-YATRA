const functions = require("firebase-functions"); // Trigger redeployment
const admin = require("firebase-admin");
const cors = require("cors")({ origin: true });
const ngeohash = require("ngeohash");

admin.initializeApp();

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

  if (!uid || !requestId) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Missing uid or requestId."
    );
  }

  try {
    // 1. Delete user from Firebase Auth
    await admin.auth().deleteUser(uid);

    // 2. Delete user's document from Firestore
    await admin.firestore().collection("users").doc(uid).delete();

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
 * Also cleans up RTDB signals and other bids when a ride is matched.
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

        // Reject all other pending bids for this ride
        const otherRideBids = await admin.firestore().collection("bids")
          .where("rideId", "==", rideId)
          .where("status", "==", "pending")
          .get();
        
        const rejectBatch = admin.firestore().batch();
        otherRideBids.docs.forEach(doc => {
          rejectBatch.update(doc.ref, { status: "rejected" });
        });
        await rejectBatch.commit();
      }

      // Cleanup RTDB signal
      await admin.database().ref(`ride_signals/${rideId}`).remove();
      console.log(`Cleaned up RTDB signal for matched ride ${rideId}`);
    }

    // 2. Cancellation and Expiration tracking
    if (before.status !== "cancelled" && after.status === "cancelled") {
      if (after.driverId) {
        // Increment total cancelled rides for driver
        await admin.firestore().collection("drivers").doc(after.driverId).update({
          totalCancelledRides: admin.firestore.FieldValue.increment(1)
        });
      }
      // Cleanup RTDB signal just in case
      await admin.database().ref(`ride_signals/${rideId}`).remove();
    } else if (before.status !== "expired" && after.status === "expired") {
      // Cleanup RTDB signal if the ride was locally expired by the app
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
 * cleanupExpiredRides
 * Runs every minute to find rides stuck in "searching" for more than 3 minutes
 * and marks them as "expired". Also cleans up the RTDB signal.
 */
exports.cleanupExpiredRides = functions.pubsub
  .schedule("* * * * *") // Every minute
  .onRun(async (context) => {
    const expiryTimeMs = Date.now() - (3 * 60 * 1000); // 3 minutes ago
    const expiryDate = new Date(expiryTimeMs);

    const expiredSnapshot = await admin.firestore().collection("rides")
      .where("status", "==", "searching")
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
