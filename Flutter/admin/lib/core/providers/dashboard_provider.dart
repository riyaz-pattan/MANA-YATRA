// lib/core/providers/dashboard_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Real-time dashboard statistics.
class DashboardStats {
  final int totalRides;
  final int completedRides;
  final int cancelledRides;
  final int ongoingRides;
  final int totalDrivers;
  final int approvedDrivers;
  final int onlineDrivers;
  final int pendingDrivers;
  final int totalRiders;
  final double totalRevenue;
  final double todayRevenue;
  final double completionRate;
  final double cancellationRate;

  const DashboardStats({
    this.totalRides = 0,
    this.completedRides = 0,
    this.cancelledRides = 0,
    this.ongoingRides = 0,
    this.totalDrivers = 0,
    this.approvedDrivers = 0,
    this.onlineDrivers = 0,
    this.pendingDrivers = 0,
    this.totalRiders = 0,
    this.totalRevenue = 0,
    this.todayRevenue = 0,
    this.completionRate = 0,
    this.cancellationRate = 0,
  });
}

/// Provider that loads dashboard statistics from Firestore.
final dashboardStatsProvider = FutureProvider<DashboardStats>((ref) async {
  final firestore = FirebaseFirestore.instance;

  // Fetch all data in parallel
  final results = await Future.wait([
    firestore.collection('rides').get(),
    firestore.collection('rides').where('status', isEqualTo: 'completed').get(),
    firestore.collection('rides').where('status', isEqualTo: 'cancelled').get(),
    firestore
        .collection('rides')
        .where('status', whereIn: ['searching', 'bidding', 'matched', 'started'])
        .get(),
    firestore.collection('drivers').get(),
    firestore.collection('drivers').where('isOnline', isEqualTo: true).get(),
    firestore.collection('users').get(),
  ]);

  final allRides = results[0];
  final completed = results[1];
  final cancelled = results[2];
  final ongoing = results[3];
  final allDrivers = results[4];
  final onlineDrivers = results[5];
  final allRiders = results[6];

  double totalRevenue = 0;
  double todayRevenue = 0;
  final todayStart = DateTime.now().copyWith(hour: 0, minute: 0, second: 0);

  for (final doc in completed.docs) {
    final price = ((doc.data()['finalPrice'] ?? 0) as num).toDouble();
    totalRevenue += price;

    final createdAt = (doc.data()['createdAt'] as Timestamp?)?.toDate();
    if (createdAt != null && createdAt.isAfter(todayStart)) {
      todayRevenue += price;
    }
  }

  final approvedCount = allDrivers.docs
      .where((d) => d.data()['isApproved'] == true)
      .length;
  final pendingCount = allDrivers.docs
      .where((d) => d.data()['isApproved'] != true && d.data()['isBlocked'] != true)
      .length;

  final completionRate = allRides.size > 0
      ? (completed.size / allRides.size) * 100
      : 0.0;
  final cancellationRate = allRides.size > 0
      ? (cancelled.size / allRides.size) * 100
      : 0.0;

  return DashboardStats(
    totalRides: allRides.size,
    completedRides: completed.size,
    cancelledRides: cancelled.size,
    ongoingRides: ongoing.size,
    totalDrivers: allDrivers.size,
    approvedDrivers: approvedCount,
    onlineDrivers: onlineDrivers.size,
    pendingDrivers: pendingCount,
    totalRiders: allRiders.size,
    totalRevenue: totalRevenue,
    todayRevenue: todayRevenue,
    completionRate: completionRate,
    cancellationRate: cancellationRate,
  );
});
