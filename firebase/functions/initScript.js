exports.initDashboardStats = functions.https.onRequest(async (req, res) => {
  const db = admin.firestore();
  const rtdb = admin.database();

  try {
    const aggregateResults = await Promise.all([
      db.collection('rides').count().get(), // 0: allRides
      db.collection('rides').where('status', '==', 'completed').count().get(), // 1: completedRides
      db.collection('rides').where('status', 'in', ['cancelled', 'expired']).count().get(), // 2: cancelledRides
      db.collection('rides').where('status', 'in', ['searching', 'bidding', 'matched', 'started']).count().get(), // 3: ongoingRides
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
