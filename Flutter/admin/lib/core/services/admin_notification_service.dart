import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

class AdminNotificationService {
  static final AdminNotificationService _instance = AdminNotificationService._internal();
  factory AdminNotificationService() => _instance;
  AdminNotificationService._internal();

  StreamSubscription<RemoteMessage>? _messageSubscription;
  OverlayEntry? _currentOverlay;

  Future<void> initialize(BuildContext context) async {
    final messaging = FirebaseMessaging.instance;
    
    // Request permission
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      criticalAlert: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized || 
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      
      // Subscribe to SOS alerts topic
      await messaging.subscribeToTopic('admin_sos_alerts');
      debugPrint('Subscribed to admin_sos_alerts topic');

      // Listen to foreground messages
      _messageSubscription?.cancel();
      _messageSubscription = FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        if (message.data['type'] == 'sos_alert') {
          _showSOSOverlay(context, message.notification?.title ?? 'SOS ALERT', message.notification?.body ?? 'A new SOS alert was activated.');
        } else {
          // General foreground notification handler
          if (message.notification != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(message.notification!.title ?? 'New Notification'),
                backgroundColor: AppTheme.brandBlue,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      });
    }
  }

  void _showSOSOverlay(BuildContext context, String title, String body) {
    _currentOverlay?.remove();
    _currentOverlay = null;

    final overlayState = Overlay.of(context);
    
    _currentOverlay = OverlayEntry(
      builder: (context) {
        return Positioned(
          top: MediaQuery.of(context).padding.top + 16,
          left: 16,
          right: 16,
          child: Material(
            color: Colors.transparent,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: -100.0, end: 0.0),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutBack,
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(0, value),
                  child: child,
                );
              },
              child: Dismissible(
                key: UniqueKey(),
                direction: DismissDirection.up,
                onDismissed: (_) {
                  _currentOverlay?.remove();
                  _currentOverlay = null;
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.danger,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          _currentOverlay?.remove();
                          _currentOverlay = null;
                          // Optional: Navigate to SOS alerts tab/screen
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 28),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      title,
                                      style: GoogleFonts.inter(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      body,
                                      style: GoogleFonts.inter(
                                        color: Colors.white.withValues(alpha: 0.9),
                                        fontSize: 14,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, color: Colors.white),
                                onPressed: () {
                                  _currentOverlay?.remove();
                                  _currentOverlay = null;
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlayState.insert(_currentOverlay!);

    // Auto dismiss after 10 seconds
    Future.delayed(const Duration(seconds: 10), () {
      if (_currentOverlay != null) {
        _currentOverlay?.remove();
        _currentOverlay = null;
      }
    });
  }

  void dispose() {
    _messageSubscription?.cancel();
    _currentOverlay?.remove();
  }
}
