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

  static const String supportNumber = '+918000000000';
}
