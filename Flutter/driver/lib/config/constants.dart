// lib/config/constants.dart

class VehicleInfo {
  final String label;
  final String icon;
  final int seats;
  const VehicleInfo({required this.label, required this.icon, required this.seats});
}

class AppConstants {
  static const Map<String, VehicleInfo> vehicleTypes = {
    'auto': VehicleInfo(label: 'Auto', icon: '🛺', seats: 3),
    'bike': VehicleInfo(label: 'Bike', icon: '🏍️', seats: 1),
  };

  static const int rideExpiryMinutes = 5;
  static const int subscriptionDailyRate = 15;

  // Matching & safety
  static const int maxVisibleRides = 10;
  static const int maxActiveBids = 10;
  static const int heartbeatMaxAgeSec = 120; // 2 minutes

  // Ride search & estimation
  static const double searchRadiusMeters = 5000; // 5 km
  static const double avgSpeedKmh = 25; // for ETA calculation

  // Tracking config
  static const int discoveryIntervalMs = 120000;   // 2 minutes
  static const int discoveryMinDistanceM = 500;     // 500 meters
  static const int activeRideIntervalMs = 5000;     // 5 seconds
  static const int autoOfflineMinutes = 120;          // 2 hours — auto-offline idle drivers

  static const Map<String, double> pricePerKm = {
    'auto': 12,
    'bike': 8,
  };

  static const Map<String, double> baseFare = {
    'auto': 30,
    'bike': 20,
  };
}
