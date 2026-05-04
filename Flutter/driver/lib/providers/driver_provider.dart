// lib/providers/driver_provider.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/smart_tracker.dart';

class DriverProvider extends ChangeNotifier {
  User? _user;
  bool _authLoading = true;
  Map<String, dynamic>? _profile;
  bool _isOnline = false;
  SmartTracker? _tracker;
  double? _lat;
  double? _lng;
  Map<String, dynamic>? _activeRide;

  // Getters
  User? get user => _user;
  bool get authLoading => _authLoading;
  bool get isLoggedIn => _user != null && !_authLoading;
  Map<String, dynamic>? get profile => _profile;
  bool get isOnline => _isOnline;
  double? get lat => _lat;
  double? get lng => _lng;
  Map<String, dynamic>? get activeRide => _activeRide;
  SmartTracker? get tracker => _tracker;

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
    if (user != null && _tracker == null) {
      _tracker = SmartTracker(user.uid);
      _tracker!.onLocationUpdate = (lat, lng) {
        _lat = lat;
        _lng = lng;
        notifyListeners();
      };
    }
    notifyListeners();
  }

  void setProfile(Map<String, dynamic>? profile) {
    _profile = profile;
    if (profile != null) {
      _isOnline = profile['isOnline'] == true;
    }
    notifyListeners();
  }

  void setOnline(bool online) {
    _isOnline = online;
    if (_tracker != null) {
      _tracker!.setMode(
          online ? TrackingMode.discovery : TrackingMode.offline);
    }
    notifyListeners();
  }

  void setActiveRide(Map<String, dynamic>? ride) {
    _activeRide = ride;
    if (_tracker != null) {
      _tracker!.setMode(ride != null
          ? TrackingMode.activeRide
          : (_isOnline ? TrackingMode.discovery : TrackingMode.offline));
    }
    notifyListeners();
  }

  void updateLocation(double lat, double lng) {
    _lat = lat;
    _lng = lng;
    notifyListeners();
  }

  @override
  void dispose() {
    _tracker?.destroy();
    super.dispose();
  }
}
