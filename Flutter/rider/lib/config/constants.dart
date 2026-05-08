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
}
