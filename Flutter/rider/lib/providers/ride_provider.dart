// lib/providers/ride_provider.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../services/google_maps_service.dart';

class RideProvider extends ChangeNotifier {
  // Auth state: null = loading, User object or 'logged_out' sentinel
  User? _user;
  bool _authLoading = true;

  // Location
  LocationResult? _pickup;
  LocationResult? _drop;
  RouteInfo? _route;

  // Ride config
  String _vehicleType = 'auto';
  int _bidPrice = 80;

  // Active ride
  Map<String, dynamic>? _activeRide;
  Map<String, dynamic>? _selectedBid;

  // Getters
  User? get user => _user;
  bool get authLoading => _authLoading;
  bool get isLoggedIn => _user != null && !_authLoading;
  LocationResult? get pickup => _pickup;
  LocationResult? get drop => _drop;
  RouteInfo? get route => _route;
  String get vehicleType => _vehicleType;
  int get bidPrice => _bidPrice;
  Map<String, dynamic>? get activeRide => _activeRide;
  Map<String, dynamic>? get selectedBid => _selectedBid;

  // Setters
  void setUser(User? user) {
    _user = user;
    _authLoading = false;
    if (user != null) {
      // Subscribe to relevant FCM topics for the user
      FirebaseMessaging.instance.subscribeToTopic('all_riders');
      FirebaseMessaging.instance.subscribeToTopic('riders');
      FirebaseMessaging.instance.subscribeToTopic('rider_${user.uid}');
    }
    notifyListeners();
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

  void setActiveRide(Map<String, dynamic>? ride) {
    _activeRide = ride;
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
    notifyListeners();
  }
}
