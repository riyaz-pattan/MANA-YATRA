// lib/services/smart_tracker.dart
import 'dart:async';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dart_geohash/dart_geohash.dart';
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

  SmartTracker(this.driverId);

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
      });

      _lastLat = lat;
      _lastLng = lng;
      _lastUpdateTime = DateTime.now().millisecondsSinceEpoch;
    } catch (_) {}
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
