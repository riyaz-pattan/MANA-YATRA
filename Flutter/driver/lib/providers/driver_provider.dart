import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/smart_tracker.dart';
import '../utils/device_session_manager.dart';

/// Driver states for the state machine.
/// OFFLINE → ONLINE_IDLE → BIDDING → ON_RIDE
class DriverState {
  static const String offline = 'OFFLINE';
  static const String onlineIdle = 'ONLINE_IDLE';
  static const String bidding = 'BIDDING';
  static const String onRide = 'ON_RIDE';
}

class DriverProvider extends ChangeNotifier {
  User? _user;
  bool _authLoading = true;
  bool _profileLoading = false;
  Map<String, dynamic>? _profile;
  String _driverState = DriverState.offline;
  SmartTracker? _tracker;
  int _presenceReqId = 0;
  double? _lat;
  double? _lng;
  double? _heading;
  Map<String, dynamic>? _activeRide;
  StreamSubscription<DocumentSnapshot>? _profileSubscription;
  StreamSubscription<DatabaseEvent>? _connectedSubscription;
  String? _persistedRideId;

  static const _kActiveRideKey = 'driver_active_ride_id';

  // Getters
  User? get user => _user;
  bool get authLoading => _authLoading;
  bool get profileLoading => _profileLoading;
  bool get isLoggedIn => _user != null && !_authLoading;
  Map<String, dynamic>? get profile => _profile;
  String get driverState => _driverState;
  double? get lat => _lat;
  double? get lng => _lng;
  double? get heading => _heading;
  Map<String, dynamic>? get activeRide => _activeRide;
  SmartTracker? get tracker => _tracker;
  String? get persistedRideId => _persistedRideId;

  // Backward-compatible getters
  bool get isOnline => _driverState != DriverState.offline;
  bool get isBusy => _driverState == DriverState.onRide;

  bool get isApproved =>
      _profile?['isApproved'] == true || _profile?['isApproved'] == 'true';
  bool get isBlocked =>
      _profile?['isBlocked'] == true || _profile?['isBlocked'] == 'true';
  bool get hasProfile => _profile != null;
  bool get isSubscriptionActive {
    if (_profile == null) return false;
    final until = _profile!['subscriptionActiveUntil'];
    if (until == null) return false;
    if (until is Timestamp) return until.toDate().isAfter(DateTime.now());
    if (until is DateTime) return until.isAfter(DateTime.now());
    return false;
  }

  void setUser(User? user) {
    _user = user;
    _authLoading = false;

    // Cancel existing subscription if any
    _profileSubscription?.cancel();

    if (user != null) {
      _initSessionAndListen(user);
    } else {
      _profile = null;
      _profileLoading = false;
      _driverState = DriverState.offline;
      _connectedSubscription?.cancel();
      _tracker?.destroy();
      _tracker = null;
    }
    notifyListeners();
  }

  Future<void> _initSessionAndListen(User user) async {
    _profileLoading = true;
    // Always start offline on fresh session
    _driverState = DriverState.offline;
    notifyListeners();

    if (_tracker == null) {
      _tracker = SmartTracker(user.uid);
      _tracker!.onLocationUpdate = (lat, lng, heading) {
        _lat = lat;
        _lng = lng;
        _heading = heading;
        notifyListeners();
      };
    }

    _setupPresence();
    _setPresence(false); // Start with offline presence

    final localDeviceId = await DeviceSessionManager.getDeviceId();

    // Update Firestore with the current device ID and force offline state
    try {
      await FirebaseFirestore.instance.collection('drivers').doc(user.uid).set({
        'deviceId': localDeviceId,
        'driverState': DriverState.offline,
        'isOnline': false,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[DriverProvider] Failed to update deviceId: $e');
    }

    // Start real-time profile listener
    _profileSubscription = FirebaseFirestore.instance
        .collection('drivers')
        .doc(user.uid)
        .snapshots()
        .listen(
          (snap) {
            if (snap.exists) {
              final data = snap.data()!;
              final remoteDeviceId = data['deviceId'] as String?;

              // If the database device ID changes and doesn't match our local device ID,
              // it means the user logged in from another device.
              if (remoteDeviceId != null && remoteDeviceId != localDeviceId) {
                debugPrint(
                  '[DriverProvider] Logged in from another device. Forcing logout.',
                );

                SharedPreferences.getInstance().then((prefs) {
                  prefs.setBool('kicked_out', true);
                  FirebaseAuth.instance.signOut();
                });
                return;
              }

              setProfile(data);
            } else {
              // No profile doc — stop loading so AuthGate shows OnboardingScreen
              _profileLoading = false;
              _profile = null;
              notifyListeners();
            }
          },
          onError: (error) {
            debugPrint('[DriverProvider] Profile listener error: $error');
            _profileLoading = false;
            notifyListeners();
          },
        );
  }

  void setProfile(Map<String, dynamic>? profile) {
    _profile = profile;
    _profileLoading = false; // First snapshot received — done loading

    // If the server forced us offline (e.g., cron job expired subscription, or admin block),
    // sync the local memory state to match.
    if (profile != null &&
        profile['isOnline'] == false &&
        _driverState != DriverState.offline) {
      _driverState = DriverState.offline;
      if (_tracker != null) {
        _tracker!.setMode(TrackingMode.offline);
      }
    }

    notifyListeners();
  }

  void setOnline(bool online) {
    _driverState = online ? DriverState.onlineIdle : DriverState.offline;
    if (_tracker != null) {
      _tracker!.setMode(online ? TrackingMode.discovery : TrackingMode.offline);
    }
    _setPresence(online);
    notifyListeners();
  }

  void setDriverState(String state) {
    _driverState = state;
    notifyListeners();
  }

  void setActiveRide(Map<String, dynamic>? ride) {
    _activeRide = ride;
    final rideId = ride?['id'] as String?;
    _persistRideId(rideId);
    if (_tracker != null) {
      _tracker!.setRideId(rideId);
      _tracker!.setMode(
        ride != null
            ? TrackingMode.activeRide
            : (isOnline ? TrackingMode.discovery : TrackingMode.offline),
      );
    }
    notifyListeners();
  }

  Future<void> _persistRideId(String? rideId) async {
    _persistedRideId = rideId;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (rideId != null) {
        await prefs.setString(_kActiveRideKey, rideId);
      } else {
        await prefs.remove(_kActiveRideKey);
      }
    } catch (e) {
      debugPrint('[DriverProvider] Failed to persist rideId: $e');
    }
  }

  /// Called once at app startup to check if a ride was in progress
  /// when the app was last killed.
  /// Validates against Firestore to prevent recovering into a finished ride.
  Future<void> loadPersistedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_kActiveRideKey);
      if (id != null && id.isNotEmpty) {
        // Validate the ride is still active in Firestore
        final rideDoc = await FirebaseFirestore.instance
            .collection('rides')
            .doc(id)
            .get();

        if (rideDoc.exists) {
          final status = rideDoc.data()?['status'] as String?;
          if (status == 'matched' ||
              status == 'started' ||
              status == 'payment_pending') {
            _persistedRideId = id;
            notifyListeners();
            return;
          }
        }

        // Ride is finished or doesn't exist — clear stale persistence
        await prefs.remove(_kActiveRideKey);
        _persistedRideId = null;
      }
    } catch (e) {
      // On network error, still recover from local state (offline-first)
      debugPrint(
        '[DriverProvider] Firestore validation failed, falling back to local: $e',
      );
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_kActiveRideKey);
      if (id != null && id.isNotEmpty) {
        _persistedRideId = id;
        notifyListeners();
      }
    }
  }

  void clearPersistedRideId() {
    _persistedRideId = null;
    _persistRideId(null);
    notifyListeners();
  }

  void updateLocation(double lat, double lng, double heading) {
    _lat = lat;
    _lng = lng;
    _heading = heading;
    notifyListeners();
  }

  void _setupPresence() {
    _connectedSubscription?.cancel();
    if (_user == null) return;

    _connectedSubscription = FirebaseDatabase.instance
        .ref('.info/connected')
        .onValue
        .listen(
          (event) {
            final connected = event.snapshot.value as bool? ?? false;
            if (connected && isOnline) {
              _setPresence(true);
            }
          },
          onError: (error) {
            debugPrint('[DriverProvider] Presence listener error: $error');
          },
        );
  }

  Future<void> _setPresence(bool online) async {
    if (_user == null) return;

    _presenceReqId++;
    final currentReqId = _presenceReqId;

    final presenceRef = FirebaseDatabase.instance.ref('presence/${_user!.uid}');
    for (int attempt = 0; attempt < 2; attempt++) {
      if (currentReqId != _presenceReqId)
        return; // Abort if newer request exists
      try {
        if (online) {
          await presenceRef.onDisconnect().update({
            'isOnline': false,
            'updatedAt': ServerValue.timestamp,
          });
          if (currentReqId != _presenceReqId)
            return; // Re-check before final set
          await presenceRef.set({
            'isOnline': true,
            'updatedAt': ServerValue.timestamp,
          });
        } else {
          await presenceRef.onDisconnect().cancel();
          if (currentReqId != _presenceReqId)
            return; // Re-check before final update
          await presenceRef.update({
            'isOnline': false,
            'updatedAt': ServerValue.timestamp,
          });
        }
        return; // success
      } catch (e) {
        debugPrint('[Presence] Attempt ${attempt + 1} failed: $e');
        if (attempt == 0) await Future.delayed(const Duration(seconds: 2));
      }
    }
  }

  @override
  void dispose() {
    _profileSubscription?.cancel();
    _connectedSubscription?.cancel();
    _tracker?.destroy();
    super.dispose();
  }
}
