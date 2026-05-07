// lib/services/ride_signal_service.dart
import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:dart_geohash/dart_geohash.dart';
import '../config/constants.dart';

/// Listens to `ride_signals/` in RTDB and emits rides matching the driver's
/// current geohash-5 zone and vehicle type.
///
/// This replaces the old 10-second Firestore polling with a bandwidth-based
/// RTDB listener (near-zero cost at scale).
class RideSignalService {
  final String vehicleType;

  StreamSubscription<DatabaseEvent>? _sub;
  String? _currentGeohash5;
  final _controller = StreamController<List<Map<String, dynamic>>>.broadcast();
  final Map<String, Map<String, dynamic>> _activeSignals = {};

  final void Function(String)? onErrorCallback;

  RideSignalService({required this.vehicleType, this.onErrorCallback});

  /// Stream of nearby ride signals, auto-filtered by geohash and vehicle type.
  Stream<List<Map<String, dynamic>>> get ridesStream => _controller.stream;

  /// Start listening. Call this once, then update the zone via [updateZone].
  void start() {
    print('🚗 RideSignalService started for vehicleType: $vehicleType');
    _sub = FirebaseDatabase.instance
        .ref('ride_signals')
        .onValue
        .listen(_handleSnapshot, onError: (error) {
      print('❌ RideSignalService RTDB Error: $error');
      if (onErrorCallback != null) {
        onErrorCallback!('RTDB Error: $error');
      }
    });
  }

  /// Update the driver's current geohash-5 zone.
  /// Called whenever the driver moves enough for the SmartTracker to recalculate.
  void updateZone(double lat, double lng) {
    final newHash = GeoHasher().encode(lng, lat, precision: 5);
    if (newHash != _currentGeohash5) {
      print('📍 RideSignalService zone updated: $_currentGeohash5 -> $newHash');
      _currentGeohash5 = newHash;
      // Re-filter cached signals with the new zone
      _emitFiltered();
    }
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
    print('📡 RideSignalService total global signals: ${signals.length}');

    for (final entry in signals.entries) {
      final rideId = entry.key;
      if (entry.value is! Map) continue;
      final signal = Map<String, dynamic>.from(entry.value);
      signal['id'] = rideId;
      _activeSignals[rideId] = signal;
    }

    _emitFiltered();
  }

  void _emitFiltered() {
    if (_currentGeohash5 == null) {
      print('⚠️ RideSignalService _emitFiltered: _currentGeohash5 is null, returning empty.');
      _controller.add([]);
      return;
    }

    // Compute the 9-cell neighborhood for the driver's current position
    final neighbors = GeoHasher().neighbors(_currentGeohash5!);
    final myZones = <String>{
      _currentGeohash5!,
      ...neighbors.values,
    };

    int typeFiltered = 0;
    int zoneFiltered = 0;

    final filtered = _activeSignals.values.where((signal) {
      // 1. Must match vehicle type
      if (signal['vehicleType'] != vehicleType) {
        typeFiltered++;
        return false;
      }

      // 2. Filter out expired signals locally
      final now = DateTime.now().millisecondsSinceEpoch;
      final createdAtMs = (signal['createdAt'] as num?)?.toInt() ?? now;
      if (now - createdAtMs >= AppConstants.rideExpiryMinutes * 60 * 1000) {
        return false;
      }

      // 3. Must be in one of our 9 neighboring cells
      final signalHash = signal['geohash5'] as String?;
      if (signalHash == null || !myZones.contains(signalHash)) {
        zoneFiltered++;
        return false;
      }
      return true;
    }).toList();

    print('🔍 RideSignalService filtered: ${filtered.length} matched | $typeFiltered dropped by type | $zoneFiltered dropped by zone');

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
