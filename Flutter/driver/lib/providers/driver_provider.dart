import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/smart_tracker.dart';

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
  double? _lat;
  double? _lng;
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
  Map<String, dynamic>? get activeRide => _activeRide;
  SmartTracker? get tracker => _tracker;
  String? get persistedRideId => _persistedRideId;

  // Backward-compatible getters
  bool get isOnline => _driverState != DriverState.offline;
  bool get isBusy => _driverState == DriverState.onRide;

  bool get isApproved => _profile?['isApproved'] == true || _profile?['isApproved'] == 'true';
  bool get isBlocked => _profile?['isBlocked'] == true || _profile?['isBlocked'] == 'true';
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
      // Mark profile as loading until first Firestore snapshot arrives
      _profileLoading = true;

      if (_tracker == null) {
        _tracker = SmartTracker(user.uid);
        _tracker!.onLocationUpdate = (lat, lng) {
          _lat = lat;
          _lng = lng;
          notifyListeners();
        };
      }
      
      _setupPresence();
      
      // Start real-time profile listener
      _profileSubscription = FirebaseFirestore.instance
          .collection('drivers')
          .doc(user.uid)
          .snapshots()
          .listen((snap) {
        if (snap.exists) {
          setProfile(snap.data());
        } else {
          // No profile doc — stop loading so AuthGate shows OnboardingScreen
          _profileLoading = false;
          _profile = null;
          notifyListeners();
        }
      }, onError: (error) {
        debugPrint('[DriverProvider] Profile listener error: $error');
        _profileLoading = false;
        notifyListeners();
      });
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

  void setProfile(Map<String, dynamic>? profile) {
    _profile = profile;
    _profileLoading = false; // First snapshot received — done loading
    if (profile != null) {
      // Read driverState, with migration fallback from old isOnline field
      final state = profile['driverState'] as String?;
      if (state != null) {
        _driverState = state;
      } else {
        // Migration: old documents only have isOnline
        _driverState = profile['isOnline'] == true
            ? DriverState.onlineIdle
            : DriverState.offline;
      }
    }
    notifyListeners();
  }

  void setOnline(bool online) {
    _driverState = online ? DriverState.onlineIdle : DriverState.offline;
    if (_tracker != null) {
      _tracker!.setMode(
          online ? TrackingMode.discovery : TrackingMode.offline);
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
    _persistRideId(ride?['id'] as String?);
    if (_tracker != null) {
      _tracker!.setMode(ride != null
          ? TrackingMode.activeRide
          : (isOnline ? TrackingMode.discovery : TrackingMode.offline));
    }
    notifyListeners();
  }

  Future<void> _persistRideId(String? rideId) async {
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
          if (status == 'matched' || status == 'started') {
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
      debugPrint('[DriverProvider] Firestore validation failed, falling back to local: $e');
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

  void updateLocation(double lat, double lng) {
    _lat = lat;
    _lng = lng;
    notifyListeners();
  }

  void _setupPresence() {
    _connectedSubscription?.cancel();
    if (_user == null) return;
    
    _connectedSubscription = FirebaseDatabase.instance.ref('.info/connected').onValue.listen((event) {
      final connected = event.snapshot.value as bool? ?? false;
      if (connected && isOnline) {
        _setPresence(true);
      }
    }, onError: (error) {
      debugPrint('[DriverProvider] Presence listener error: $error');
    });
  }

  Future<void> _setPresence(bool online) async {
    if (_user == null) return;
    final presenceRef = FirebaseDatabase.instance.ref('presence/${_user!.uid}');
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        if (online) {
          await presenceRef.onDisconnect().update({'isOnline': false, 'updatedAt': ServerValue.timestamp});
          await presenceRef.set({'isOnline': true, 'updatedAt': ServerValue.timestamp});
        } else {
          await presenceRef.onDisconnect().cancel();
          await presenceRef.update({'isOnline': false, 'updatedAt': ServerValue.timestamp});
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
