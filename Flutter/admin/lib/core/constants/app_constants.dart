// lib/core/constants/app_constants.dart

/// Central configuration constants for Gaman Admin Console.
class AppConstants {
  AppConstants._();

  static const String appName = 'Gaman Admin';
  static const String appVersion = '2.0.0';

  // Firebase Cloud Functions base URL
  static const String functionsBaseUrl =
      'https://us-central1-mana-yatra.cloudfunctions.net';

  // Pagination defaults
  static const int defaultPageSize = 20;
  static const int maxPageSize = 100;

  // Date/time formats
  static const String dateFormat = 'dd MMM yyyy';
  static const String dateTimeFormat = 'dd MMM yyyy, hh:mm a';
  static const String timeFormat = 'hh:mm a';
}
