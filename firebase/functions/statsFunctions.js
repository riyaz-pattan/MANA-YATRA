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

    const ongoingStatuses = ["searching", "bidding", "matched", "started"];

    if (!change.before.exists && change.after.exists) {
      // New ride created
      updates.totalRides = increment;
      const after = change.after.data();
      if (after.status === "completed") {
        updates.completedRides = increment;
        if (after.finalPrice) updates.totalRevenue = admin.database.ServerValue.increment(after.finalPrice);
      } else if (after.status === "cancelled" || after.status === "expired") {
        updates.cancelledRides = increment;
      } else if (ongoingStatuses.includes(after.status)) {
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
      } else if (ongoingStatuses.includes(before.status)) {
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
        } else if (ongoingStatuses.includes(before.status)) {
          updates.ongoingRides = decrement;
        }

        // Handle transitions INTO new status
        if (after.status === "completed") {
          updates.completedRides = increment;
          if (after.finalPrice) updates.totalRevenue = admin.database.ServerValue.increment(after.finalPrice);
        } else if (after.status === "cancelled" || after.status === "expired") {
          updates.cancelledRides = increment;
        } else if (ongoingStatuses.includes(after.status)) {
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
