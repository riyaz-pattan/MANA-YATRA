// lib/providers/ride_provider.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/google_maps_service.dart';
import '../utils/device_session_manager.dart';

class RideProvider extends ChangeNotifier {
  // Auth state: null = loading, User object or 'logged_out' sentinel
  User? _user;
  bool _authLoading = true;

  // Location
  LocationResult? _pickup;
  LocationResult? _drop;
  RouteInfo? _route;

  // Ride config
  String _vehicleType = '';
  int _bidPrice = 80;
  String _paymentMethod = 'Cash';

  // Active ride
  Map<String, dynamic>? _activeRide;
  Map<String, dynamic>? _selectedBid;
  String? _persistedRideId; // Loaded from SharedPreferences on startup
  StreamSubscription<DocumentSnapshot>? _profileSubscription;

  static const _kActiveRideKey = 'rider_active_ride_id';

  // Getters
  User? get user => _user;
  bool get authLoading => _authLoading;
  bool get isLoggedIn => _user != null && !_authLoading;
  LocationResult? get pickup => _pickup;
  LocationResult? get drop => _drop;
  RouteInfo? get route => _route;
  String get vehicleType => _vehicleType;
  int get bidPrice => _bidPrice;
  String get paymentMethod => _paymentMethod;
  Map<String, dynamic>? get activeRide => _activeRide;
  Map<String, dynamic>? get selectedBid => _selectedBid;
  /// Non-null when we recovered a ride ID from local storage on cold start.
  String? get persistedRideId => _persistedRideId;

  // Setters
  void setUser(User? user) {
    _user = user;
    _authLoading = false;
    _profileSubscription?.cancel();
    
    if (user != null) {
      _initSessionAndListen(user);
    } else {
      _profileSubscription?.cancel();
    }
    notifyListeners();
  }

  Future<void> _initSessionAndListen(User user) async {
    // Subscribe to relevant FCM topics for the user
    try {
      FirebaseMessaging.instance.subscribeToTopic('all_riders');
      FirebaseMessaging.instance.subscribeToTopic('riders');
      FirebaseMessaging.instance.subscribeToTopic('rider_${user.uid}');
    } catch (e) {
      debugPrint('[RideProvider] FCM subscription error: $e');
    }
    
    final localDeviceId = await DeviceSessionManager.getDeviceId();
    
    // Update Firestore with the current device ID
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'deviceId': localDeviceId,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[RideProvider] Failed to update deviceId: $e');
    }
    
    // Start real-time profile listener
    _profileSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((snap) {
      if (snap.exists) {
        final data = snap.data()!;
        final remoteDeviceId = data['deviceId'] as String?;
        
        // If the database device ID changes and doesn't match our local device ID,
        // it means the user logged in from another device.
        if (remoteDeviceId != null && remoteDeviceId != localDeviceId) {
          debugPrint('[RideProvider] Logged in from another device. Forcing logout.');
          
          // Clean up stream subscriptions before logging out
          setUser(null);
          
          SharedPreferences.getInstance().then((prefs) {
            prefs.setBool('kicked_out', true);
            FirebaseAuth.instance.signOut();
          });
          return;
        }
      }
    }, onError: (error) {
      debugPrint('[RideProvider] Profile listener error: $error');
    });
  }

  void setPickup(LocationResult? pickup) {
    _pickup = pickup;
    notifyListeners();
  }

  void setDrop(LocationResult? drop) {
    _drop = drop;
    notifyListeners();
  }

  void setRoute(RouteInfo? route) {
    _route = route;
    notifyListeners();
  }

  void setVehicleType(String type) {
    _vehicleType = type;
    notifyListeners();
  }

  void setBidPrice(int price) {
    _bidPrice = price;
    notifyListeners();
  }

  void setPaymentMethod(String method) {
    _paymentMethod = method;
    notifyListeners();
  }

  void setActiveRide(Map<String, dynamic>? ride) {
    _activeRide = ride;
    _persistRideId(ride?['id'] as String?);
    notifyListeners();
  }

  /// Persist the active ride ID to local storage so we can recover
  /// after an unexpected app kill.
  Future<void> _persistRideId(String? rideId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (rideId != null) {
        await prefs.setString(_kActiveRideKey, rideId);
      } else {
        await prefs.remove(_kActiveRideKey);
      }
    } catch (e) {
      debugPrint('[RideProvider] Failed to persist rideId: $e');
    }
  }

  /// Called once at app startup (from AuthGate) to check if a ride was
  /// in progress when the app was last killed.
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
          // Only recover if ride is in an active state
          if (status == 'searching' || status == 'bidding' || 
              status == 'matched' || status == 'started') {
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
      debugPrint('[RideProvider] Firestore validation failed, falling back to local: $e');
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_kActiveRideKey);
      if (id != null && id.isNotEmpty) {
        _persistedRideId = id;
        notifyListeners();
      }
    }
  }

  /// Clears the local persisted ride id — call this once the live
  /// Firestore listener confirms the ride is completed/cancelled.
  void clearPersistedRideId() {
    _persistedRideId = null;
    _persistRideId(null);
    notifyListeners();
  }

  void setSelectedBid(Map<String, dynamic>? bid) {
    _selectedBid = bid;
    notifyListeners();
  }

  void resetRide() {
    _pickup = null;
    _activeRide = null;
    _selectedBid = null;
    _drop = null;
    _route = null;
    // Also clear persisted ride ID to prevent stale recovery on next app start
    clearPersistedRideId();
    notifyListeners();
  }

  @override
  void dispose() {
    _profileSubscription?.cancel();
    super.dispose();
  }
}
