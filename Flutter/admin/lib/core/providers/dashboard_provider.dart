// lib/core/providers/dashboard_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';

class DailyStat {
  final String date;
  final int ridesCount;
  final double revenue;

  DailyStat({required this.date, required this.ridesCount, required this.revenue});
}

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
  final List<DailyStat> dailyStats;

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
    this.dailyStats = const [],
  });
}

/// Provider that streams dashboard statistics from RTDB and Firestore.
final dashboardStatsProvider = StreamProvider<DashboardStats>((ref) async* {
  final firestore = FirebaseFirestore.instance;
  final rtdb = FirebaseDatabase.instance;
  final todayStart = DateTime.now().copyWith(hour: 0, minute: 0, second: 0, millisecond: 0, microsecond: 0);

  double todayRevenue = 0;
  try {
    final todayRidesSnapshot = await firestore
        .collection('rides')
        .where('createdAt', isGreaterThanOrEqualTo: todayStart)
        .get();

    for (final doc in todayRidesSnapshot.docs) {
      if (doc.data()['status'] == 'completed') {
        todayRevenue += ((doc.data()['finalPrice'] ?? 0) as num).toDouble();
      }
    }
  } catch (e) {
    print('Error fetching today rides: $e');
  }

  final List<DailyStat> fetchedDailyStats = [];
  try {
    final dailyStatsSnapshot = await firestore
        .collection('admin_stats')
        .orderBy('date', descending: true)
        .limit(7)
        .get();

    for (final doc in dailyStatsSnapshot.docs) {
      fetchedDailyStats.add(DailyStat(
        date: doc.data()['date'] ?? '',
        ridesCount: doc.data()['ridesCount'] ?? 0,
        revenue: ((doc.data()['revenue'] ?? 0) as num).toDouble(),
      ));
    }
    
    fetchedDailyStats.sort((a, b) => a.date.compareTo(b.date));
  } catch (e) {
    print('Error fetching admin stats: $e');
  }

  await for (final event in rtdb.ref('dashboard_stats').onValue) {
    final data = event.snapshot.value as Map<dynamic, dynamic>? ?? {};

    final allRidesCount = (data['totalRides'] ?? 0) as int;
    final completedCount = (data['completedRides'] ?? 0) as int;
    final cancelledCount = (data['cancelledRides'] ?? 0) as int;
    final ongoingCount = (data['ongoingRides'] ?? 0) as int;
    
    final allDriversCount = (data['totalDrivers'] ?? 0) as int;
    final onlineDriversCount = (data['onlineDrivers'] ?? 0) as int;
    final allRidersCount = (data['totalRiders'] ?? 0) as int;
    
    final approvedDriversCount = (data['approvedDrivers'] ?? 0) as int;
    final blockedDriversCount = (data['blockedDrivers'] ?? 0) as int;

    final totalRevenue = ((data['totalRevenue'] ?? 0) as num).toDouble();

    final pendingDriversCount = allDriversCount - approvedDriversCount - blockedDriversCount;

    final completionRate = allRidesCount > 0
        ? (completedCount / allRidesCount) * 100
        : 0.0;
    final cancellationRate = allRidesCount > 0
        ? (cancelledCount / allRidesCount) * 100
        : 0.0;

    yield DashboardStats(
      totalRides: allRidesCount,
      completedRides: completedCount,
      cancelledRides: cancelledCount,
      ongoingRides: ongoingCount,
      totalDrivers: allDriversCount,
      approvedDrivers: approvedDriversCount,
      onlineDrivers: onlineDriversCount,
      pendingDrivers: pendingDriversCount > 0 ? pendingDriversCount : 0,
      totalRiders: allRidersCount,
      totalRevenue: totalRevenue,
      todayRevenue: todayRevenue,
      completionRate: completionRate,
      cancellationRate: cancellationRate,
      dailyStats: fetchedDailyStats,
    );
  }
});

// ============================================================
// LIVE MAP PROVIDER (SMART CACHE)
// ============================================================

class DriverProfileCache {
  final String name;
  final String phone;
  final String vehicleType;

  DriverProfileCache({
    required this.name,
    required this.phone,
    required this.vehicleType,
  });
}

class DriverMapModel {
  final String id;
  final String name;
  final String phone;
  final String vehicleType;
  final double lat;
  final double lng;
  final double heading;
  final String status;
  final String? rideId;

  DriverMapModel({
    required this.id,
    required this.name,
    required this.phone,
    required this.vehicleType,
    required this.lat,
    required this.lng,
    required this.heading,
    required this.status,
    this.rideId,
  });
}

class LiveMapNotifier extends StateNotifier<AsyncValue<List<DriverMapModel>>> {
  final Map<String, DriverProfileCache> _profileCache = {};
  Map<dynamic, dynamic> _lastRawData = {};
  // ignore: cancel_subscriptions
  var _sub;

  LiveMapNotifier() : super(const AsyncValue.loading()) {
    _sub = FirebaseDatabase.instance.ref('liveLocations').onValue.listen((event) {
      _lastRawData = event.snapshot.value as Map<dynamic, dynamic>? ?? {};
      _emitCurrentState();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _emitCurrentState() {
    final List<DriverMapModel> drivers = [];

    for (final entry in _lastRawData.entries) {
      final driverId = entry.key.toString();
      final locData = entry.value as Map<dynamic, dynamic>;

      final latRaw = locData['lat'];
      final lngRaw = locData['lng'];
      final headingRaw = locData['heading'];

      double latDouble = 0.0;
      double lngDouble = 0.0;
      double headingDouble = 0.0;

      if (latRaw is num) latDouble = latRaw.toDouble();
      if (latRaw is String) latDouble = double.tryParse(latRaw) ?? 0.0;

      if (lngRaw is num) lngDouble = lngRaw.toDouble();
      if (lngRaw is String) lngDouble = double.tryParse(lngRaw) ?? 0.0;

      if (headingRaw is num) headingDouble = headingRaw.toDouble();
      if (headingRaw is String) headingDouble = double.tryParse(headingRaw) ?? 0.0;

      // Skip invalid coordinates
      if (!latDouble.isFinite || !lngDouble.isFinite || (latDouble == 0.0 && lngDouble == 0.0)) {
        continue;
      }

      if (!_profileCache.containsKey(driverId)) {
        // Set placeholder
        _profileCache[driverId] = DriverProfileCache(name: 'Loading...', phone: '', vehicleType: 'auto');

        // Fetch asynchronously without blocking
        FirebaseFirestore.instance.collection('drivers').doc(driverId).get().then((doc) {
          if (doc.exists) {
            final docData = doc.data()!;
            _profileCache[driverId] = DriverProfileCache(
              name: docData['name'] ?? 'Unknown',
              phone: docData['phone'] ?? 'Unknown',
              vehicleType: docData['vehicleType'] ?? 'auto',
            );
          } else {
            _profileCache[driverId] = DriverProfileCache(name: 'Unknown', phone: '', vehicleType: 'auto');
          }
          if (mounted) _emitCurrentState();
        }).catchError((_) {
          _profileCache[driverId] = DriverProfileCache(name: 'Unknown', phone: '', vehicleType: 'auto');
          if (mounted) _emitCurrentState();
        });
      }

      final profile = _profileCache[driverId]!;
      
      // Do not display drivers on the map if they are still loading or if their profile is orphaned/unknown.
      // This prevents the "phantom auto" overlapping issue.
      if (profile.name == 'Loading...' || profile.name == 'Unknown') {
        continue;
      }

      final statusStr = locData['status'] as String? ?? 'offline';
      final rId = locData['rideId'] as String?;

      drivers.add(DriverMapModel(
        id: driverId,
        name: profile.name,
        phone: profile.phone,
        vehicleType: profile.vehicleType,
        lat: latDouble,
        lng: lngDouble,
        heading: headingDouble,
        status: statusStr,
        rideId: rId,
      ));
    }

    state = AsyncValue.data(drivers);
  }
}

final liveMapProvider = StateNotifierProvider<LiveMapNotifier, AsyncValue<List<DriverMapModel>>>((ref) {
  return LiveMapNotifier();
});
