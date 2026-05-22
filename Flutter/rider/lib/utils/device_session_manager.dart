import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class DeviceSessionManager {
  static const String _kDeviceIdKey = 'device_session_id';

  /// Retrieves the unique device ID for this installation.
  /// If it doesn't exist, it generates a new UUID and saves it.
  static Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString(_kDeviceIdKey);
    
    if (deviceId == null) {
      deviceId = const Uuid().v4();
      await prefs.setString(_kDeviceIdKey, deviceId);
    }
    
    return deviceId;
  }
}
