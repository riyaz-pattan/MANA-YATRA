// lib/services/smart_tracker.dart
import 'dart:async';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dart_geohash/dart_geohash.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../config/constants.dart';

enum TrackingMode { offline, discovery, activeRide }

class SmartTracker {
  final String driverId;
  TrackingMode _mode = TrackingMode.offline;
  double? _lastLat;
  double? _lastLng;
  int _lastUpdateTime = 0;
  StreamSubscription<Position>? _positionStream;
  Timer? _activeRideTimer;
  double? _currentLat;
  double? _currentLng;
  void Function(double lat, double lng)? onLocationUpdate;
  void Function(double lat, double lng)? onZoneChanged;

  // FCM zone topic tracking
  String? _currentGeohash5;
  String? _vehicleType;
  final Set<String> _subscribedTopics = {};

  SmartTracker(this.driverId);

  String? get currentGeohash5 => _currentGeohash5;

  void setVehicleType(String type) {
    _vehicleType = type;
  }

  TrackingMode get mode => _mode;

  void setMode(TrackingMode mode) {
    final prev = _mode;
    _mode = mode;

    if (mode == TrackingMode.offline) {
      _stopAll();
    } else if (mode == TrackingMode.discovery && prev != TrackingMode.discovery) {
      _startWatching();
      _stopActiveRideTimer();
    } else if (mode == TrackingMode.activeRide) {
      _startWatching();
      _startActiveRideTimer();
    }
  }

  void _startWatching() {
    if (_positionStream != null) return;

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen(_handlePosition, onError: (e) {
      // GPS error, ignore
    });
  }

  void _stopWatching() {
    _positionStream?.cancel();
    _positionStream = null;
  }

  void _startActiveRideTimer() {
    if (_activeRideTimer != null) return;
    // Timer checks periodically; pushes if distance > 500m or time > 2 min
    _activeRideTimer = Timer.periodic(
      Duration(milliseconds: AppConstants.activeRideIntervalMs),
      (_) {
        if (_currentLat != null && _mode == TrackingMode.activeRide) {
          final distance = _haversine(
              _lastLat, _lastLng, _currentLat!, _currentLng!);
          final elapsed =
              DateTime.now().millisecondsSinceEpoch - _lastUpdateTime;
          if (_lastLat == null ||
              distance > AppConstants.discoveryMinDistanceM ||
              elapsed > AppConstants.discoveryIntervalMs) {
            _pushToFirebase(_currentLat!, _currentLng!);
          }
        }
      },
    );
  }

  void _stopActiveRideTimer() {
    _activeRideTimer?.cancel();
    _activeRideTimer = null;
  }

  void _stopAll() {
    _stopWatching();
    _stopActiveRideTimer();
  }

  void _handlePosition(Position pos) {
    _currentLat = pos.latitude;
    _currentLng = pos.longitude;

    // Notify UI immediately
    onLocationUpdate?.call(pos.latitude, pos.longitude);

    if (_mode == TrackingMode.offline) return;

    // Both discovery and active ride: push if 500m+ moved
    final distance = _haversine(_lastLat, _lastLng, pos.latitude, pos.longitude);
    final elapsed = DateTime.now().millisecondsSinceEpoch - _lastUpdateTime;

    final shouldUpdate = _lastLat == null ||
        distance > AppConstants.discoveryMinDistanceM ||
        elapsed > AppConstants.discoveryIntervalMs;

    if (shouldUpdate) {
      _pushToFirebase(pos.latitude, pos.longitude);
    }
  }

  Future<void> _pushToFirebase(double lat, double lng) async {
    try {
      // 1. Realtime DB
      await FirebaseDatabase.instance
          .ref('liveLocations/$driverId')
          .set({'lat': lat, 'lng': lng, 'updatedAt': ServerValue.timestamp});

      // 2. Firestore with geohash
      final geohash = GeoHasher().encode(lng, lat, precision: 6);
      await FirebaseFirestore.instance
          .collection('drivers')
          .doc(driverId)
          .update({
        'lat': lat,
        'lng': lng,
        'geohash': geohash,
        'lastLocationUpdate': FieldValue.serverTimestamp(),
        'lastHeartbeat': FieldValue.serverTimestamp(),
      });

      // 3. Update FCM zone topics if geohash-5 changed
      final newHash5 = GeoHasher().encode(lng, lat, precision: 5);
      if (newHash5 != _currentGeohash5 && _mode == TrackingMode.discovery) {
        _currentGeohash5 = newHash5;
        await _updateZoneTopics(newHash5);
        onZoneChanged?.call(lat, lng);
      }

      _lastLat = lat;
      _lastLng = lng;
      _lastUpdateTime = DateTime.now().millisecondsSinceEpoch;
    } catch (_) {}
  }

  /// Subscribe to 9-cell FCM topics (geohash-5) + 1 wider geohash-4 topic.
  /// The geohash-4 topic enables the expanded search phase (Phase 2).
  Future<void> _updateZoneTopics(String centerHash) async {
    if (_vehicleType == null) return;

    final neighbors = GeoHasher().neighbors(centerHash);
    final newTopics = <String>{
      'zone_${centerHash}_$_vehicleType',
      ...neighbors.values.map((h) => 'zone_${h}_$_vehicleType'),
    };

    // Add geohash-4 topic for expanded search reach (~20km radius)
    final geohash4 = centerHash.substring(0, 4);
    newTopics.add('zone_${geohash4}_$_vehicleType');

    // Unsubscribe from old topics not in the new set
    final toUnsub = _subscribedTopics.difference(newTopics);
    for (final t in toUnsub) {
      await FirebaseMessaging.instance.unsubscribeFromTopic(t);
    }

    // Subscribe to new topics not in the old set
    final toSub = newTopics.difference(_subscribedTopics);
    for (final t in toSub) {
      await FirebaseMessaging.instance.subscribeToTopic(t);
    }

    _subscribedTopics
      ..clear()
      ..addAll(newTopics);
  }

  double _haversine(double? lat1, double? lng1, double lat2, double lng2) {
    if (lat1 == null || lng1 == null) return double.infinity;
    const r = 6371000.0;
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) * cos(_toRad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _toRad(double d) => d * pi / 180;

  void destroy() {
    _stopAll();
    onLocationUpdate = null;
  }
}
