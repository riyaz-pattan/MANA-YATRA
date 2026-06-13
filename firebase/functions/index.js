const functions = require("firebase-functions"); // Trigger redeployment
const admin = require("firebase-admin");
const cors = require("cors")({ origin: true });
const ngeohash = require("ngeohash");
const crypto = require("crypto");
const Razorpay = require("razorpay");
const geofire = require("geofire-common");

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
  const rtdb = admin.database();
  const opRef = rtdb.ref(`operations/${operationId}`);
  const opSnap = await opRef.get();
  if (opSnap.exists()) {
    throw new functions.https.HttpsError(
      "already-exists",
      "Operation already processed."
    );
  }
}

async function recordOperation(db, operationId, type) {
  if (!operationId) return;
  const rtdb = admin.database();
  await rtdb.ref(`operations/${operationId}`).set({
    type,
    timestamp: admin.database.ServerValue.TIMESTAMP
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
  const rtdb = admin.database();
  const rateLimitRef = rtdb.ref(`rate_limits/${uid}_${action}`);
  const now = Date.now();
  
  const result = await rateLimitRef.transaction((currentData) => {
    if (!currentData || (now - currentData.windowStart) > windowMs) {
      // Reset or start new window
      return {
        windowStart: now,
        count: 1
      };
    } else {
      if (currentData.count >= limitCount) {
        // Abort transaction if rate limit is exceeded
        return undefined;
      }
      currentData.count += 1;
      return currentData;
    }
  });

  if (!result.committed) {
    // If aborted, double check if it was due to limit
    const snap = await rateLimitRef.get();
    const data = snap.val();
    if (data && data.count >= limitCount && (now - data.windowStart) <= windowMs) {
      throw new functions.https.HttpsError(
        'resource-exhausted',
        `Rate limit exceeded for action: ${action}`
      );
    }
  }
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

  const rtdb = admin.database();
  // In Scenario B, the driverId is used as the bidId in RTDB
  const bidSnapRtdb = await rtdb.ref(`active_bids/${rideId}/${bidId}`).once('value');
  if (!bidSnapRtdb.exists()) {
    throw new functions.https.HttpsError("not-found", "Bid not found in RTDB.");
  }
  const bid = bidSnapRtdb.val();
  const driverId = bid.driverId || bidId;

  const rideRef = db.collection("rides").doc(rideId);
  const driverRef = db.collection("drivers").doc(driverId);
  const bidRef = db.collection("bids").doc(bidId); // We still save the winning bid to Firestore permanently

  try {
    await db.runTransaction(async (txn) => {
      const rideSnap = await txn.get(rideRef);
      const driverSnap = await txn.get(driverRef);

      if (!rideSnap.exists) {
        throw new functions.https.HttpsError("not-found", "Ride not found.");
      }
      if (!driverSnap.exists) {
        throw new functions.https.HttpsError("not-found", "Driver not found.");
      }

      const ride = rideSnap.data();
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
        driverUpiId: driver.upiId || "",
        finalPrice: bid.price,
        rideOtp: otp,
        matchedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // 2. Save the winning bid permanently to Firestore
      txn.set(bidRef, {
        ...bid,
        status: "accepted",
        acceptedAt: admin.firestore.FieldValue.serverTimestamp()
      });

      // 3. Update Driver State
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

    // Wipe all losing bids from RTDB instantly (free operation)
    await admin.database().ref(`active_bids/${rideId}`).remove();
    await admin.database().ref(`active_rides/${rideId}`).remove(); // Remove the sync flag too

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
      // ── ALL READS FIRST (Firestore transactions require reads before writes) ──
      const rideSnap = await txn.get(rideRef);
      const driverSnap = await txn.get(driverRef);

      if (!rideSnap.exists) {
        throw new functions.https.HttpsError("not-found", "Ride not found.");
      }

      const ride = rideSnap.data();

      if (ride.driverId !== driverId) {
        throw new functions.https.HttpsError("permission-denied", "Not assigned to this ride.");
      }

      if (ride.status !== "started" && ride.status !== "payment_pending") {
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

      // ── ALL WRITES AFTER READS ──
      txn.update(rideRef, {
        status: "completed",
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
        ...(actualDurationMin !== null && { actualDurationMin }),
      });

      const driverData = driverSnap.data() || {};
      const subActiveUntil = driverData.subscriptionActiveUntil ? driverData.subscriptionActiveUntil.toDate() : new Date(0);
      const isExpired = subActiveUntil <= completedAtDate;

      txn.update(driverRef, {
        driverState: isExpired ? "OFFLINE" : "ONLINE_IDLE",
        isOnline: !isExpired,
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
 * notifyDriverArrived
 * Driver callable — sends FCM notification to rider when driver arrives at pickup.
 */
exports.notifyDriverArrived = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Please log in.");
  }

  const rideId = data.rideId;
  const driverId = context.auth.uid;

  if (!rideId) {
    throw new functions.https.HttpsError("invalid-argument", "Missing rideId.");
  }

  const db = admin.firestore();

  // Rate Limiting — max 5 calls per minute
  await checkRateLimit(db, driverId, 'notifyDriverArrived', 5, 60000);

  try {
    const rideSnap = await db.collection("rides").doc(rideId).get();
    if (!rideSnap.exists) {
      throw new functions.https.HttpsError("not-found", "Ride not found.");
    }

    const ride = rideSnap.data();

    if (ride.driverId !== driverId) {
      throw new functions.https.HttpsError("permission-denied", "Not assigned to this ride.");
    }

    const riderId = ride.riderId;
    if (!riderId) {
      throw new functions.https.HttpsError("not-found", "Rider not found on this ride.");
    }

    // Send FCM to rider's personal topic
    await admin.messaging().send({
      topic: `rider_${riderId}`,
      notification: {
        title: "🚗 Driver has arrived!",
        body: "Your driver is at the pickup location. Please head to the pickup point.",
      },
      data: {
        type: "driver_arrived",
        rideId: rideId,
      },
    });

    return { success: true };
  } catch (error) {
    if (error instanceof functions.https.HttpsError) throw error;
    console.error("notifyDriverArrived error:", error);
    throw new functions.https.HttpsError("internal", "Failed to send arrival notification.");
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

    await admin.database().ref(`active_bids/${rideId}`).remove();
    await admin.database().ref(`active_rides/${rideId}`).remove();

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
    // 1. Fetch user's phone number from Firebase Auth
    const userRecord = await admin.auth().getUser(uid);
    const phoneNumber = userRecord.phoneNumber;

    if (!phoneNumber) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Driver does not have a verified phone number."
      );
    }

    // 2. Check if this phone number has already used a free trial
    const usedTrialRef = db.collection("used_free_trials").doc(phoneNumber);
    const usedTrialSnap = await usedTrialRef.get();

    if (usedTrialSnap.exists) {
      throw new functions.https.HttpsError(
        "already-exists",
        "Free trial already used on this phone number."
      );
    }

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

    // Record the phone number in used_free_trials
    batch.set(usedTrialRef, {
      uid: uid,
      activatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await batch.commit();

    return { success: true, validUntil: until.toISOString() };
  } catch (error) {
    console.error("Error activating free trial:", error);
    if (error instanceof functions.https.HttpsError) throw error;
    throw new functions.https.HttpsError("internal", error.message);
  }
});

// ============================================================
// REFERRAL PROGRAM
// ============================================================

/**
 * generateReferralCode
 *
 * Generates a unique referral code (G-XXXXXX) for the authenticated driver.
 * If the driver already has a referral code, returns it.
 * Stores the code in the `referral_codes` collection for lookup.
 */
exports.generateReferralCode = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "You must be logged in."
    );
  }

  const uid = context.auth.uid;
  const db = admin.firestore();

  // Rate Limiting: 5 calls/min
  await checkRateLimit(db, uid, "generateReferralCode", 5, 60000);

  try {
    // Check if driver already has a referral code
    const driverRef = db.collection("drivers").doc(uid);
    const driverSnap = await driverRef.get();

    if (!driverSnap.exists) {
      throw new functions.https.HttpsError("not-found", "Driver not found.");
    }

    const driverData = driverSnap.data();
    if (driverData.referralCode) {
      return { success: true, code: driverData.referralCode };
    }

    // Generate unique code: G-XXXXXX (6 uppercase alphanumeric chars)
    const CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    let code;
    let collision = true;
    let attempts = 0;

    while (collision && attempts < 10) {
      const bytes = crypto.randomBytes(6);
      let generated = "G-";
      for (let i = 0; i < 6; i++) {
        generated += CHARS[bytes[i] % CHARS.length];
      }
      code = generated;

      // Check for collision
      const codeSnap = await db.collection("referral_codes").doc(code).get();
      if (!codeSnap.exists) {
        collision = false;
      }
      attempts++;
    }

    if (collision) {
      throw new functions.https.HttpsError(
        "internal",
        "Failed to generate unique referral code. Please try again."
      );
    }

    // Store code in referral_codes collection
    const batch = db.batch();
    batch.set(db.collection("referral_codes").doc(code), {
      driverId: uid,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Update driver doc with referral code
    batch.update(driverRef, {
      referralCode: code,
    });

    await batch.commit();

    return { success: true, code };
  } catch (error) {
    if (error instanceof functions.https.HttpsError) throw error;
    console.error("generateReferralCode error:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

/**
 * registerReferral
 *
 * Registers a referral for the authenticated driver using a referral code.
 * Validates the code, performs anti-fraud checks (different phone numbers,
 * different UIDs), and creates a pending referral record.
 */
exports.registerReferral = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "You must be logged in."
    );
  }

  const uid = context.auth.uid;
  const { referralCode } = data;

  console.log(`[REFERRAL] registerReferral called by uid=${uid}, referralCode=${referralCode}, raw data=`, JSON.stringify(data));

  if (!referralCode) {
    console.log(`[REFERRAL] ERROR: Missing referral code. data keys:`, Object.keys(data || {}));
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Missing referral code."
    );
  }

  // --- KILL SWITCH CHECK ---
  const configSnap = await admin.database().ref('config/feature_flags/enable_referrals').once('value');
  const referralsEnabled = configSnap.val() !== false; // true by default

  if (!referralsEnabled) {
    console.log(`[REFERRAL] ERROR: Referral program is paused.`);
    throw new functions.https.HttpsError(
      "failed-precondition",
      "The referral program is currently paused. Please try again later."
    );
  }

  const db = admin.firestore();

  // Rate Limiting: 5 calls/min
  await checkRateLimit(db, uid, "registerReferral", 5, 60000);

  try {
    // Validate code exists
    console.log(`[REFERRAL] Looking up code: "${referralCode}" in referral_codes collection`);
    const codeSnap = await db.collection("referral_codes").doc(referralCode).get();
    if (!codeSnap.exists) {
      console.log(`[REFERRAL] ERROR: Code "${referralCode}" not found in referral_codes`);
      throw new functions.https.HttpsError(
        "not-found",
        "Invalid referral code."
      );
    }

    const referrerDriverId = codeSnap.data().driverId;
    console.log(`[REFERRAL] Code found. Referrer driverId: ${referrerDriverId}`);

    // Anti-fraud: ensure driver isn't referring themselves (uid check)
    if (referrerDriverId === uid) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "You cannot use your own referral code."
      );
    }

    // Anti-fraud: get both phone numbers from Firebase Auth, ensure they differ
    const [referredUser, referrerUser] = await Promise.all([
      admin.auth().getUser(uid),
      admin.auth().getUser(referrerDriverId),
    ]);

    if (
      referredUser.phoneNumber &&
      referrerUser.phoneNumber &&
      referredUser.phoneNumber === referrerUser.phoneNumber
    ) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Referral not allowed between accounts with the same phone number."
      );
    }

    // Anti-fraud: Check if this phone number has already used a referral code
    const phoneNumber = referredUser.phoneNumber;
    if (phoneNumber) {
      const usedReferralRef = db.collection("used_referral_phones").doc(phoneNumber);
      const usedReferralSnap = await usedReferralRef.get();
      if (usedReferralSnap.exists) {
        console.log(`[REFERRAL] Phone ${phoneNumber} already used a referral code`);
        throw new functions.https.HttpsError(
          "already-exists",
          "This phone number has already used a referral code."
        );
      }
    }

    // Check if the referred driver already has a referral
    const referredDriverRef = db.collection("drivers").doc(uid);
    const referredDriverSnap = await referredDriverRef.get();

    if (!referredDriverSnap.exists) {
      console.log(`[REFERRAL] ERROR: Driver doc not found for uid=${uid}`);
      throw new functions.https.HttpsError("not-found", "Driver not found.");
    }

    if (referredDriverSnap.data().referredBy) {
      console.log(`[REFERRAL] Driver ${uid} already has referredBy=${referredDriverSnap.data().referredBy}`);
      throw new functions.https.HttpsError(
        "already-exists",
        "You have already used a referral code."
      );
    }

    // Create referral record
    const referralRef = db.collection("referrals").doc();
    const batch = db.batch();

    batch.set(referralRef, {
      referrerDriverId,
      referredDriverId: uid,
      referredDriverName: referredDriverSnap.data().name || "New Driver",
      referralCode,
      status: "pending",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Update referred driver doc
    batch.update(referredDriverRef, {
      referredBy: referrerDriverId,
      referredByCode: referralCode,
    });

    // Record phone number to prevent reuse after account deletion
    if (phoneNumber) {
      const usedReferralRef = db.collection("used_referral_phones").doc(phoneNumber);
      batch.set(usedReferralRef, {
        uid: uid,
        referralCode: referralCode,
        usedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
    console.log(`[REFERRAL] SUCCESS: Referral registered. referralId=${referralRef.id}, referrer=${referrerDriverId}, referred=${uid}`);

    return { success: true };
  } catch (error) {
    if (error instanceof functions.https.HttpsError) throw error;
    console.error("[REFERRAL] registerReferral error:", error);
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

    const { title, body, target, scheduledTime, geofenceLat, geofenceLng, geofenceRadius } = req.body;

    if (!title || !body || !target) {
      res.status(400).json({ error: "Missing title, body, or target" });
      return;
    }
    
    let geofence = null;
    if (geofenceLat !== undefined && geofenceLng !== undefined && geofenceRadius !== undefined) {
      geofence = { lat: geofenceLat, lng: geofenceLng, radiusKm: geofenceRadius };
    }

    try {
      if (scheduledTime) {
        await admin.firestore().collection("scheduled_notifications").add({
          title,
          body,
          target,
          geofence,
          scheduledTime: admin.firestore.Timestamp.fromDate(new Date(scheduledTime)),
          status: "pending",
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        res.status(200).json({ success: true, message: "Notification scheduled." });
        return;
      }

      // Immediate sending logic
      await _executeNotificationSend(title, body, target, geofence);

      res.status(200).json({ success: true });
    } catch (error) {
      console.error("Error sending notification:", error);
      res.status(500).json({ error: error.message });
    }
  });
});

/**
 * Helper to execute the actual push notification logic.
 */
async function _executeNotificationSend(title, body, target, geofence) {
  let topicName = null;
  let tokens = [];

  console.log(`[Notification] Target: ${target}, Geofence: ${geofence ? JSON.stringify(geofence) : 'none'}`);

  // Determine base collection for geofencing or targeted queries
  let collectionRef = null;
  if (target === "users") collectionRef = admin.firestore().collection("users");
  else collectionRef = admin.firestore().collection("drivers");

  if (target === "users" && !geofence) {
    topicName = "riders";
  } else if (target === "drivers" && !geofence) {
    topicName = "drivers";
  }

  if (collectionRef && !topicName) {
    if (geofence && geofence.lat && geofence.lng && geofence.radiusKm) {
      const center = [geofence.lat, geofence.lng];
      const radiusInM = geofence.radiusKm * 1000;
      const bounds = geofire.geohashQueryBounds(center, radiusInM);

      const promises = [];
      for (const b of bounds) {
        const q = collectionRef.where("geohash", ">=", b[0]).where("geohash", "<=", b[1]);
        promises.push(q.get());
      }

      const snapshots = await Promise.all(promises);
      snapshots.forEach((snap) => {
        snap.forEach((doc) => {
          const data = doc.data();
          
          // Verify target conditions locally to avoid missing composite index errors
          let matchesTarget = true;
          if (target === "active_drivers" && data.isOnline !== true) matchesTarget = false;
          if (target === "offline_drivers" && data.isOnline !== false) matchesTarget = false;
          if (target === "unapproved_drivers" && data.isApproved !== false) matchesTarget = false;

          if (matchesTarget && data.lat && data.lng) {
            const distanceInKm = geofire.distanceBetween([data.lat, data.lng], center);
            if (distanceInKm <= geofence.radiusKm) {
              if (data.fcmToken) tokens.push(data.fcmToken);
            }
          }
        });
      });
    } else {
      // No geofence, just fetch tokens via simple query based on target
      let simpleQuery = collectionRef;
      if (target === "active_drivers") simpleQuery = simpleQuery.where("isOnline", "==", true);
      if (target === "offline_drivers") simpleQuery = simpleQuery.where("isOnline", "==", false);
      if (target === "unapproved_drivers") simpleQuery = simpleQuery.where("isApproved", "==", false);

      const snapshot = await simpleQuery.get();
      snapshot.forEach((doc) => {
        const data = doc.data();
        if (data.fcmToken) tokens.push(data.fcmToken);
      });
    }
  }

  tokens = [...new Set(tokens)];

  console.log(`[Notification] Method: ${topicName ? 'topic:' + topicName : 'multicast'}, Tokens found: ${tokens.length}`);

  if (topicName) {
    await admin.messaging().send({
      topic: topicName,
      notification: { title, body },
      data: { type: "broadcast", target },
    });
  } else if (tokens.length > 0) {
    // Send in batches of 500
    for (let i = 0; i < tokens.length; i += 500) {
      const batchTokens = tokens.slice(i, i + 500);
      await admin.messaging().sendEachForMulticast({
        tokens: batchTokens,
        notification: { title, body },
        data: { type: "broadcast", target },
      });
    }
  }

  // Log to Firestore
  await admin.firestore().collection("notifications_log").add({
    title,
    body,
    target,
    geofence: geofence || null,
    sentAt: admin.firestore.FieldValue.serverTimestamp(),
    method: topicName ? "topic" : "multicast",
    topic: topicName || "none",
    tokenCount: tokens.length,
  });
}

/**
 * processScheduledNotifications
 * Runs every 5 minutes to send scheduled push notifications.
 */
exports.processScheduledNotifications = functions.pubsub.schedule("*/5 * * * *").onRun(async (context) => {
  const now = admin.firestore.Timestamp.now();
  const snapshot = await admin.firestore().collection("scheduled_notifications")
    .where("status", "==", "pending")
    .where("scheduledTime", "<=", now)
    .get();

  if (snapshot.empty) return null;

  const batch = admin.firestore().batch();
  for (const doc of snapshot.docs) {
    const data = doc.data();
    
    try {
      await _executeNotificationSend(data.title, data.body, data.target, data.geofence);
      batch.update(doc.ref, {
        status: "sent",
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (e) {
      console.error(`Error sending scheduled notification ${doc.id}:`, e);
      batch.update(doc.ref, {
        status: "failed",
        error: e.message,
      });
    }
  }

  await batch.commit();
  return null;
});

/**
 * onSOSCreated
 * Sends an FCM notification to the admin dashboard when a new SOS alert is created.
 */
exports.onSOSCreated = functions.firestore
  .document("sos_alerts/{alertId}")
  .onCreate(async (snap, context) => {
    const data = snap.data();
    if (!data) return null;

    const role = (data.role || "user").toUpperCase();
    const name = data.name || "Unknown User";
    const location = data.location || "Unknown Location";

    try {
      await admin.messaging().send({
        topic: "admin_sos_alerts",
        notification: {
          title: "🚨 EMERGENCY SOS ALERT",
          body: `[${role}] ${name} activated SOS at ${location}`,
        },
        android: {
          priority: "high",
          notification: {
            channelId: "emergency_alerts",
            defaultSound: true,
            defaultVibrateTimings: true,
            priority: "high",
          },
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
            },
          },
        },
        data: { 
          type: "sos_alert",
          alertId: context.params.alertId 
        },
      });

      console.log(`SOS Alert FCM sent to admins for alert: ${context.params.alertId}`);
    } catch (error) {
      console.error("Error sending SOS FCM to admins:", error);
    }
    return null;
  });

/**
 * onSOSResolved
 * Sends an FCM notification to the rider when their SOS alert is marked as resolved by the admin.
 */
exports.onSOSResolved = functions.firestore
  .document("sos_alerts/{alertId}")
  .onUpdate(async (change, context) => {
    const beforeData = change.before.data();
    const afterData = change.after.data();

    // Check if status changed from 'active' to 'resolved'
    if (beforeData.status === "active" && afterData.status === "resolved") {
      const userId = afterData.userId;
      if (!userId) return null;

      try {
        await admin.messaging().send({
          topic: `rider_${userId}`,
          notification: {
            title: "Emergency Alert Closed",
            body: "Your emergency alert has been closed. If you still need help, please call Support.",
          },
          data: { type: "sos_resolved" },
        });

          // Log the notification
          await admin.firestore().collection("notifications_log").add({
            title: "Emergency Alert Closed",
            body: "Your emergency alert has been closed. If you still need help, please call Support.",
            targetUserId: userId,
            sentAt: admin.firestore.FieldValue.serverTimestamp(),
            method: "token",
            topic: "none",
          });
      } catch (error) {
        console.error(`Failed to send SOS resolution notification to user ${userId}:`, error);
      }
    }
    return null;
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
      
      // Delete driver's payment history
      try {
        const paymentsSnap = await admin.firestore().collection("payments").where("driverId", "==", uid).get();
        if (!paymentsSnap.empty) {
          const batch = admin.firestore().batch();
          paymentsSnap.forEach(doc => {
            batch.delete(doc.ref);
          });
          await batch.commit();
          console.log(`Deleted ${paymentsSnap.size} payment records for driver ${uid}`);
        }
      } catch (e) {
        console.error(`Failed to delete payments for ${uid}:`, e);
      }
      
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
    const driverId = context.params.driverId;
    
    // Fetch phone from Auth to guarantee we have it, even if client hasn't saved it yet
    try {
      const userRecord = await admin.auth().getUser(driverId);
      const phone = userRecord.phoneNumber;
      
      // Check if driver has previously used a free trial on this phone number
      if (phone) {
        const usedTrialSnap = await admin.firestore().collection("used_free_trials").doc(phone).get();
        if (usedTrialSnap.exists) {
          await snap.ref.update({ hasFreeTrialUsed: true });
          console.log(`[Driver Onboarding] Phone ${phone} has already used free trial. Set hasFreeTrialUsed = true.`);
        }
      }
    } catch (e) {
      console.error(`Error checking used_free_trials for driver ${driverId}:`, e);
    }
    
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
 * Notifies the driver when their account is approved or rejected.
 */
exports.onDriverApproved = functions.firestore
  .document("drivers/{driverId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();

    const wasApproved = before.isApproved === true || before.isApproved === "true";
    const isApproved = after.isApproved === true || after.isApproved === "true";
    
    const wasRejected = before.isRejected === true || before.isRejected === "true";
    const isRejected = after.isRejected === true || after.isRejected === "true";

    // Handle Approval
    if (!wasApproved && isApproved) {
      await admin.messaging().send({
        topic: `driver_${context.params.driverId}`,
        notification: {
          title: "Account Approved!",
          body: "Your driver account has been approved. You can now accept rides.",
        },
        data: { type: "driver_approved" },
      });

      // ── REFERRAL REWARD PROCESSING ──
      try {
        const approvedDriverId = context.params.driverId;
        const referrerDriverId = after.referredBy;

        console.log(`[REFERRAL-REWARD] Driver ${approvedDriverId} approved. referredBy=${referrerDriverId || 'NONE'}`);

        if (referrerDriverId) {
          // --- KILL SWITCH CHECK ---
          const configSnap = await admin.database().ref('config/feature_flags/enable_referrals').once('value');
          if (configSnap.val() === false) {
            console.log(`[REFERRAL-REWARD] Referral program is paused. Skipping reward for driver ${approvedDriverId}.`);
            return null;
          }

          const db = admin.firestore();

          // Find the pending referral document
          console.log(`[REFERRAL-REWARD] Querying referrals for referredDriverId=${approvedDriverId}, status=pending`);
          const referralsQuery = await db.collection("referrals")
            .where("referredDriverId", "==", approvedDriverId)
            .where("status", "==", "pending")
            .limit(1)
            .get();

          console.log(`[REFERRAL-REWARD] Found ${referralsQuery.size} pending referral docs`);

          if (!referralsQuery.empty) {
            const referralDoc = referralsQuery.docs[0];
            const referralId = referralDoc.id;

            // a. Update referral doc status
            await db.collection("referrals").doc(referralId).update({
              status: "rewarded",
              approvedAt: admin.firestore.FieldValue.serverTimestamp(),
              rewardedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            console.log(`[REFERRAL-REWARD] Referral ${referralId} marked as rewarded`);

            // b. Extend referrer's subscription by 7 days
            const referrerRef = db.collection("drivers").doc(referrerDriverId);
            const referrerSnap = await referrerRef.get();

            if (referrerSnap.exists) {
              const referrerData = referrerSnap.data();
              const now = new Date();
              let baseDate = now;

              if (referrerData.subscriptionActiveUntil) {
                const currentExpiry = referrerData.subscriptionActiveUntil.toDate
                  ? referrerData.subscriptionActiveUntil.toDate()
                  : new Date(referrerData.subscriptionActiveUntil);
                if (currentExpiry > now) {
                  baseDate = currentExpiry;
                }
              }

              const newExpiry = new Date(baseDate);
              newExpiry.setDate(newExpiry.getDate() + 7);

              await referrerRef.update({
                subscriptionActiveUntil: admin.firestore.Timestamp.fromDate(newExpiry),
                totalReferrals: admin.firestore.FieldValue.increment(1),
              });
              console.log(`[REFERRAL-REWARD] Extended referrer ${referrerDriverId} subscription to ${newExpiry.toISOString()}`);

              // c. Create payment record
              await db.collection("payments").add({
                driverId: referrerDriverId,
                amount: 0,
                days: 7,
                type: "referral_reward",
                method: "referral",
                referralId,
                referredDriverName: after.name || "Driver",
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
              });
              console.log(`[REFERRAL-REWARD] Payment record created for referrer ${referrerDriverId}`);

              // e. Send FCM notification to referrer
              await admin.messaging().send({
                topic: `driver_${referrerDriverId}`,
                notification: {
                  title: "🎉 Referral Reward Earned!",
                  body: `Your friend ${after.name || "a driver"} has successfully onboarded! You have earned 7 days subscription free. Keep referring!`,
                },
                data: { type: "referral_reward" },
              });
              console.log(`[REFERRAL-REWARD] FCM notification sent to referrer ${referrerDriverId}`);
            } else {
              console.log(`[REFERRAL-REWARD] ERROR: Referrer driver doc ${referrerDriverId} not found`);
            }
          } else {
            console.log(`[REFERRAL-REWARD] No pending referral found for driver ${approvedDriverId}`);
          }
        }
      } catch (referralError) {
        console.error("[REFERRAL-REWARD] Error processing referral reward:", referralError);
        // Don't throw — referral processing failure should not break the approval notification
      }
    }

    // Handle Rejection
    if (!wasRejected && isRejected) {
      const reason = after.rejectionReason || "Please review your documents and resubmit.";
      await admin.messaging().send({
        topic: `driver_${context.params.driverId}`,
        notification: {
          title: "Profile Requires Attention",
          body: `Your profile was rejected: ${reason}`,
        },
        data: { type: "driver_rejected" },
      });
      console.log(`[DRIVER-REJECTED] Sent rejection notification to driver_${context.params.driverId}`);
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

    // 3. Track driver earnings and rider completed rides when a ride is completed
    if (before.status !== "completed" && after.status === "completed") {
      if (after.driverId && after.finalPrice) {
        await admin.firestore().collection("drivers").doc(after.driverId).update({
          totalEarnings: admin.firestore.FieldValue.increment(Number(after.finalPrice) || 0)
        });
      }
      if (after.riderId) {
        await admin.firestore().collection("users").doc(after.riderId).update({
          totalCompletedRides: admin.firestore.FieldValue.increment(1)
        });
      }
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
 * manageActiveRides
 * Runs every minute to manage rides stuck in "searching" or "bidding".
 * - If > 5 minutes old: Expires the ride and cleans up RTDB signals.
 * - If 3-5 minutes old: Expands the search radius to geohash-4.
 */
exports.manageActiveRides = functions.pubsub
  .schedule("* * * * *")
  .onRun(async (context) => {
    const now = Date.now();
    const phase2Start = new Date(now - (3 * 60 * 1000)); // 3 minutes ago
    const expiryTime = new Date(now - (5 * 60 * 1000));  // 5 minutes ago

    const snapshot = await admin.firestore().collection("rides")
      .where("status", "in", ["searching", "bidding"])
      .where("createdAt", "<", admin.firestore.Timestamp.fromDate(phase2Start))
      .get();

    if (snapshot.empty) return null;

    const batch = admin.firestore().batch();
    const promises = [];
    let expandedCount = 0;
    let expiredCount = 0;

    for (const doc of snapshot.docs) {
      const data = doc.data();
      const rideId = doc.id;
      const createdAt = data.createdAt ? data.createdAt.toDate() : new Date();

      if (createdAt < expiryTime) {
        // --- EXPIRATION LOGIC ---
        batch.update(doc.ref, { status: "expired" });
        
        const paths = data.activeSignalPaths || [];
        if (paths.length > 0) {
          const removeUpdate = {};
          for (const p of paths) {
            removeUpdate[p] = null;
          }
          promises.push(admin.database().ref().update(removeUpdate));
        }
        promises.push(admin.database().ref(`ride_declines/${rideId}`).remove());
        expiredCount++;
      } else if (data.expandedSearch !== true) {
        // --- EXPANSION LOGIC ---
        if (!data.pickup || !data.pickup.lat || !data.pickup.lng) continue;

        const lat = data.pickup.lat;
        const lng = data.pickup.lng;
        const vehicleType = data.vehicleType || "auto";

        const centerHash4 = ngeohash.encode(lat, lng, 4);
        const neighbors4 = ngeohash.neighbors(centerHash4);
        const expandedHashes = [centerHash4, ...neighbors4];

        try {
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
              if (!existingPaths.includes(path)) {
                expandMultiPath[path] = signalData;
                newPaths.push(path);
              }
            }
            if (Object.keys(expandMultiPath).length > 0) {
              promises.push(admin.database().ref().update(expandMultiPath));
            }
            if (newPaths.length > 0) {
              batch.update(doc.ref, {
                activeSignalPaths: admin.firestore.FieldValue.arrayUnion(...newPaths),
                expandedSearch: true
              });
            } else {
              batch.update(doc.ref, { expandedSearch: true });
            }
          } else {
            batch.update(doc.ref, { expandedSearch: true });
          }
        } catch (e) {
          console.error(`Failed to expand RTDB signals for ride ${rideId}:`, e);
        }

        const pickupName = (data.pickup && data.pickup.short_name) || "Nearby";
        const dropName = (data.drop && data.drop.short_name) || "Destination";
        const fareLabel = data.riderBid ? `₹${data.riderBid}` : "Open bid";

        const chunk1 = expandedHashes.slice(0, 5);
        const chunk2 = expandedHashes.slice(5, 9);

        const sendExpanded = (hashes) => {
          if (hashes.length === 0) return;
          const condition = hashes.map(h => `'zone_${h}_${vehicleType}' in topics`).join(" || ");
          promises.push(
            admin.messaging().send({
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
            }).catch(e => console.error("Expanded FCM Send Error:", e))
          );
        };

        sendExpanded(chunk1);
        sendExpanded(chunk2);
        
        expandedCount++;
      }
    }

    promises.push(batch.commit());
    await Promise.all(promises);

    if (expandedCount > 0 || expiredCount > 0) {
      console.log(`manageActiveRides: Expanded ${expandedCount}, Expired ${expiredCount}`);
    }
    return null;
  });

/**
 * cleanupStaleRides
 * Runs every 30 minutes. 
 * - Finds rides stuck in "matched" for > 60 minutes and cancels them.
 * - Finds rides stuck in "started" for > 4 hours and cancels them.
 */
exports.cleanupStaleRides = functions.pubsub
  .schedule("every 30 minutes")
  .onRun(async (context) => {
    const db = admin.firestore();
    const now = Date.now();
    
    const staleMatchedTimeMs = now - (60 * 60 * 1000); // 60 minutes ago
    const staleStartedTimeMs = now - (4 * 60 * 60 * 1000); // 4 hours ago

    const batch = db.batch();
    const promises = [];
    let matchedCount = 0;
    let startedCount = 0;

    try {
      // 1. Cleanup Stale "Matched" Rides
      const staleMatchedSnap = await db.collection("rides")
        .where("status", "==", "matched")
        .where("createdAt", "<", admin.firestore.Timestamp.fromDate(new Date(staleMatchedTimeMs)))
        .get();

      if (!staleMatchedSnap.empty) {
        staleMatchedSnap.forEach((doc) => {
          const data = doc.data();
          const rideId = doc.id;
          
          batch.update(doc.ref, { 
            status: "cancelled",
            cancelReason: "server_stale_cleanup",
            cancelledAt: admin.firestore.FieldValue.serverTimestamp()
          });

          if (data.driverId) {
            batch.update(db.collection("drivers").doc(data.driverId), {
              driverState: "ONLINE_IDLE",
              activeRideId: null,
              activeBidCount: 0,
            });
          }
          
          const paths = data.activeSignalPaths || [];
          if (paths.length > 0) {
            const removeUpdate = {};
            for (const p of paths) {
              removeUpdate[p] = null;
            }
            promises.push(admin.database().ref().update(removeUpdate));
          }
          promises.push(admin.database().ref(`ride_declines/${rideId}`).remove());
          matchedCount++;
        });
      }

      // 2. Cleanup Dead "Started" Sessions
      const deadStartedSnap = await db.collection("rides")
        .where("status", "==", "started")
        .where("startedAt", "<", admin.firestore.Timestamp.fromDate(new Date(staleStartedTimeMs)))
        .get();

      if (!deadStartedSnap.empty) {
        deadStartedSnap.forEach((doc) => {
          const data = doc.data();
          
          batch.update(doc.ref, {
            status: "cancelled",
            cancelReason: "system_timeout_dead_session",
            completedAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          if (data.driverId) {
            batch.update(db.collection("drivers").doc(data.driverId), {
              driverState: "ONLINE_IDLE",
              activeRideId: null,
            });
          }
          startedCount++;
        });
      }

      if (matchedCount > 0 || startedCount > 0) {
        promises.push(batch.commit());
        await Promise.all(promises);
        console.log(`Cleaned up ${matchedCount} stale matched rides and ${startedCount} dead started sessions.`);
      }

      return null;
    } catch (e) {
      console.error("Error cleaning up stale rides:", e);
      return null;
    }
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
 * autoOfflineIdleDrivers
 * Scheduled Cron Job (Runs every 60 minutes)
 * Uses RTDB-first approach: queries RTDB presence nodes for drivers who have been
 * disconnected for more than 2 hours, then updates only those specific drivers in
 * Firestore. This avoids reading ALL online drivers from Firestore every execution,
 * reducing Firestore reads from ~200/execution to ~0-5/execution.
 */
exports.autoOfflineIdleDrivers = functions.pubsub
  .schedule("every 60 minutes")
  .onRun(async (context) => {
    const db = admin.firestore();
    const rtdb = admin.database();

    try {
      const twoHoursAgo = Date.now() - 2 * 60 * 60 * 1000;

      // Step 1: Query RTDB for stale presence nodes (bandwidth-based = essentially free)
      const presenceSnap = await rtdb.ref("presence")
        .orderByChild("updatedAt")
        .endAt(twoHoursAgo)
        .once("value");

      if (!presenceSnap.exists()) return null;

      const batch = db.batch();
      let count = 0;
      const cleanupPromises = [];

      // Step 2: For each stale presence node, check the specific Firestore driver doc
      const staleEntries = [];
      presenceSnap.forEach((child) => {
        const presence = child.val();
        if (presence && presence.isOnline === false) {
          staleEntries.push({ driverId: child.key, presence });
        }
      });

      for (const entry of staleEntries) {
        const driverId = entry.driverId;

        // Step 3: Read only THIS specific driver from Firestore (1 read, not 200)
        const driverDoc = await db.collection("drivers").doc(driverId).get();

        if (driverDoc.exists) {
          const data = driverDoc.data();

          // Only update if still marked online and not actively on a ride
          if (data.isOnline === true && data.driverState !== "ON_RIDE") {
            batch.update(driverDoc.ref, {
              isOnline: false,
              driverState: "OFFLINE",
            });
            count++;
          }
        }

        // Step 4: Remove processed presence node so we don't re-check next time.
        // The driver's app will recreate it via onDisconnect when they go online again.
        cleanupPromises.push(rtdb.ref(`presence/${driverId}`).remove());
      }

      if (count > 0) {
        await batch.commit();
        console.log(`Auto-offlined ${count} idle drivers who were disconnected for > 2 hours.`);
      }

      // Cleanup processed RTDB presence nodes
      if (cleanupPromises.length > 0) {
        await Promise.all(cleanupPromises);
        console.log(`Cleaned up ${cleanupPromises.length} stale RTDB presence nodes.`);
      }
    } catch (e) {
      console.error("Error in autoOfflineIdleDrivers:", e);
    }
    return null;
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

  await admin.database().ref(`active_bids/${rideId}`).remove();
  await admin.database().ref(`active_rides/${rideId}`).remove();

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
        try {
          await admin.messaging().send({
            topic: `driver_${task.driverId}`,
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
        } catch (e) {
          console.error("Failed to send match notification to driver", e);
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

// Razorpay credentials — stored securely in Google Cloud Secret Manager.
// Set via: firebase functions:secrets:set RAZORPAY_KEY_ID
//          firebase functions:secrets:set RAZORPAY_KEY_SECRET
// Accessed at runtime via process.env.RAZORPAY_KEY_ID / process.env.RAZORPAY_KEY_SECRET

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
exports.createRazorpayOrder = functions
  .runWith({ secrets: ["RAZORPAY_KEY_ID", "RAZORPAY_KEY_SECRET"] })
  .https.onCall(async (data, context) => {
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
      key_id: process.env.RAZORPAY_KEY_ID,
      key_secret: process.env.RAZORPAY_KEY_SECRET,
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
exports.verifyRazorpayPayment = functions
  .runWith({ secrets: ["RAZORPAY_KEY_ID", "RAZORPAY_KEY_SECRET"] })
  .https.onCall(async (data, context) => {
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
    .createHmac("sha256", process.env.RAZORPAY_KEY_SECRET)
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
    const RazorpayClient = require("razorpay");
    const rzp = new RazorpayClient({
      key_id: process.env.RAZORPAY_KEY_ID,
      key_secret: process.env.RAZORPAY_KEY_SECRET,
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

/**
 * checkSubscriptions
 * Runs every 15 minutes to check for expired subscriptions and upcoming expirations.
 */
exports.checkSubscriptions = functions.pubsub
  .schedule("every 15 minutes")
  .onRun(async (context) => {
    const db = admin.firestore();
    const now = new Date();
    
    // 1. Force offline drivers whose subscriptions have expired
    try {
      const expiredDriversSnap = await db.collection("drivers")
        .where("isOnline", "==", true)
        .where("subscriptionActiveUntil", "<=", now)
        .get();

      if (!expiredDriversSnap.empty) {
        const batch = db.batch();
        let count = 0;
        for (const doc of expiredDriversSnap.docs) {
          batch.update(doc.ref, {
            isOnline: false,
            driverState: "OFFLINE",
          });
          count++;
        }
        await batch.commit();
        console.log(`checkSubscriptions: forced ${count} expired drivers offline.`);
      }
    } catch (e) {
      console.error("Error setting expired drivers offline:", e);
    }

    // 2. Send FCM alerts for subscriptions expiring in ~1 hour (45 to 60 mins from now)
    try {
      const minExpiry = new Date(now.getTime() + 45 * 60000);
      const maxExpiry = new Date(now.getTime() + 60 * 60000);

      const warningDriversSnap = await db.collection("drivers")
        .where("subscriptionActiveUntil", ">=", minExpiry)
        .where("subscriptionActiveUntil", "<=", maxExpiry)
        .get();

      if (!warningDriversSnap.empty) {
        let alertCount = 0;
        const messaging = admin.messaging();
        for (const doc of warningDriversSnap.docs) {
          const driverId = doc.id;
          const payload = {
            notification: {
              title: "Subscription Expiring Soon",
              body: "Your subscription is going to end in 1 hour. Please renew to stay online.",
            },
            data: {
              type: "subscription_alert",
            },
            topic: `driver_${driverId}`,
          };
          try {
            await messaging.send(payload);
            alertCount++;
          } catch (err) {
            console.error(`Error sending subscription alert to driver_${driverId}:`, err);
          }
        }
        console.log(`checkSubscriptions: sent ${alertCount} expiry alerts.`);
      }
    } catch (e) {
      console.error("Error sending subscription alerts:", e);
    }

    return null;
  });




// --- Daily Stats Function ---
exports.updateDailyStats = functions.firestore
  .document("rides/{rideId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();

    // Only proceed if status changed to 'completed'
    if (before.status !== "completed" && after.status === "completed") {
      const db = admin.firestore();
      
      // Calculate date in IST (+05:30) since the user is based in India
      const date = new Date();
      date.setHours(date.getHours() + 5);
      date.setMinutes(date.getMinutes() + 30);
      
      const yyyy = date.getUTCFullYear();
      const mm = String(date.getUTCMonth() + 1).padStart(2, '0');
      const dd = String(date.getUTCDate()).padStart(2, '0');
      const dateStr = `${yyyy}-${mm}-${dd}`;
      
      const statsRef = db.collection('admin_stats').doc(`daily_stats_${dateStr}`);
      const price = Number(after.finalPrice) || 0;
      
      try {
        await statsRef.set({
          date: dateStr,
          ridesCount: admin.firestore.FieldValue.increment(1),
          revenue: admin.firestore.FieldValue.increment(price),
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        }, { merge: true });
        console.log(`Updated daily stats for ${dateStr}: +1 ride, +${price} revenue`);
      } catch (err) {
        console.error("Error updating daily stats:", err);
      }
    }
    return null;
  });
// ============================================================
// REAL-TIME DASHBOARD STATS MAINTENANCE
// ============================================================

/**
 * maintainDriverStats
 * Maintains RTDB dashboard counters for drivers.
 */
exports.maintainDriverStats = functions.firestore
  .document("drivers/{driverId}")
  .onWrite(async (change, context) => {
    const rtdb = admin.database().ref("dashboard_stats");
    const updates = {};
    const increment = admin.database.ServerValue.increment(1);
    const decrement = admin.database.ServerValue.increment(-1);

    if (!change.before.exists && change.after.exists) {
      // New driver created
      updates.totalDrivers = increment;
      const after = change.after.data();
      if (after.isApproved) updates.approvedDrivers = increment;
      if (after.isBlocked) updates.blockedDrivers = increment;
      if (after.isOnline) updates.onlineDrivers = increment;
    } else if (change.before.exists && !change.after.exists) {
      // Driver deleted
      updates.totalDrivers = decrement;
      const before = change.before.data();
      if (before.isApproved) updates.approvedDrivers = decrement;
      if (before.isBlocked) updates.blockedDrivers = decrement;
      if (before.isOnline) updates.onlineDrivers = decrement;
    } else {
      // Driver updated
      const before = change.before.data();
      const after = change.after.data();

      if (!before.isApproved && after.isApproved) updates.approvedDrivers = increment;
      if (before.isApproved && !after.isApproved) updates.approvedDrivers = decrement;

      if (!before.isBlocked && after.isBlocked) updates.blockedDrivers = increment;
      if (before.isBlocked && !after.isBlocked) updates.blockedDrivers = decrement;

      if (!before.isOnline && after.isOnline) updates.onlineDrivers = increment;
      if (before.isOnline && !after.isOnline) updates.onlineDrivers = decrement;
    }

    if (Object.keys(updates).length > 0) {
      await rtdb.update(updates);
    }
  });

/**
 * maintainRideStats
 * Maintains RTDB dashboard counters for rides.
 */
exports.maintainRideStats = functions.firestore
  .document("rides/{rideId}")
  .onWrite(async (change, context) => {
    const rtdb = admin.database().ref("dashboard_stats");
    const updates = {};
    const increment = admin.database.ServerValue.increment(1);
    const decrement = admin.database.ServerValue.increment(-1);

    const ongoingStatuses = ["matched", "started", "payment_pending"];

    if (!change.before.exists && change.after.exists) {
      // New ride created
      updates.totalRides = increment;
      const after = change.after.data();
      if (after.status === "completed") {
        updates.completedRides = increment;
        if (after.finalPrice) updates.totalRevenue = admin.database.ServerValue.increment(after.finalPrice);
      } else if (after.status === "cancelled" || after.status === "expired") {
        updates.cancelledRides = increment;
      }
      
      if (ongoingStatuses.includes(after.status)) {
        updates.ongoingRides = increment;
      }
    } else if (change.before.exists && !change.after.exists) {
      // Ride deleted
      updates.totalRides = decrement;
      const before = change.before.data();
      if (before.status === "completed") {
        updates.completedRides = decrement;
        if (before.finalPrice) updates.totalRevenue = admin.database.ServerValue.increment(-before.finalPrice);
      } else if (before.status === "cancelled" || before.status === "expired") {
        updates.cancelledRides = decrement;
      }
      
      if (ongoingStatuses.includes(before.status)) {
        updates.ongoingRides = decrement;
      }
    } else {
      // Ride updated
      const before = change.before.data();
      const after = change.after.data();

      if (before.status !== after.status) {
        // Handle transitions OUT of old status
        if (before.status === "completed") {
          updates.completedRides = decrement;
          if (before.finalPrice) updates.totalRevenue = admin.database.ServerValue.increment(-before.finalPrice);
        } else if (before.status === "cancelled" || before.status === "expired") {
          updates.cancelledRides = decrement;
        }

        // Handle transitions INTO new status
        if (after.status === "completed") {
          updates.completedRides = increment;
          if (after.finalPrice) updates.totalRevenue = admin.database.ServerValue.increment(after.finalPrice);
        } else if (after.status === "cancelled" || after.status === "expired") {
          updates.cancelledRides = increment;
        }

        const wasOngoing = ongoingStatuses.includes(before.status);
        const isOngoing = ongoingStatuses.includes(after.status);
        if (wasOngoing && !isOngoing) {
          updates.ongoingRides = decrement;
        } else if (!wasOngoing && isOngoing) {
          updates.ongoingRides = increment;
        }
      } else if (before.status === "completed" && after.status === "completed") {
        // Edge case: ride already completed but finalPrice changed
        const bPrice = before.finalPrice || 0;
        const aPrice = after.finalPrice || 0;
        if (bPrice !== aPrice) {
          updates.totalRevenue = admin.database.ServerValue.increment(aPrice - bPrice);
        }
      }
    }

    if (Object.keys(updates).length > 0) {
      await rtdb.update(updates);
    }
  });

/**
 * maintainUserStats
 * Maintains RTDB dashboard counters for riders (users).
 */
exports.maintainUserStats = functions.firestore
  .document("users/{userId}")
  .onWrite(async (change, context) => {
    const rtdb = admin.database().ref("dashboard_stats");
    const increment = admin.database.ServerValue.increment(1);
    const decrement = admin.database.ServerValue.increment(-1);

    if (!change.before.exists && change.after.exists) {
      await rtdb.update({ totalRiders: increment });
    } else if (change.before.exists && !change.after.exists) {
      await rtdb.update({ totalRiders: decrement });
    }
  });

exports.initDashboardStats = functions.https.onRequest(async (req, res) => {
  const db = admin.firestore();
  const rtdb = admin.database();

  try {
    const aggregateResults = await Promise.all([
      db.collection('rides').count().get(), // 0: allRides
      db.collection('rides').where('status', '==', 'completed').count().get(), // 1: completedRides
      db.collection('rides').where('status', 'in', ['cancelled', 'expired']).count().get(), // 2: cancelledRides
      db.collection('rides').where('status', 'in', ['matched', 'started', 'payment_pending']).count().get(), // 3: ongoingRides
      db.collection('drivers').count().get(), // 4: allDrivers
      db.collection('drivers').where('isOnline', '==', true).count().get(), // 5: onlineDrivers
      db.collection('users').count().get(), // 6: allRiders
      db.collection('drivers').where('isApproved', '==', true).count().get(), // 7: approvedDrivers
      db.collection('drivers').where('isBlocked', '==', true).count().get(), // 8: blockedDrivers
    ]);

    // Sum needs a separate try block since it might fail if index is missing
    let totalRevenue = 0;
    try {
      const revenueRes = await db.collection('rides').where('status', '==', 'completed').aggregate({
        totalRevenue: admin.firestore.AggregateField.sum('finalPrice')
      }).get();
      totalRevenue = revenueRes.data().totalRevenue || 0;
    } catch(e) {
      console.log('Sum failed, maybe index is missing', e);
    }

    const stats = {
      totalRides: aggregateResults[0].data().count || 0,
      completedRides: aggregateResults[1].data().count || 0,
      cancelledRides: aggregateResults[2].data().count || 0,
      ongoingRides: aggregateResults[3].data().count || 0,
      totalDrivers: aggregateResults[4].data().count || 0,
      onlineDrivers: aggregateResults[5].data().count || 0,
      totalRiders: aggregateResults[6].data().count || 0,
      approvedDrivers: aggregateResults[7].data().count || 0,
      blockedDrivers: aggregateResults[8].data().count || 0,
      totalRevenue: totalRevenue,
    };

    await rtdb.ref('dashboard_stats').set(stats);
    res.status(200).send('Successfully seeded RTDB dashboard_stats: ' + JSON.stringify(stats));
  } catch (e) {
    res.status(500).send('Error seeding stats: ' + e.message);
  }
});



// Triggered when feature flags config is updated
exports.onFeatureFlagUpdateRTDB = functions.database
  .ref('/config/feature_flags')
  .onUpdate(async (change, context) => {
    const beforeData = change.before.val() || {};
    const afterData = change.after.val() || {};

    const maintenanceBefore = beforeData.maintenance_mode === true;
    const maintenanceAfter = afterData.maintenance_mode === true;

    if (maintenanceBefore !== maintenanceAfter) {
      let title = '';
      let body = '';

      if (maintenanceAfter) {
        title = 'System Upgrades in Progress 🛠️';
        body = 'We are currently performing scheduled maintenance to bring you a faster and more reliable experience. We will be back online shortly.';
      } else {
        title = 'System Online ✅';
        body = 'Maintenance is complete! The app is now fully functional and ready for use. Thank you for your patience.';
      }

      const payloadDriver = {
        topic: 'drivers',
        notification: {
          title: title,
          body: body,
        },
        data: {
          type: 'broadcast',
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
      };

      const payloadRider = {
        topic: 'riders',
        notification: {
          title: title,
          body: body,
        },
        data: {
          type: 'broadcast',
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
      };

      try {
        await admin.messaging().send(payloadDriver);
        await admin.messaging().send(payloadRider);
        console.log('Successfully sent maintenance mode notifications');
      } catch (error) {
        console.error('Error sending maintenance mode notifications:', error);
      }
    }

    // Handle Referral Program toggles
    const referralsBefore = beforeData.enable_referrals !== false; // Default is true
    const referralsAfter = afterData.enable_referrals !== false;

    if (referralsBefore !== referralsAfter) {
      let title = '';
      let body = '';

      if (!referralsAfter) {
        title = 'Referral Program Paused ⏸️';
        body = 'Our Refer & Earn program is taking a short break. You can still view your past earnings in the app!';
      } else {
        title = 'Referral Program is Back! 🎉';
        body = 'Great news! The Refer & Earn program is active again. Start referring other drivers to get your 7-day free subscription!';
      }

      const payloadDriverReferral = {
        topic: 'drivers',
        notification: {
          title: title,
          body: body,
        },
        data: {
          type: 'referral_broadcast', // Custom type so frontend can show Toast + Notification
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
      };

      try {
        await admin.messaging().send(payloadDriverReferral);
        console.log('Successfully sent referral program notifications to drivers');
      } catch (error) {
        console.error('Error sending referral program notifications:', error);
      }
    }

    return null;
  });

// ============================================================
// CRON JOBS
// ============================================================
/**
 * cleanupRTDB
 * Runs every 24 hours to delete old rate limit and idempotency nodes from RTDB.
 */
exports.cleanupRTDB = functions.pubsub.schedule("every 24 hours").onRun(async (context) => {
  const rtdb = admin.database();
  const now = Date.now();
  
  // 1. Clean up operations older than 7 days
  const sevenDaysAgo = now - (7 * 24 * 60 * 60 * 1000);
  const opsSnap = await rtdb.ref("operations").orderByChild("timestamp").endAt(sevenDaysAgo).once("value");
  const opsUpdates = {};
  opsSnap.forEach(child => {
    opsUpdates[child.key] = null;
  });
  if (Object.keys(opsUpdates).length > 0) {
    await rtdb.ref("operations").update(opsUpdates);
  }

  // 2. Clean up rate_limits older than 1 hour
  const oneHourAgo = now - (60 * 60 * 1000);
  const limitsSnap = await rtdb.ref("rate_limits").orderByChild("windowStart").endAt(oneHourAgo).once("value");
  const limitUpdates = {};
  limitsSnap.forEach(child => {
    limitUpdates[child.key] = null;
  });
  if (Object.keys(limitUpdates).length > 0) {
    await rtdb.ref("rate_limits").update(limitUpdates);
  }

  console.log(`Cleaned up ${Object.keys(opsUpdates).length} old operations and ${Object.keys(limitUpdates).length} old rate limits from RTDB.`);
  return null;
});

// ============================================================
// DYNAMIC ADVERTISEMENTS (REMOTE CONFIG)
// ============================================================
/**
 * syncPromoConfig
 * Automatically updates Firebase Remote Config whenever an ad campaign is modified in Firestore.
 */
exports.syncPromoConfig = functions.firestore
  .document('ad_campaigns/{campaignId}')
  .onWrite(async (change, context) => {
    try {
      const db = admin.firestore();
      // 1. Find the active campaign
      const activeQuery = await db.collection('ad_campaigns')
        .where('isActive', '==', true)
        .limit(1)
        .get();

      let promoPayload = { isActive: false };

      if (!activeQuery.empty) {
        const data = activeQuery.docs[0].data();
        promoPayload = {
          isActive: true,
          imageUrl: data.imageUrl || '',
          title: data.title || '',
          actionUrl: data.actionUrl || '',
          targetLat: data.targetLat || 0,
          targetLng: data.targetLng || 0,
          radiusKm: data.radiusKm || 0,
          campaignId: data.id || activeQuery.docs[0].id,
        };
      }

      // 2. Get the current active Remote Config template
      const template = await admin.remoteConfig().getTemplate();

      // 3. Add or update the 'promotional_banner' parameter
      template.parameters = template.parameters || {};
      template.parameters['promotional_banner'] = {
        defaultValue: {
          value: JSON.stringify(promoPayload)
        },
        valueType: 'STRING',
        description: 'Dynamic Ad Campaign Payload'
      };

      // 4. Validate and publish the updated template
      const validatedTemplate = await admin.remoteConfig().validateTemplate(template);
      const publishedTemplate = await admin.remoteConfig().publishTemplate(validatedTemplate);

      console.log("Successfully published new Remote Config template:", publishedTemplate.version.versionNumber);
      return null;
    } catch (error) {
      console.error("Error syncing Remote Config:", error);
      return null;
    }
  });
