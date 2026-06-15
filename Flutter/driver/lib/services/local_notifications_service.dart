import 'dart:ui';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:geolocator/geolocator.dart';

class LocalNotificationsService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static void initialize() {
    // Initialization settings for Android
    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: AndroidInitializationSettings('@drawable/ic_notification'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      ),
    );

    _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Handle notification tapped logic here if needed
      },
    );
  }

  static void display(RemoteMessage message) async {
    try {
      final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Android specific details
      const NotificationDetails notificationDetails = NotificationDetails(
        android: AndroidNotificationDetails(
          'mana_yatra_high_importance',
          'High Importance Notifications',
          channelDescription: 'This channel is used for important broadcast notifications.',
          importance: Importance.max,
          priority: Priority.high,
          icon: '@drawable/ic_notification',
          color: const Color(0xFFFFD700),
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

      await _notificationsPlugin.show(
        id,
        message.notification?.title ?? 'Notification',
        message.notification?.body ?? '',
        notificationDetails,
        payload: message.data.toString(),
      );
    } on Exception catch (e) {
      print('Error displaying local notification: $e');
    }
  }

  static void showRideRequestNotification(Map<String, dynamic> data) async {
    try {
      final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      
      final isExpanded = data['isExpanded'] == 'true';
      final vType = data['vehicleType']?.toString().toUpperCase() ?? 'RIDE';
      final fare = data['fareLabel'] ?? '';
      final dist = data['distLabel'] ?? '';
      final pickupFull = data['pickupFull'] ?? 'Pickup';
      final dropFull = data['dropFull'] ?? 'Drop';
      
      String awayLabel = '';
      if (data['pickupLat'] != null && data['pickupLng'] != null && data['pickupLat'].toString().isNotEmpty) {
        try {
          final pLat = double.parse(data['pickupLat'].toString());
          final pLng = double.parse(data['pickupLng'].toString());
          final position = await Geolocator.getLastKnownPosition();
          if (position != null) {
            final distMeters = Geolocator.distanceBetween(
                position.latitude, position.longitude, pLat, pLng);
            if (distMeters < 1000) {
              awayLabel = '${distMeters.toInt()}m away · ';
            } else {
              awayLabel = '${(distMeters / 1000).toStringAsFixed(1)}km away · ';
            }
          }
        } catch (e) {
          // Ignore
        }
      }

      final String title = isExpanded 
          ? '${awayLabel}$vType ride nearby — $fare'
          : '${awayLabel}New $vType ride — $fare';
          
      final String summaryText = '$pickupFull → $dropFull${dist.isNotEmpty ? " · $dist" : ""}';
      
      final String bigText = '''
📍 Pickup: $pickupFull
🏁 Drop: $dropFull
📏 Distance: $dist
💰 Fare: $fare
''';

      final NotificationDetails notificationDetails = NotificationDetails(
        android: AndroidNotificationDetails(
          'ride_requests',
          'Ride Requests',
          channelDescription: 'Notifications for new ride requests.',
          importance: Importance.max,
          priority: Priority.high,
          icon: '@drawable/ic_notification',
          color: const Color(0xFFFFD700),
          styleInformation: BigTextStyleInformation(
            bigText,
            contentTitle: title,
            summaryText: isExpanded ? 'Expanded Search' : 'New Request',
            htmlFormatBigText: false,
            htmlFormatContentTitle: false,
            htmlFormatSummaryText: false,
          ),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

      await _notificationsPlugin.show(
        id,
        title,
        summaryText,
        notificationDetails,
        payload: data.toString(),
      );
    } catch (e) {
      print('Error showing ride request notification: $e');
    }
  }
}
