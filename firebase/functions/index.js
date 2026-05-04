const functions = require("firebase-functions"); // Trigger redeployment
const admin = require("firebase-admin");
const cors = require("cors")({ origin: true });

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
 */
exports.onRideStatusChanged = functions.firestore
  .document("rides/{rideId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();

    // Cancellation tracking
    if (before.status !== "cancelled" && after.status === "cancelled") {
      if (after.driverId) {
        // Increment total cancelled rides for driver
        await admin.firestore().collection("drivers").doc(after.driverId).update({
          totalCancelledRides: admin.firestore.FieldValue.increment(1)
        });
      }
    }
    
    // Total assigned tracking
    if (before.status === "pending" && after.status === "accepted") {
      if (after.driverId) {
        await admin.firestore().collection("drivers").doc(after.driverId).update({
          totalAssignedRides: admin.firestore.FieldValue.increment(1)
        });
      }
    }

    // Status change notifications
    if (before.status !== after.status) {
      if (after.riderId) {
        await admin.messaging().send({
          topic: `rider_${after.riderId}`,
          notification: {
            title: "Ride Update",
            body: `Your ride status is now: ${after.status}`,
          },
          data: { type: "ride_status", rideId: context.params.rideId, status: after.status },
        });
      }
      if (after.driverId) {
        await admin.messaging().send({
          topic: `driver_${after.driverId}`,
          notification: {
            title: "Ride Update",
            body: `Ride status updated to: ${after.status}`,
          },
          data: { type: "ride_status", rideId: context.params.rideId, status: after.status },
        });
      }
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
