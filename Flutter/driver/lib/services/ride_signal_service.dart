// lib/services/ride_signal_service.dart
import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:dart_geohash/dart_geohash.dart';
import '../config/constants.dart';

/// Listens to `ride_signals/{vehicleType}/{geohash5}/` in RTDB and emits
/// rides matching the driver's current geohash-5 zone.
///
/// Instead of listening to the global root (which broadcasts ALL rides to
/// ALL drivers), this service subscribes ONLY to the driver's current
/// zone — dramatically reducing bandwidth, battery drain, and rebuild storms.
class RideSignalService {
  final String vehicleType;

  StreamSubscription<DatabaseEvent>? _sub;
  String? _currentGeohash5;
  final _controller = StreamController<List<Map<String, dynamic>>>.broadcast();
  final Map<String, Map<String, dynamic>> _activeSignals = {};

  final void Function(String)? onErrorCallback;

  RideSignalService({required this.vehicleType, this.onErrorCallback});

  /// Stream of nearby ride signals, auto-scoped by zone and vehicle type.
  Stream<List<Map<String, dynamic>>> get ridesStream => _controller.stream;

  /// Start the service. Does NOT subscribe to RTDB yet — call [updateZone]
  /// with the driver's location to begin listening.
  void start() {
    print('🚗 RideSignalService started for vehicleType: $vehicleType');
    // Subscription is created dynamically in updateZone() when we know
    // the driver's geohash. No global listener needed.
  }

  /// Update the driver's current geohash-5 zone.
  /// When the zone changes, the old listener is cancelled and a new one
  /// is created on the correct path: ride_signals/{vehicleType}/{newHash}/
  void updateZone(double lat, double lng) {
    final newHash = GeoHasher().encode(lng, lat, precision: 5);
    if (newHash != _currentGeohash5) {
      print('📍 RideSignalService zone updated: $_currentGeohash5 -> $newHash');
      _currentGeohash5 = newHash;
      _subscribeToZone(newHash);
    }
  }

  /// Cancel the existing listener and subscribe to the new zone path.
  void _subscribeToZone(String geohash5) {
    // Cancel old subscription
    _sub?.cancel();
    _activeSignals.clear();

    final path = 'ride_signals/$vehicleType/$geohash5';
    print('📡 RideSignalService subscribing to: $path');

    _sub = FirebaseDatabase.instance
        .ref(path)
        .orderByChild('createdAt')
        .limitToLast(50)
        .onValue
        .listen(_handleSnapshot, onError: (error) {
      print('❌ RideSignalService RTDB Error: $error');
      if (onErrorCallback != null) {
        onErrorCallback!('RTDB Error: $error');
      }
    });
  }

  void _handleSnapshot(DatabaseEvent event) {
    _activeSignals.clear();

    final data = event.snapshot.value;
    print('📡 RideSignalService received snapshot, data is null? ${data == null}');

    if (data == null || data is! Map) {
      _controller.add([]);
      return;
    }

    final signals = Map<String, dynamic>.from(data);
    print('📡 RideSignalService zone signals: ${signals.length}');

    final now = DateTime.now().millisecondsSinceEpoch;

    for (final entry in signals.entries) {
      final rideId = entry.key;
      if (entry.value is! Map) continue;
      final signal = Map<String, dynamic>.from(entry.value);
      signal['id'] = rideId;

      // Filter out expired signals locally
      final createdAtMs = (signal['createdAt'] as num?)?.toInt() ?? now;
      if (now - createdAtMs >= AppConstants.rideExpiryMinutes * 60 * 1000) {
        continue;
      }

      _activeSignals[rideId] = signal;
    }

    _emitFiltered();
  }

  void _emitFiltered() {
    // No geohash/vehicleType filtering needed — the RTDB path already
    // scopes to the correct vehicleType and zone.
    final filtered = _activeSignals.values.toList();

    print('🔍 RideSignalService emitting ${filtered.length} signals from zone $_currentGeohash5');

    // Sort by createdAt descending (newest first)
    filtered.sort((a, b) {
      final aTime = (a['createdAt'] as num?) ?? 0;
      final bTime = (b['createdAt'] as num?) ?? 0;
      return bTime.compareTo(aTime);
    });

    _controller.add(filtered);
  }

  void dispose() {
    _sub?.cancel();
    _controller.close();
  }
}
