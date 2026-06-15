// lib/services/region_service.dart
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';

class RegionService {
  static final RegionService _instance = RegionService._internal();
  factory RegionService() => _instance;
  RegionService._internal();

  List<Map<String, dynamic>> _serviceableAreas = [];
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final remoteConfig = FirebaseRemoteConfig.instance;
      await remoteConfig.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(minutes: 1),
        minimumFetchInterval: const Duration(minutes: 15),
      ));
      
      await remoteConfig.setDefaults(const {
        "serviceable_areas": "[]"
      });

      await remoteConfig.fetchAndActivate();
      
      final String areasJson = remoteConfig.getString('serviceable_areas');
      if (areasJson.isNotEmpty) {
        final List<dynamic> parsedList = json.decode(areasJson);
        _serviceableAreas = parsedList.map((e) => e as Map<String, dynamic>).toList();
      }
      _initialized = true;
    } catch (e) {
      debugPrint("Error initializing RegionService: $e");
    }
  }

  /// Returns true if the given lat, lng is within ANY of the active regions' radius.
  /// If the 'serviceable_areas' remote config is empty or invalid, it returns true by default to avoid breaking the app.
  bool isLocationServiceable(double lat, double lng) {
    if (_serviceableAreas.isEmpty) return true; // Allow all if not configured yet

    for (var area in _serviceableAreas) {
      final double centerLat = (area['lat'] as num).toDouble();
      final double centerLng = (area['lng'] as num).toDouble();
      final double radiusKm = (area['radiusKm'] as num).toDouble();
      
      final double distanceMeters = Geolocator.distanceBetween(lat, lng, centerLat, centerLng);
      final double distanceKm = distanceMeters / 1000.0;
      
      if (distanceKm <= radiusKm) {
        return true; 
      }
    }
    
    return false;
  }

  /// Saves the user's details to the waitlist in RTDB
  Future<void> addToWaitlist({
    required double lat,
    required double lng,
    required String type, // 'rider' or 'driver'
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final phone = user?.phoneNumber ?? 'Unknown';
    final uid = user?.uid ?? 'Unknown';

    try {
      final dbRef = FirebaseDatabase.instance.ref('waitlist').push();
      await dbRef.set({
        'uid': uid,
        'phone': phone,
        'lat': lat,
        'lng': lng,
        'type': type,
        'timestamp': ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint("Error adding to waitlist: $e");
    }
  }
}
