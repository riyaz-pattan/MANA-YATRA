// lib/services/pricing_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pricing configuration for a single vehicle type (auto or bike).
/// Supports 3-tier distance-based pricing with dynamic base fare.
class VehiclePricingConfig {
  final double minFare;
  final double baseFareShort;   // distance ≤ tier1Cap
  final double baseFareMedium;  // tier1Cap < distance ≤ tier1Cap + tier2Cap
  final double baseFareLong;    // distance > tier1Cap + tier2Cap
  final double tier1Rate;       // per-km rate for 0 to tier1Cap km
  final double tier1Cap;        // km boundary for tier 1
  final double tier2Rate;       // per-km rate for tier1Cap to tier1Cap+tier2Cap km
  final double tier2Cap;        // km width of tier 2
  final double tier3Rate;       // per-km rate for everything beyond tier 2

  const VehiclePricingConfig({
    required this.minFare,
    required this.baseFareShort,
    required this.baseFareMedium,
    required this.baseFareLong,
    required this.tier1Rate,
    required this.tier1Cap,
    required this.tier2Rate,
    required this.tier2Cap,
    required this.tier3Rate,
  });

  /// Calculate the fare for a given distance.
  double calculate(double distanceKm) {
    // Dynamic base fare based on total distance
    double baseFare;
    if (distanceKm <= tier1Cap) {
      baseFare = baseFareShort;
    } else if (distanceKm <= tier1Cap + tier2Cap) {
      baseFare = baseFareMedium;
    } else {
      baseFare = baseFareLong;
    }

    double fare = baseFare;
    double remaining = distanceKm;

    // Tier 1: first tier1Cap km
    final t1 = remaining.clamp(0.0, tier1Cap);
    fare += tier1Rate * t1;
    remaining -= t1;

    // Tier 2: next tier2Cap km
    final t2 = remaining.clamp(0.0, tier2Cap);
    fare += tier2Rate * t2;
    remaining -= t2;

    // Tier 3: everything beyond
    if (remaining > 0) {
      fare += tier3Rate * remaining;
    }

    return fare < minFare ? minFare : fare.roundToDouble();
  }

  /// Returns a (low, high) fare estimate range with distance-adaptive bands.
  /// Short rides get tighter bands (±10%), long rides get wider bands.
  (int low, int high) estimateRange(double distanceKm) {
    final mid = calculate(distanceKm);
    double lowMult, highMult;

    if (distanceKm <= 3) {
      lowMult = 0.90;
      highMult = 1.10;
    } else if (distanceKm <= 8) {
      lowMult = 0.88;
      highMult = 1.15;
    } else if (distanceKm <= 15) {
      lowMult = 0.85;
      highMult = 1.18;
    } else {
      lowMult = 0.82;
      highMult = 1.20;
    }

    return ((mid * lowMult).round(), (mid * highMult).round());
  }

  /// Create from a Firestore map (e.g., the 'auto' or 'bike' sub-document).
  factory VehiclePricingConfig.fromMap(Map<String, dynamic> map) {
    return VehiclePricingConfig(
      minFare: (map['minFare'] as num?)?.toDouble() ?? 25,
      baseFareShort: (map['baseFareShort'] as num?)?.toDouble() ?? 20,
      baseFareMedium: (map['baseFareMedium'] as num?)?.toDouble() ?? 25,
      baseFareLong: (map['baseFareLong'] as num?)?.toDouble() ?? 30,
      tier1Rate: (map['tier1Rate'] as num?)?.toDouble() ?? 10,
      tier1Cap: (map['tier1Cap'] as num?)?.toDouble() ?? 3,
      tier2Rate: (map['tier2Rate'] as num?)?.toDouble() ?? 13,
      tier2Cap: (map['tier2Cap'] as num?)?.toDouble() ?? 5,
      tier3Rate: (map['tier3Rate'] as num?)?.toDouble() ?? 11,
    );
  }

  Map<String, dynamic> toMap() => {
        'minFare': minFare,
        'baseFareShort': baseFareShort,
        'baseFareMedium': baseFareMedium,
        'baseFareLong': baseFareLong,
        'tier1Rate': tier1Rate,
        'tier1Cap': tier1Cap,
        'tier2Rate': tier2Rate,
        'tier2Cap': tier2Cap,
        'tier3Rate': tier3Rate,
      };
}

/// Hardcoded fallback defaults — used when Firestore is unavailable.
const _defaultAutoConfig = VehiclePricingConfig(
  minFare: 25,
  baseFareShort: 20,
  baseFareMedium: 25,
  baseFareLong: 30,
  tier1Rate: 10,
  tier1Cap: 3,
  tier2Rate: 13,
  tier2Cap: 5,
  tier3Rate: 11,
);

const _defaultBikeConfig = VehiclePricingConfig(
  minFare: 18,
  baseFareShort: 15,
  baseFareMedium: 18,
  baseFareLong: 22,
  tier1Rate: 7,
  tier1Cap: 3,
  tier2Rate: 9,
  tier2Cap: 5,
  tier3Rate: 8,
);

/// Service that syncs pricing configuration from Firestore in real-time.
/// Falls back to cached (SharedPreferences) or hardcoded defaults.
class PricingService extends ChangeNotifier {
  static const _cacheKey = 'cached_pricing_config';

  Map<String, VehiclePricingConfig> _configs = {
    'auto': _defaultAutoConfig,
    'bike': _defaultBikeConfig,
  };

  StreamSubscription<DocumentSnapshot>? _sub;
  bool _initialized = false;

  bool get isInitialized => _initialized;

  /// Get pricing config for a vehicle type ('auto' or 'bike').
  VehiclePricingConfig getConfig(String vehicleType) {
    return _configs[vehicleType] ?? _defaultAutoConfig;
  }

  /// Calculate estimated fare for a ride.
  double estimatePrice(double distanceKm, String vehicleType) {
    return getConfig(vehicleType).calculate(distanceKm);
  }

  /// Get fare estimate range (low, high).
  (int low, int high) estimatePriceRange(double distanceKm, String vehicleType) {
    return getConfig(vehicleType).estimateRange(distanceKm);
  }

  /// Get minimum fare for a vehicle type.
  double getMinFare(String vehicleType) {
    return getConfig(vehicleType).minFare;
  }

  /// Initialize the service: load cache, then start Firestore listener.
  Future<void> init() async {
    await _loadFromCache();
    _startFirestoreListener();
    _initialized = true;
  }

  /// Load pricing from SharedPreferences cache (offline-first).
  Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_cacheKey);
      if (cached != null) {
        final data = jsonDecode(cached) as Map<String, dynamic>;
        _applyConfig(data);
        debugPrint('[PricingService] Loaded pricing from cache.');
      }
    } catch (e) {
      debugPrint('[PricingService] Cache load error: $e');
    }
  }

  /// Start real-time Firestore listener on config/pricing.
  void _startFirestoreListener() {
    _sub?.cancel();
    _sub = FirebaseFirestore.instance
        .collection('config')
        .doc('pricing')
        .snapshots()
        .listen(
      (snap) {
        if (snap.exists && snap.data() != null) {
          final data = snap.data()!;
          _applyConfig(data);
          _saveToCache(data);
          debugPrint('[PricingService] Pricing updated from Firestore.');
          notifyListeners();
        }
      },
      onError: (error) {
        debugPrint('[PricingService] Firestore listener error: $error');
      },
    );
  }

  /// Apply config data from Firestore or cache.
  void _applyConfig(Map<String, dynamic> data) {
    if (data['auto'] != null && data['auto'] is Map) {
      _configs['auto'] = VehiclePricingConfig.fromMap(
        Map<String, dynamic>.from(data['auto'] as Map),
      );
    }
    if (data['bike'] != null && data['bike'] is Map) {
      _configs['bike'] = VehiclePricingConfig.fromMap(
        Map<String, dynamic>.from(data['bike'] as Map),
      );
    }
  }

  /// Persist the latest config to SharedPreferences for offline use.
  Future<void> _saveToCache(Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Only cache the pricing fields, not Timestamps
      final cacheData = <String, dynamic>{};
      if (data['auto'] != null) {
        cacheData['auto'] = Map<String, dynamic>.from(data['auto'] as Map);
      }
      if (data['bike'] != null) {
        cacheData['bike'] = Map<String, dynamic>.from(data['bike'] as Map);
      }
      await prefs.setString(_cacheKey, jsonEncode(cacheData));
    } catch (e) {
      debugPrint('[PricingService] Cache save error: $e');
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
