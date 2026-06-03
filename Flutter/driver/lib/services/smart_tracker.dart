// lib/services/smart_tracker.dart
import 'dart:async';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dart_geohash/dart_geohash.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../config/constants.dart';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(LocationTaskHandler());
}

class LocationTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {}

  @override
  void onReceiveData(Object data) {}

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }

  @override
  void onNotificationDismissed() {}
}

enum TrackingMode { offline, discovery, activeRide }

class SmartTracker {
  final String driverId;
  TrackingMode _mode = TrackingMode.offline;
  double? _lastLat;
  double? _lastLng;
  StreamSubscription<Position>? _positionStream;
  Timer? _activeRideTimer;
  Timer? _retryTimer;
  Map<String, double>? _pendingLocation;
  double? _currentLat;
  double? _currentLng;
  double? _currentHeading;
  void Function(double lat, double lng, double heading)? onLocationUpdate;
  void Function(double lat, double lng)? onZoneChanged;

  // FCM zone topic tracking
  String? _currentGeohash5;
  String? _vehicleType;
  final Set<String> _subscribedTopics = {};

  SmartTracker(this.driverId) {
    _initForegroundTask();
  }

  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'gaman_tracking',
        channelName: 'Location Tracking',
        channelDescription: 'Keeps driver online in the background',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

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
      FlutterForegroundTask.stopService();
    } else if (mode == TrackingMode.discovery && prev != TrackingMode.discovery) {
      _startForegroundService("You are online and ready for rides");
      _startWatching();
      _stopActiveRideTimer();
      if (_currentLat != null) _pushToFirebase(_currentLat!, _currentLng!, _currentHeading ?? 0.0);
    } else if (mode == TrackingMode.activeRide) {
      _startForegroundService("Actively navigating on a ride");
      _startWatching();
      _startActiveRideTimer();
      if (_currentLat != null) _pushToFirebase(_currentLat!, _currentLng!, _currentHeading ?? 0.0);
    }
  }

  Future<void> _startForegroundService(String message) async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'Gaman Driver',
        notificationText: message,
      );
    } else {
      await FlutterForegroundTask.startService(
        notificationTitle: 'Gaman Driver',
        notificationText: message,
        callback: startCallback,
      );
    }
  }


  void _startWatching() {
    if (_positionStream != null) return;
    _startRetryTimer();

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
          if (_lastLat == null ||
              distance > 20.0) {
            _pushToFirebase(_currentLat!, _currentLng!, _currentHeading ?? 0.0);
          } else {
            // Unconditionally touch the RTDB timestamp so Rider app doesn't mark it stale
            FirebaseDatabase.instance
                .ref('liveLocations/$driverId/updatedAt')
                .set(ServerValue.timestamp);
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
    _stopRetryTimer();
  }

  void _startRetryTimer() {
    if (_retryTimer != null) return;
    _retryTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_pendingLocation != null) {
        _pushToFirebase(_pendingLocation!['lat']!, _pendingLocation!['lng']!, _pendingLocation!['heading'] ?? 0.0);
      }
    });
  }

  void _stopRetryTimer() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void _handlePosition(Position pos) {
    _currentLat = pos.latitude.clamp(-90.0, 90.0);
    _currentLng = pos.longitude.clamp(-180.0, 180.0);

    final heading = pos.heading;
    _currentHeading = heading;

    // Notify UI immediately
    onLocationUpdate?.call(_currentLat!, _currentLng!, heading);

    if (_mode == TrackingMode.offline) return;

    final distance = _haversine(_lastLat, _lastLng, _currentLat!, _currentLng!);
    // Use 500m for discovery, 20m for active rides
    final threshold = _mode == TrackingMode.activeRide ? 20.0 : AppConstants.discoveryMinDistanceM;

    final shouldUpdate = _lastLat == null || distance > threshold;

    if (shouldUpdate) {
      _pushToFirebase(_currentLat!, _currentLng!, heading);
    }
  }

  Future<void> _pushToFirebase(double lat, double lng, double heading) async {
    // Update coordinates immediately to prevent GPS spamming if offline
    _lastLat = lat;
    _lastLng = lng;

    try {
      // 1. Realtime DB
      await FirebaseDatabase.instance
          .ref('liveLocations/$driverId')
          .set({'lat': lat, 'lng': lng, 'heading': heading, 'updatedAt': ServerValue.timestamp});

      // 2. Firestore with geohash
      final geohash = GeoHasher().encode(lng, lat, precision: 6);
      await FirebaseFirestore.instance
          .collection('drivers')
          .doc(driverId)
          .update({
        'lat': lat,
        'lng': lng,
        'heading': heading,
        'geohash': geohash,
        'lastLocationUpdate': FieldValue.serverTimestamp(),
      });

      // 3. Update FCM zone topics if geohash-5 changed
      final newHash5 = GeoHasher().encode(lng, lat, precision: 5);
      if (newHash5 != _currentGeohash5 && _mode == TrackingMode.discovery) {
        _currentGeohash5 = newHash5;
        await _updateZoneTopics(newHash5);
        onZoneChanged?.call(lat, lng);
      }

      // Success, clear any pending location
      _pendingLocation = null;
    } catch (e) {
      // Save for retry queue
      _pendingLocation = {'lat': lat, 'lng': lng, 'heading': heading};
      debugPrint('SmartTracker: Firebase push failed, queued for retry. Error: $e');
    }
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
