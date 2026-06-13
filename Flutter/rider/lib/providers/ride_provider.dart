// lib/providers/ride_provider.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dart_geohash/dart_geohash.dart';
import 'package:geolocator/geolocator.dart';
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
  bool _shouldCalculateRoute = false;

  // Ride config
  String _vehicleType = 'auto';
  int _bidPrice = 80;
  String _paymentMethod = 'Cash';

  // Active ride
  Map<String, dynamic>? _activeRide;
  Map<String, dynamic>? _selectedBid;
  String? _persistedRideId; // Loaded from SharedPreferences on startup
  String? _persistedRideStatus; // Tracks status on startup recovery
  StreamSubscription<DocumentSnapshot>? _profileSubscription;

  static const _kActiveRideKey = 'rider_active_ride_id';

  // Nearby Drivers Tracking
  List<Map<String, dynamic>> _nearbyDrivers = [];
  StreamSubscription<QuerySnapshot>? _driversSubscription;
  Timer? _etaUpdateTimer;

  // Getters
  User? get user => _user;
  bool get authLoading => _authLoading;
  bool get isLoggedIn => _user != null && !_authLoading;
  LocationResult? get pickup => _pickup;
  LocationResult? get drop => _drop;
  RouteInfo? get route => _route;
  bool get shouldCalculateRoute => _shouldCalculateRoute;
  String get vehicleType => _vehicleType;
  int get bidPrice => _bidPrice;
  String get paymentMethod => _paymentMethod;
  Map<String, dynamic>? get activeRide => _activeRide;
  Map<String, dynamic>? get selectedBid => _selectedBid;
  /// Non-null when we recovered a ride ID from local storage on cold start.
  String? get persistedRideId => _persistedRideId;
  String? get persistedRideStatus => _persistedRideStatus;
  List<Map<String, dynamic>> get nearbyDrivers => _nearbyDrivers;

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
    _listenForNearbyDrivers();
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

  void triggerRouteCalculation() {
    _shouldCalculateRoute = true;
    notifyListeners();
  }

  void clearRouteCalculationFlag() {
    _shouldCalculateRoute = false;
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
    _persistedRideId = rideId;
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
            _persistedRideStatus = status;
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
    _persistedRideStatus = null;
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
    _nearbyDrivers.clear();
    _driversSubscription?.cancel();
    _etaUpdateTimer?.cancel();
    // Also clear persisted ride ID to prevent stale recovery on next app start
    clearPersistedRideId();
    notifyListeners();
  }

  void _listenForNearbyDrivers() {
    debugPrint('[RideProvider] _listenForNearbyDrivers called.');
    _driversSubscription?.cancel();
    _etaUpdateTimer?.cancel();
    _nearbyDrivers.clear();

    if (_pickup == null) {
      debugPrint('[RideProvider] _pickup is null, aborting driver search.');
      return;
    }

    debugPrint('[RideProvider] Pickup Location: ${_pickup!.lat}, ${_pickup!.lng}');

    // Use Geohash precision 4 (approx 39km x 19km bounding box).
    // This allows us to find all nearby drivers in one simple range query,
    // and then filter down to a strict 5km circle locally.
    final hash4 = GeoHasher().encode(_pickup!.lng, _pickup!.lat, precision: 4);
    debugPrint('[RideProvider] Generated hash4 for query: $hash4');

    _driversSubscription = FirebaseFirestore.instance
        .collection('drivers')
        .where('geohash', isGreaterThanOrEqualTo: hash4)
        .where('geohash', isLessThan: '$hash4~')
        .snapshots()
        .listen((snap) {
      debugPrint('[RideProvider] Firestore snapshot received. Total docs returned by geohash query: ${snap.docs.length}');
      
      final drivers = <Map<String, dynamic>>[];
      for (var doc in snap.docs) {
        final data = doc.data();
        debugPrint('[RideProvider] Evaluating driver doc: ${doc.id} | isOnline: ${data['isOnline']} | lat: ${data['lat']} | lng: ${data['lng']} | geohash: ${data['geohash']} | type: ${data['vehicleType']}');
        
        if (data['isOnline'] == true && data['lat'] != null && data['lng'] != null) {
          final dist = Geolocator.distanceBetween(
              _pickup!.lat, _pickup!.lng, data['lat'], data['lng']);
              
          debugPrint('[RideProvider] Driver ${doc.id} distance to pickup: $dist meters');
          
          // Strict 5km radius filter
          if (dist <= 5000) {
            debugPrint('[RideProvider] Driver ${doc.id} added to nearby list!');
            drivers.add({
              'id': doc.id,
              'lat': data['lat'],
              'lng': data['lng'],
              'heading': data['heading'] ?? 0.0,
              'vehicleType': data['vehicleType'] ?? 'auto',
              'distance': dist,
            });
          } else {
            debugPrint('[RideProvider] Driver ${doc.id} rejected (too far).');
          }
        } else {
          debugPrint('[RideProvider] Driver ${doc.id} rejected (offline or missing GPS).');
        }
      }
      _nearbyDrivers = drivers;
      debugPrint('[RideProvider] Final nearby drivers count: ${_nearbyDrivers.length}');
      notifyListeners();
    }, onError: (error) {
      debugPrint('[RideProvider] Error fetching nearby drivers: $error');
    });

    // Update ETA every 10 seconds based on live driver coordinates
    _etaUpdateTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_nearbyDrivers.isNotEmpty) {
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _profileSubscription?.cancel();
    _driversSubscription?.cancel();
    _etaUpdateTimer?.cancel();
    super.dispose();
  }
}
