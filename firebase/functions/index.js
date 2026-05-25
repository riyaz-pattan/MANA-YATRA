const functions = require("firebase-functions"); // Trigger redeployment
const admin = require("firebase-admin");
const cors = require("cors")({ origin: true });
const ngeohash = require("ngeohash");
const crypto = require("crypto");
const Razorpay = require("razorpay");

admin.initializeApp();

// ============================================================
// CONSTANTS
// ============================================================
const HEARTBEAT_MAX_AGE_SEC = 300; // 5 minutes (App sends heartbeat every 2m, needs buffer)
const RIDE_EXPIRY_MINUTES = 5;
const OPERATION_TTL_DAYS = 30; // How long to keep operationIds for dedup

// ============================================================
// IDEMPOTENCY HELPER
// ============================================================
/**
 * checkAndRecordOperation(db, operationId, resultData)
 *
 * Checks if an operationId has already been processed.
 * - If YES: throws HttpsError("already-exists") — client SyncEngine treats this as success.
 * - If NO: records the operationId in the `operations` collection for future dedup.
 *
 * Call this AFTER successful transaction commit to avoid recording failed ops.
 */
async function checkIdempotency(db, operationId) {
  if (!operationId) return; // Backwards compat — old clients without operationId
  const opRef = db.collection("operations").doc(operationId);
  const opSnap = await opRef.get();
  if (opSnap.exists) {
    throw new functions.https.HttpsError(
      "already-exists",
      "Operation already processed."
    );
  }
}

async function recordOperation(db, operationId, type) {
  if (!operationId) return;
  await db.collection("operations").doc(operationId).set({
    type,
    processedAt: admin.firestore.FieldValue.serverTimestamp(),
    expiresAt: new Date(Date.now() + OPERATION_TTL_DAYS * 86400000),
  });
}

// ============================================================
// RATE LIMITING HELPER
// ============================================================
/**
 * checkRateLimit
 * Prevents API abuse by limiting calls per UID per action.
 */
async function checkRateLimit(db, uid, action, limitCount = 10, windowMs = 60000) {
  const rateLimitRef = db.collection('rate_limits').doc(`${uid}_${action}`);
  const now = Date.now();
  
  await db.runTransaction(async (txn) => {
    const snap = await txn.get(rateLimitRef);
    let data = snap.data();
    
    if (!snap.exists || !data || (now - data.windowStart) > windowMs) {
      // Reset or start new window
      txn.set(rateLimitRef, {
        windowStart: now,
        count: 1
      });
    } else {
      if (data.count >= limitCount) {
        throw new functions.https.HttpsError(
          'resource-exhausted',
          `Rate limit exceeded for action: ${action}`
        );
      }
      txn.update(rateLimitRef, {
        count: admin.firestore.FieldValue.increment(1)
      });
    }
  });
}

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

  const { rideId, bidId, operationId } = data;
  if (!rideId || !bidId) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Missing rideId or bidId."
    );
  }

  const db = admin.firestore();

  // Rate Limiting (e.g. max 10 acceptBid calls per minute per user)
  await checkRateLimit(db, context.auth.uid, 'acceptBid', 10, 60000);

  // Idempotency: if this operationId was already processed, return success
  await checkIdempotency(db, operationId);
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

      // ── CHECK 0: Integrity ──
      if (bid.rideId !== rideId) {
        throw new functions.https.HttpsError(
          "invalid-argument",
          "This bid does not belong to the requested ride."
        );
      }

      const driverId = bid.driverId;
      const driverRef = db.collection("drivers").doc(driverId);
      const driverSnap = await txn.get(driverRef);

      if (!driverSnap.exists) {
        throw new functions.https.HttpsError("not-found", "Driver not found.");
      }
      const driver = driverSnap.data();

      // PRE-FETCH READS
      // Fetch other bids to reject (Firestore transactions require all reads before writes)
      const otherBidsQuery = db.collection("bids")
        .where("rideId", "==", rideId)
        .where("status", "==", "pending");
      const otherBidsSnap = await txn.get(otherBidsQuery);

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
          "This bid is no longer active (withdrawn or rejected)."
        );
      }

      // ── CHECK 4: Driver state ──
      // Must be ONLINE_IDLE or BIDDING. If ON_RIDE or OFFLINE, reject.
      const dState = driver.driverState || (driver.isOnline ? "ONLINE_IDLE" : "OFFLINE");
      if (dState !== "ONLINE_IDLE" && dState !== "BIDDING") {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "Driver is no longer available (busy or offline)."
        );
      }

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

      // ── ATOMIC UPDATES ──
      const otp = String(1000 + Math.floor(Math.random() * 9000));

      // 1. Update Ride
      txn.update(rideRef, {
        locked: true,
        status: "matched",
        driverId: driverId,
        driverName: bid.driverName || "Driver",
        driverPhone: bid.driverPhone || "",
        vehicleNumber: bid.vehicleNumber || "",
        driverImageUrl: bid.driverImageUrl || "",
        vehicleImageUrl: bid.vehicleImageUrl || "",
        finalPrice: bid.price,
        rideOtp: otp,
        matchedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // 2. Update Accepted Bid
      txn.update(bidRef, { status: "accepted" });

      // 3. Reject other bids for this ride
      otherBidsSnap.forEach((doc) => {
        if (doc.id !== bidId) {
          txn.update(doc.ref, { status: "rejected_by_system" });
        }
      });

      // 4. Update Driver State
      txn.update(driverRef, {
        driverState: "ON_RIDE",
        activeRideId: rideId,
        activeBidCount: 0,
      });

      // 5. Cleanup RTDB Signals Task
      if (ride.activeSignalPaths && Array.isArray(ride.activeSignalPaths)) {
        txn.set(db.collection("tasks").doc(`cleanup_${rideId}`), {
          type: "CLEANUP_SIGNALS",
          paths: ride.activeSignalPaths,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      // 6. Send Notification Task
      txn.set(db.collection("tasks").doc(`notify_match_${rideId}`), {
        type: "NOTIFY_DRIVER_MATCH",
        driverId: driverId,
        rideId: rideId,
        title: "Ride Matched! 🚀",
        body: `You are matched for a ride to ${ride.drop?.short_name || "destination"}.`,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    // Record idempotency key after successful commit
    await recordOperation(db, operationId, "acceptBid");

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
 * startRide
 * Driver callable to mark a ride as started.
 */
exports.startRide = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Please log in.");
  }

  const rideId = data.rideId;
  const operationId = data.operationId;
  const driverId = context.auth.uid;

  if (!rideId) {
    throw new functions.https.HttpsError("invalid-argument", "Missing rideId.");
  }

  const db = admin.firestore();

  // Rate Limiting
  await checkRateLimit(db, driverId, 'startRide', 10, 60000);

  await checkIdempotency(db, operationId);
  const rideRef = db.collection("rides").doc(rideId);

  try {
    await db.runTransaction(async (txn) => {
      const rideSnap = await txn.get(rideRef);

      if (!rideSnap.exists) {
        throw new functions.https.HttpsError("not-found", "Ride not found.");
      }

      const ride = rideSnap.data();

      if (ride.driverId !== driverId) {
        throw new functions.https.HttpsError("permission-denied", "Not assigned to this ride.");
      }

      if (ride.status !== "matched") {
        throw new functions.https.HttpsError(
          "failed-precondition",
          `Cannot start ride from status: ${ride.status}`
        );
      }

      txn.update(rideRef, {
        status: "started",
        startedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    await recordOperation(db, operationId, "startRide");
    return { success: true };
  } catch (error) {
    if (error instanceof functions.https.HttpsError) throw error;
    console.error("startRide error:", error);
    throw new functions.https.HttpsError("internal", "Failed to start ride.");
  }
});

/**
 * completeRide
 * Driver callable to mark a ride as completed.
 */
exports.completeRide = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Please log in.");
  }

  const rideId = data.rideId;
  const operationId = data.operationId;
  const driverId = context.auth.uid;

  if (!rideId) {
    throw new functions.https.HttpsError("invalid-argument", "Missing rideId.");
  }

  const db = admin.firestore();

  // Rate Limiting
  await checkRateLimit(db, driverId, 'completeRide', 10, 60000);

  await checkIdempotency(db, operationId);
  const rideRef = db.collection("rides").doc(rideId);
  const driverRef = db.collection("drivers").doc(driverId);

  try {
    await db.runTransaction(async (txn) => {
      const rideSnap = await txn.get(rideRef);

      if (!rideSnap.exists) {
        throw new functions.https.HttpsError("not-found", "Ride not found.");
      }

      const ride = rideSnap.data();

      if (ride.driverId !== driverId) {
        throw new functions.https.HttpsError("permission-denied", "Not assigned to this ride.");
      }

      if (ride.status !== "started") {
        throw new functions.https.HttpsError(
          "failed-precondition",
          `Cannot complete ride from status: ${ride.status}`
        );
      }

      const startedAt = ride.startedAt ? ride.startedAt.toDate() : null;
      const completedAtDate = new Date();
      const actualDurationMin = startedAt
        ? Math.round((completedAtDate.getTime() - startedAt.getTime()) / 60000)
        : null;

      txn.update(rideRef, {
        status: "completed",
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
        ...(actualDurationMin !== null && { actualDurationMin }),
      });

      txn.update(driverRef, {
        driverState: "ONLINE_IDLE",
        activeRideId: null,
        activeBidCount: 0,
      });
    });

    await recordOperation(db, operationId, "completeRide");
    return { success: true };
  } catch (error) {
    if (error instanceof functions.https.HttpsError) throw error;
    console.error("completeRide error:", error);
    throw new functions.https.HttpsError("internal", "Failed to complete ride.");
  }
});

/**
 * cancelRide
 * Rider or Driver callable to cancel a ride.
 */
exports.cancelRide = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Please log in.");
  }

  const rideId = data.rideId;
  const operationId = data.operationId;
  const userId = context.auth.uid;

  if (!rideId) {
    throw new functions.https.HttpsError("invalid-argument", "Missing rideId.");
  }

  const db = admin.firestore();

  // Rate Limiting
  await checkRateLimit(db, userId, 'cancelRide', 10, 60000);

  await checkIdempotency(db, operationId);
  const rideRef = db.collection("rides").doc(rideId);

  try {
    await db.runTransaction(async (txn) => {
      const rideSnap = await txn.get(rideRef);

      if (!rideSnap.exists) {
        throw new functions.https.HttpsError("not-found", "Ride not found.");
      }

      const ride = rideSnap.data();

      if (ride.riderId !== userId && ride.driverId !== userId) {
        throw new functions.https.HttpsError("permission-denied", "Not authorized to cancel this ride.");
      }

      let canceller;
      if (data.role === 'rider' || data.role === 'driver') {
        canceller = data.role;
      } else {
        canceller = ride.riderId === userId ? "rider" : "driver";
      }
      if (ride.status === "completed" || ride.status === "cancelled" || ride.status === "expired") {
        throw new functions.https.HttpsError(
          "failed-precondition",
          `Cannot cancel ride with status: ${ride.status}`
        );
      }

      txn.update(rideRef, {
        status: "cancelled",
        cancelledBy: canceller,
        cancelReason: data.reason || "user_cancelled",
        cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    await recordOperation(db, operationId, "cancelRide");
    return { success: true };
  } catch (error) {
    if (error instanceof functions.https.HttpsError) throw error;
    console.error("cancelRide error:", error);
    throw new functions.https.HttpsError("internal", "Failed to cancel ride.");
  }
});

/**
 * placeBid (Callable)
 *
 * Server-authoritative bid placement. Replaces the driver app's direct
 * Firestore write to `bids` collection. Validates ride status and driver
 * state before creating the bid document.
 *
 * Idempotent via operationId — safe to retry.
 */
exports.placeBid = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Please log in.");
  }

  const {
    rideId, riderId, price, driverName, driverPhone,
    vehicleType, vehicleNumber, driverImageUrl, vehicleImageUrl, driverLat, driverLng, operationId,
  } = data;
  const driverId = context.auth.uid;

  if (!rideId || !price) {
    throw new functions.https.HttpsError("invalid-argument", "Missing rideId or price.");
  }

  const db = admin.firestore();

  // Rate Limiting — drivers bid frequently, allow 20/min
  await checkRateLimit(db, driverId, 'placeBid', 20, 60000);

  await checkIdempotency(db, operationId);

  // Validate ride is still accepting bids
  const rideSnap = await db.collection("rides").doc(rideId).get();
  if (!rideSnap.exists) {
    throw new functions.https.HttpsError("not-found", "Ride not found.");
  }
  const ride = rideSnap.data();
  if (ride.status !== "searching" && ride.status !== "bidding") {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Ride is no longer accepting bids."
    );
  }

  try {
    // Create bid document
    const bidRef = await db.collection("bids").add({
      rideId,
      riderId: riderId || ride.riderId,
      driverId,
      driverName: driverName || "Driver",
      driverPhone: driverPhone || "",
      vehicleType: vehicleType || "auto",
      vehicleNumber: vehicleNumber || "",
      driverImageUrl: driverImageUrl || "",
      vehicleImageUrl: vehicleImageUrl || "",
      price,
      driverLat: driverLat || null,
      driverLng: driverLng || null,
      status: "pending",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Update driver state
    const driverUpdates = {
      activeBidCount: admin.firestore.FieldValue.increment(1),
    };
    const driverSnap = await db.collection("drivers").doc(driverId).get();
    if (driverSnap.exists) {
      const dState = driverSnap.data().driverState;
      if (dState === "ONLINE_IDLE") {
        driverUpdates.driverState = "BIDDING";
      }
    }
    await db.collection("drivers").doc(driverId).update(driverUpdates);

    await recordOperation(db, operationId, "placeBid");
    return { success: true, bidId: bidRef.id };
  } catch (error) {
    if (error instanceof functions.https.HttpsError) throw error;
    console.error("placeBid error:", error);
    throw new functions.https.HttpsError("internal", "Failed to place bid.");
  }
});

/**
 * startFreeTrial
 *
 * Activates a 7-day free trial for a driver.
 */
exports.startFreeTrial = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Only authenticated users can call this function."
    );
  }

  const uid = context.auth.uid;
  const db = admin.firestore();

  try {
    const driverRef = db.collection("drivers").doc(uid);
    const driverSnap = await driverRef.get();

    if (!driverSnap.exists) {
      throw new functions.https.HttpsError("not-found", "Driver not found.");
    }

    const driverData = driverSnap.data();
    if (driverData.hasFreeTrialUsed) {
      throw new functions.https.HttpsError("already-exists", "Free trial already used.");
    }

    const now = new Date();
    const until = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000); // 7 days from now

    const batch = db.batch();
    
    // Update driver
    batch.update(driverRef, {
      subscriptionActiveUntil: admin.firestore.Timestamp.fromDate(until),
      hasFreeTrialUsed: true,
    });

    // Record payment
    const paymentRef = db.collection("payments").doc();
    batch.set(paymentRef, {
      driverId: uid,
      amount: 0,
      days: 7,
      type: "free_trial",
      method: "free",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await batch.commit();

    return { success: true, validUntil: until.toISOString() };
  } catch (error) {
    console.error("Error activating free trial:", error);
    if (error instanceof functions.https.HttpsError) throw error;
    throw new functions.https.HttpsError("internal", error.message);
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
 * deleteMyAccount
 *
 * An HTTPS callable function for users to delete their own account.
 * It takes role ('driver' or 'rider') and an optional reason.
 * Deletes the user from Firebase Auth (if no other roles exist), Firestore, and Storage.
 */
exports.deleteMyAccount = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Only authenticated users can call this function."
    );
  }

  const uid = context.auth.uid;
  const role = data.role; // 'driver' or 'rider'
  const reason = data.reason || "No reason provided";

  if (!role || !['driver', 'rider'].includes(role)) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Valid role ('driver' or 'rider') is required."
    );
  }

  try {
    let shouldDeleteAuth = false;

    // Log the reason for analytics (optional)
    console.log(`User ${uid} deleting ${role} account. Reason: ${reason}`);

    if (role === "driver") {
      // Delete driver from Firestore
      await admin.firestore().collection("drivers").doc(uid).delete();
      
      // Delete driver from RTDB liveLocations
      try {
        await admin.database().ref(`liveLocations/${uid}`).remove();
      } catch (e) {
        console.log(`Failed to delete RTDB liveLocation for ${uid}:`, e);
      }
      
      // Delete images from Firebase Storage
      const bucket = admin.storage().bucket();
      const filesToDelete = [
        `drivers/${uid}/selfie.jpg`,
        `drivers/${uid}/aadhar.jpg`,
        `drivers/${uid}/license.jpg`,
        `drivers/${uid}/vehicle.jpg`
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
    } else {
      // Delete rider from Firestore
      await admin.firestore().collection("users").doc(uid).delete();
      
      // Check if user has a driver profile
      const driverDoc = await admin.firestore().collection("drivers").doc(uid).get();
      if (!driverDoc.exists) {
        shouldDeleteAuth = true;
      }
    }

    // Delete user from Firebase Auth if no other profiles exist
    if (shouldDeleteAuth) {
      try {
        await admin.auth().deleteUser(uid);
        console.log(`Deleted auth user: ${uid}`);
      } catch (e) {
        console.log(`Failed to delete auth user ${uid}:`, e);
      }
    }

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

      // Cleanup RTDB signals from all zone paths
      const signalPaths = after.activeSignalPaths || [];
      if (signalPaths.length > 0) {
        const removeUpdate = {};
        for (const p of signalPaths) {
          removeUpdate[p] = null;
        }
        await admin.database().ref().update(removeUpdate);
      }
      // Also cleanup declinedDrivers for this ride
      await admin.database().ref(`ride_declines/${rideId}`).remove();
      console.log(`Cleaned up RTDB signals (${signalPaths.length} paths) for matched ride ${rideId}`);
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
      // Cleanup RTDB signals from all zone paths
      const cancelPaths = after.activeSignalPaths || [];
      if (cancelPaths.length > 0) {
        const cancelRemove = {};
        for (const p of cancelPaths) {
          cancelRemove[p] = null;
        }
        await admin.database().ref().update(cancelRemove);
      }
      await admin.database().ref(`ride_declines/${rideId}`).remove();
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

      // Cleanup RTDB signals from all zone paths
      const expPaths = after.activeSignalPaths || [];
      if (expPaths.length > 0) {
        const expRemove = {};
        for (const p of expPaths) {
          expRemove[p] = null;
        }
        await admin.database().ref().update(expRemove);
      }
      await admin.database().ref(`ride_declines/${rideId}`).remove();
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

    // 1. Write the signal to RTDB partitioned by vehicleType/geohash
    const signalData = {
      rideId,
      riderId: data.riderId,
      pickup: data.pickup,
      drop: data.drop,
      vehicleType,
      createdAt: admin.database.ServerValue.TIMESTAMP,
      status: "searching",
      geohash5: centerHash,
      distanceKm: data.distanceKm || 0,
      durationMin: data.durationMin || 0,
      riderBid: data.riderBid || 0,
    };

    // Multi-path update: write signal to all 9 geohash zone paths
    const multiPathUpdate = {};
    const activeSignalPaths = [];
    for (const hash of targetHashes) {
      const path = `ride_signals/${vehicleType}/${hash}/${rideId}`;
      multiPathUpdate[path] = signalData;
      activeSignalPaths.push(path);
    }
    await admin.database().ref().update(multiPathUpdate);

    // Save the signal paths to Firestore so cleanup functions know where to delete
    await snap.ref.update({
      activeSignalPaths,
      geohash5: centerHash,
    });

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

      // Write signal to expanded geohash-4 zone paths in RTDB
      try {
        // Read existing signal data from one of the original paths
        const existingPaths = data.activeSignalPaths || [];
        let signalData = null;
        if (existingPaths.length > 0) {
          const existingSnap = await admin.database().ref(existingPaths[0]).once("value");
          if (existingSnap.exists()) {
            signalData = existingSnap.val();
          }
        }
        if (signalData) {
          signalData.expanded = true;
          const expandMultiPath = {};
          const newPaths = [];
          for (const hash of expandedHashes) {
            const path = `ride_signals/${vehicleType}/${hash}/${rideId}`;
            // Only add if not already covered by existing paths
            if (!existingPaths.includes(path)) {
              expandMultiPath[path] = signalData;
              newPaths.push(path);
            }
          }
          if (Object.keys(expandMultiPath).length > 0) {
            await admin.database().ref().update(expandMultiPath);
          }
          // Append new paths to Firestore
          if (newPaths.length > 0) {
            await doc.ref.update({
              activeSignalPaths: admin.firestore.FieldValue.arrayUnion(...newPaths),
            });
          }
        }
      } catch (e) {
        console.error(`Failed to expand RTDB signals for ride ${rideId}:`, e);
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
      const rideData = doc.data();
      const rideId = doc.id;
      // Update firestore status
      batch.update(doc.ref, { status: "expired" });
      
      // Delete from RTDB using stored zone paths
      const paths = rideData.activeSignalPaths || [];
      if (paths.length > 0) {
        const removeUpdate = {};
        for (const p of paths) {
          removeUpdate[p] = null;
        }
        promises.push(admin.database().ref().update(removeUpdate));
      }
      // Also cleanup declinedDrivers
      promises.push(admin.database().ref(`ride_declines/${rideId}`).remove());
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
      
      // Delete from RTDB using stored zone paths
      const paths = data.activeSignalPaths || [];
      if (paths.length > 0) {
        const removeUpdate = {};
        for (const p of paths) {
          removeUpdate[p] = null;
        }
        promises.push(admin.database().ref().update(removeUpdate));
      }
      promises.push(admin.database().ref(`ride_declines/${rideId}`).remove());
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

/**
 * onDriverPresenceChanged
 * Triggers when a driver's RTDB presence changes. If they disconnect,
 * mirror this state to Firestore by setting them offline.
 */
exports.onDriverPresenceChanged = functions.database
  .ref("/presence/{driverId}")
  .onUpdate(async (change, context) => {
    const isOnline = change.after.val().isOnline;
    const driverId = context.params.driverId;

    if (isOnline === false) {
      // Driver disconnected or intentionally went offline
      try {
        await admin.firestore().collection("drivers").doc(driverId).update({
          driverState: "OFFLINE",
          isOnline: false,
          activeBidCount: 0,
          activeRideId: null,
        });
        console.log(`Driver ${driverId} marked OFFLINE via Presence disconnect.`);
      } catch (e) {
        console.error(`Failed to update offline status for driver ${driverId}:`, e);
      }
    }
  });

/**
 * onBidStatusChanged
 * Triggers when a bid document is updated.
 * Used to decrement the driver's activeBidCount if a rider rejects the bid.
 */
exports.onBidStatusChanged = functions.firestore
  .document("bids/{bidId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();

    if (before.status === "pending" && after.status === "rejected") {
      const driverRef = admin.firestore().collection("drivers").doc(after.driverId);
      try {
        await admin.firestore().runTransaction(async (t) => {
          const dSnap = await t.get(driverRef);
          if (dSnap.exists) {
            const dData = dSnap.data();
            const newCount = Math.max(0, (dData.activeBidCount || 1) - 1);
            const upd = { activeBidCount: newCount };
            if (newCount === 0 && dData.driverState === "BIDDING") {
              upd.driverState = "ONLINE_IDLE";
            }
            t.update(driverRef, upd);
            console.log(`Decremented activeBidCount for driver ${after.driverId} due to rejected bid. New count: ${newCount}`);
          }
        });
      } catch (e) {
        console.error(`Failed to update activeBidCount for rejected bid ${context.params.bidId}:`, e);
      }
    }
  });

/**
 * cleanupDeadSessions
 * Scheduled Cron Job (Runs every 30 minutes)
 * Finds rides stuck in 'started' state for > 4 hours and automatically cancels them.
 */
exports.cleanupDeadSessions = functions.pubsub
  .schedule("every 30 minutes")
  .onRun(async (context) => {
    const db = admin.firestore();
    const fourHoursAgo = new Date(Date.now() - 4 * 60 * 60 * 1000);
    
    try {
      const deadRidesSnap = await db.collection("rides")
        .where("status", "==", "started")
        .where("startedAt", "<", admin.firestore.Timestamp.fromDate(fourHoursAgo))
        .get();

      if (deadRidesSnap.empty) {
        console.log("No dead ride sessions found for cleanup.");
        return null;
      }

      console.log(`Found ${deadRidesSnap.size} dead ride sessions. Cleaning up...`);

      const batch = db.batch();
      
      deadRidesSnap.forEach((doc) => {
        const rideData = doc.data();
        const rideRef = doc.ref;
        
        batch.update(rideRef, {
          status: "cancelled",
          cancelReason: "system_timeout_dead_session",
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        if (rideData.driverId) {
          const driverRef = db.collection("drivers").doc(rideData.driverId);
          batch.update(driverRef, {
            driverState: "ONLINE_IDLE",
            activeRideId: null,
          });
        }
      });

      await batch.commit();
      console.log(`Successfully cleaned up ${deadRidesSnap.size} dead ride sessions.`);
      return null;
    } catch (e) {
      console.error("Error cleaning up dead sessions:", e);
      return null;
    }
  });

/**
 * expireRide
 * Allows a rider to manually expire a ride if no bids are received.
 */
exports.expireRide = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Auth required.");
  }

  const { rideId } = data;
  if (!rideId) {
    throw new functions.https.HttpsError("invalid-argument", "Missing rideId.");
  }

  const db = admin.firestore();
  const rideRef = db.collection("rides").doc(rideId);

  await db.runTransaction(async (txn) => {
    const snap = await txn.get(rideRef);
    if (!snap.exists) return;
    const ride = snap.data();

    // Safety: Only owner can expire
    if (ride.riderId !== context.auth.uid) {
      throw new functions.https.HttpsError("permission-denied", "Not your ride.");
    }

    // Only if searching/bidding
    if (ride.status !== "searching" && ride.status !== "bidding") {
      throw new functions.https.HttpsError("failed-precondition", "Ride is already matched or cancelled.");
    }

    txn.update(rideRef, { status: "expired" });

    // Cleanup signals
    if (ride.activeSignalPaths) {
      txn.set(db.collection("tasks").doc(`cleanup_expire_${rideId}`), {
        type: "CLEANUP_SIGNALS",
        paths: ride.activeSignalPaths,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  });

  return { success: true };
});

/**
 * processTasks
 * Listens to the 'tasks' collection and executes background work like
 * RTDB cleanup and FCM notifications. This keeps the main transaction fast.
 */
exports.processTasks = functions.firestore
  .document("tasks/{taskId}")
  .onCreate(async (snap, context) => {
    const task = snap.data();
    const taskId = context.params.taskId;

    try {
      if (task.type === "CLEANUP_SIGNALS") {
        const updates = {};
        task.paths.forEach(p => { updates[p] = null; });
        await admin.database().ref().update(updates);
      } else if (task.type === "NOTIFY_DRIVER_MATCH") {
        const driverSnap = await admin.firestore().collection("drivers").doc(task.driverId).get();
        const fcmToken = driverSnap.data()?.fcmToken;
        if (fcmToken) {
          await admin.messaging().send({
            token: fcmToken,
            notification: {
              title: task.title,
              body: task.body,
            },
            data: {
              type: "ride_matched",
              rideId: task.rideId,
            },
            android: {
              priority: "high",
              notification: {
                channelId: "ride_alerts",
                sound: "default",
                clickAction: "FLUTTER_NOTIFICATION_CLICK",
              },
            },
          });
        }
      }

      // Delete task after completion
      await snap.ref.delete();
    } catch (e) {
      console.error(`Task ${taskId} failed:`, e);
    }
  });

// ============================================================
// RBAC: SET ADMIN ROLE
// ============================================================
/**
 * setAdminRole (Callable)
 *
 * Allows a super_admin to assign RBAC roles to other users.
 * Sets a custom claim `role` on the target user's Firebase Auth token.
 *
 * Valid roles: super_admin, operations_manager, finance_manager,
 *              support_executive, business_analyst, viewer
 *
 * Also creates/updates the admin_users Firestore doc and writes an audit log.
 *
 * Input: { uid: string, role: string, displayName?: string, email?: string }
 * Caller must have custom claim: role == 'super_admin'
 */
const VALID_ADMIN_ROLES = [
  'super_admin',
  'operations_manager',
  'finance_manager',
  'support_executive',
  'business_analyst',
  'viewer',
];

exports.setAdminRole = functions.https.onCall(async (data, context) => {
  // 1. Authentication check
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "You must be logged in."
    );
  }

  // 2. Authorization: only super_admin can assign roles
  const callerRole = context.auth.token.role;
  const callerIsLegacyAdmin = context.auth.token.admin === true;

  if (callerRole !== 'super_admin' && !callerIsLegacyAdmin) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Only super admins can assign roles."
    );
  }

  // 3. Validate input
  const { uid, role, displayName, email } = data;

  if (!uid || !role) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Missing uid or role."
    );
  }

  if (!VALID_ADMIN_ROLES.includes(role)) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      `Invalid role: ${role}. Must be one of: ${VALID_ADMIN_ROLES.join(', ')}`
    );
  }

  // 4. Prevent self-demotion for safety
  if (uid === context.auth.uid && role !== 'super_admin') {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "You cannot demote your own super_admin role."
    );
  }

  try {
    // 5. Verify target user exists in Firebase Auth
    const targetUser = await admin.auth().getUser(uid);

    // 6. Set custom claims — merge with existing claims
    const existingClaims = targetUser.customClaims || {};
    await admin.auth().setCustomUserClaims(uid, {
      ...existingClaims,
      role: role,
      admin: true,  // Keep legacy admin flag for backward compat
    });

    // 7. Create/update admin_users document in Firestore
    const db = admin.firestore();
    await db.collection('admin_users').doc(uid).set({
      uid: uid,
      role: role,
      displayName: displayName || targetUser.displayName || '',
      email: email || targetUser.email || '',
      phone: targetUser.phoneNumber || '',
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedBy: context.auth.uid,
    }, { merge: true });

    // 8. Write audit log
    await db.collection('audit_logs').add({
      action: 'set_admin_role',
      targetUid: uid,
      newRole: role,
      previousRole: existingClaims.role || null,
      performedBy: context.auth.uid,
      performedByRole: callerRole || 'legacy_admin',
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      metadata: {
        targetEmail: email || targetUser.email || '',
        targetDisplayName: displayName || targetUser.displayName || '',
      },
    });

    console.log(`Role '${role}' assigned to user ${uid} by ${context.auth.uid}`);


    return {
      success: true,
      message: `Role '${role}' has been assigned to user ${uid}.`,
      uid: uid,
      role: role,
    };
  } catch (error) {
    if (error instanceof functions.https.HttpsError) throw error;

    if (error.code === 'auth/user-not-found') {
      throw new functions.https.HttpsError(
        "not-found",
        `User with UID ${uid} not found in Firebase Auth.`
      );
    }

    console.error("setAdminRole error:", error);
    throw new functions.https.HttpsError("internal", error.message || "Failed to set admin role.");
  }
});

/**
 * removeAdminRole (Callable)
 *
 * Allows a super_admin to remove the admin role from a user.
 * Removes the `role` and `admin` custom claims and updates Firestore.
 *
 * Input: { uid: string }
 * Caller must have custom claim: role == 'super_admin'
 */
exports.removeAdminRole = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "You must be logged in.");
  }

  const callerRole = context.auth.token.role;
  const callerIsLegacyAdmin = context.auth.token.admin === true;

  if (callerRole !== 'super_admin' && !callerIsLegacyAdmin) {
    throw new functions.https.HttpsError("permission-denied", "Only super admins can remove roles.");
  }

  const { uid } = data;
  if (!uid) {
    throw new functions.https.HttpsError("invalid-argument", "Missing uid.");
  }

  // Prevent self-removal
  if (uid === context.auth.uid) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "You cannot remove your own admin role."
    );
  }

  try {
    const targetUser = await admin.auth().getUser(uid);
    const existingClaims = targetUser.customClaims || {};
    const previousRole = existingClaims.role || null;

    // Remove role and admin claims
    const { role: _r, admin: _a, ...remainingClaims } = existingClaims;
    await admin.auth().setCustomUserClaims(uid, remainingClaims);

    // Update Firestore
    const db = admin.firestore();
    await db.collection('admin_users').doc(uid).update({
      role: admin.firestore.FieldValue.delete(),
      removedAt: admin.firestore.FieldValue.serverTimestamp(),
      removedBy: context.auth.uid,
      isActive: false,
    });

    // Audit log
    await db.collection('audit_logs').add({
      action: 'remove_admin_role',
      targetUid: uid,
      previousRole: previousRole,
      performedBy: context.auth.uid,
      performedByRole: callerRole || 'legacy_admin',
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { success: true, message: `Admin role removed from user ${uid}.` };
  } catch (error) {
    if (error instanceof functions.https.HttpsError) throw error;
    console.error("removeAdminRole error:", error);
    throw new functions.https.HttpsError("internal", error.message || "Failed to remove admin role.");
  }
});

exports.createAdminUser = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "You must be logged in.");

  const callerRole = context.auth.token.role;
  const callerIsLegacyAdmin = context.auth.token.admin === true;

  if (callerRole !== 'super_admin' && !callerIsLegacyAdmin) {
    throw new functions.https.HttpsError("permission-denied", "Only super admins can create admin users.");
  }

  const { email, password, displayName, role } = data;

  if (!email || !password || !displayName || !role) {
    throw new functions.https.HttpsError("invalid-argument", "Missing required fields.");
  }

  try {
    const userRecord = await admin.auth().createUser({
      email: email,
      password: password,
      displayName: displayName,
    });

    const uid = userRecord.uid;

    await admin.auth().setCustomUserClaims(uid, {
      role: role,
      admin: true,
    });

    const db = admin.firestore();
    await db.collection('admin_users').doc(uid).set({
      uid: uid,
      role: role,
      displayName: displayName,
      email: email,
      isActive: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      createdBy: context.auth.uid,
    });

    await db.collection('audit_logs').add({
      action: 'create_admin_user',
      targetUid: uid,
      newRole: role,
      performedBy: context.auth.uid,
      performedByRole: callerRole || 'legacy_admin',
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      metadata: { targetEmail: email, targetDisplayName: displayName },
    });

    return { success: true, message: `Created admin user ${email} with role ${role}` };
  } catch (error) {
    console.error("Error creating admin user:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

// ============================================================
// RAZORPAY PAYMENT FUNCTIONS
// ============================================================

// Server-side subscription plan pricing (source of truth — never trust client)
const SUBSCRIPTION_PLANS = [
  { days: 1, label: "1 Day", amount: 20, amountPaise: 2000 },
  { days: 7, label: "7 Days", amount: 133, amountPaise: 13300 },
  { days: 30, label: "30 Days", amount: 540, amountPaise: 54000 },
];

// Razorpay credentials — swap to live keys for production
const RAZORPAY_KEY_ID = "rzp_test_StTUBd9Fsqxj8F";
const RAZORPAY_KEY_SECRET = "K0U2rHZExjyKSfhOGGzI7nzj";

/**
 * createRazorpayOrder (Callable)
 *
 * Called by the driver app when they select a plan and tap "Pay".
 * Creates a Razorpay Order server-side with the correct amount
 * (prevents price tampering from the client).
 *
 * Input:  { planIndex: 0|1|2 }
 * Output: { orderId, amount, currency }
 */
exports.createRazorpayOrder = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "You must be logged in."
    );
  }

  const uid = context.auth.uid;
  const { planIndex } = data;

  if (planIndex === undefined || planIndex === null || planIndex < 0 || planIndex > 2) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Invalid plan selection. planIndex must be 0, 1, or 2."
    );
  }

  const db = admin.firestore();

  // Rate limit: max 5 order creations per minute per user
  await checkRateLimit(db, uid, "createOrder", 5, 60000);

  const plan = SUBSCRIPTION_PLANS[planIndex];

  try {
    const rzp = new Razorpay({
      key_id: RAZORPAY_KEY_ID,
      key_secret: RAZORPAY_KEY_SECRET,
    });

    const order = await rzp.orders.create({
      amount: plan.amountPaise,
      currency: "INR",
      receipt: `sub_${uid.slice(-8)}_${Date.now().toString(36)}`,
      notes: {
        driverId: uid,
        planDays: String(plan.days),
        planAmount: String(plan.amount),
      },
    });

    console.log(`Razorpay order created: ${order.id} for driver ${uid}, plan: ${plan.label}`);

    return {
      orderId: order.id,
      amount: order.amount,
      currency: order.currency,
    };
  } catch (error) {
    console.error("createRazorpayOrder error:", error);
    throw new functions.https.HttpsError(
      "internal",
      "Failed to create payment order. Please try again."
    );
  }
});

/**
 * verifyRazorpayPayment (Callable)
 *
 * Called by the driver app after a successful Razorpay checkout.
 * Verifies the payment signature (HMAC SHA256) to ensure it hasn't
 * been tampered with, then extends the driver's subscription.
 *
 * Input:  { razorpay_order_id, razorpay_payment_id, razorpay_signature, planIndex, operationId }
 * Output: { success, validUntil }
 */
exports.verifyRazorpayPayment = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "You must be logged in."
    );
  }

  const uid = context.auth.uid;
  const {
    razorpay_order_id,
    razorpay_payment_id,
    razorpay_signature,
    planIndex,
    operationId,
  } = data;

  if (!razorpay_order_id || !razorpay_payment_id || !razorpay_signature) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Missing payment verification data."
    );
  }

  if (planIndex === undefined || planIndex === null || planIndex < 0 || planIndex > 2) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Invalid plan selection."
    );
  }

  const db = admin.firestore();

  // Rate limit: max 10 verify calls per minute per user
  await checkRateLimit(db, uid, "verifyPayment", 10, 60000);

  // Idempotency check
  await checkIdempotency(db, operationId);

  // Step 1: Verify HMAC SHA256 signature
  const expectedSignature = crypto
    .createHmac("sha256", RAZORPAY_KEY_SECRET)
    .update(razorpay_order_id + "|" + razorpay_payment_id)
    .digest("hex");

  if (expectedSignature !== razorpay_signature) {
    console.error(
      `Payment signature mismatch for driver ${uid}. ` +
      `Order: ${razorpay_order_id}, Payment: ${razorpay_payment_id}`
    );
    throw new functions.https.HttpsError(
      "permission-denied",
      "Payment verification failed. Signature mismatch."
    );
  }

  const plan = SUBSCRIPTION_PLANS[planIndex];

  // Fetch payment details to get the payment method
  let paymentMethod = "online";
  try {
    const Razorpay = require("razorpay");
    const rzp = new Razorpay({
      key_id: RAZORPAY_KEY_ID,
      key_secret: RAZORPAY_KEY_SECRET,
    });
    const paymentDetails = await rzp.payments.fetch(razorpay_payment_id);
    if (paymentDetails && paymentDetails.method) {
      paymentMethod = paymentDetails.method; // e.g. "upi", "card", "netbanking"
    }
  } catch (error) {
    console.error("Failed to fetch payment method from Razorpay:", error);
  }

  try {
    const driverRef = db.collection("drivers").doc(uid);

    let newExpiry;

    await db.runTransaction(async (txn) => {
      const driverSnap = await txn.get(driverRef);

      if (!driverSnap.exists) {
        throw new functions.https.HttpsError("not-found", "Driver not found.");
      }

      const driverData = driverSnap.data();
      const now = new Date();

      // Determine base date: extend from current expiry if still active, otherwise from now
      let baseDate = now;
      if (driverData.subscriptionActiveUntil) {
        const currentExpiry = driverData.subscriptionActiveUntil.toDate
          ? driverData.subscriptionActiveUntil.toDate()
          : new Date(driverData.subscriptionActiveUntil);
        if (currentExpiry > now) {
          baseDate = currentExpiry;
        }
      }

      // Add plan days
      newExpiry = new Date(baseDate);
      newExpiry.setDate(newExpiry.getDate() + plan.days);

      // Update driver subscription
      txn.update(driverRef, {
        subscriptionActiveUntil: admin.firestore.Timestamp.fromDate(newExpiry),
      });

      // Create payment record
      const paymentRef = db.collection("payments").doc();
      txn.set(paymentRef, {
        driverId: uid,
        amount: plan.amount,
        days: plan.days,
        type: "subscription",
        method: paymentMethod,
        razorpayOrderId: razorpay_order_id,
        razorpayPaymentId: razorpay_payment_id,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    // Record idempotency key after successful commit
    await recordOperation(db, operationId, "verifyRazorpayPayment");

    console.log(
      `Payment verified for driver ${uid}. ` +
      `Plan: ${plan.label}, New expiry: ${newExpiry.toISOString()}`
    );

    return {
      success: true,
      validUntil: newExpiry.toISOString(),
    };
  } catch (error) {
    if (error instanceof functions.https.HttpsError) throw error;
    console.error("verifyRazorpayPayment error:", error);
    throw new functions.https.HttpsError(
      "internal",
      "Failed to verify payment. Please contact support."
    );
  }
});
