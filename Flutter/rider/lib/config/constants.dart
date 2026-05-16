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

  static const Map<String, double> pricePerKm = {
    'auto': 12,
    'bike': 8,
  };

  static const Map<String, double> baseFare = {
    'auto': 30,
    'bike': 20,
  };

  static double estimatePrice(double distanceKm, String vehicleType) {
    final base = baseFare[vehicleType] ?? 30;
    final perKm = pricePerKm[vehicleType] ?? 12;
    return (base + perKm * distanceKm).roundToDouble();
  }

  /// Returns a (low, high) fare estimate range with ±15% band.
  static (int low, int high) estimatePriceRange(
      double distanceKm, String vehicleType) {
    final mid = estimatePrice(distanceKm, vehicleType);
    return ((mid * 0.85).round(), (mid * 1.15).round());
  }

  /// Minimum acceptable bid per vehicle type (below this → warn rider).
  static const Map<String, int> minFare = {
    'auto': 30,
    'bike': 20,
  };

  static const String supportNumber = '+918000000000';
}
