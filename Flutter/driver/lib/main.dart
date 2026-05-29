// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'config/firebase_config.dart';
import 'package:google_fonts/google_fonts.dart';
import 'config/theme.dart';
import 'providers/driver_provider.dart';
import 'providers/connectivity_provider.dart';

import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/pending_screen.dart';
import 'screens/rejected_screen.dart';
import 'screens/account_deletion_pending_screen.dart';

import 'screens/dashboard_screen.dart';
import 'screens/active_ride_screen.dart';
import 'screens/subscription_screen.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'utils/custom_toast.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'services/action_queue_service.dart';
import 'services/sync_engine.dart';
import 'services/error_handler.dart';
import 'repositories/ride_repository.dart';
import 'repositories/auth_repository.dart';
import 'services/analytics_service.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:upgrader/upgrader.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: FirebaseConfig.firebaseOptions);
  // For 'new_ride' data messages: the app is woken up.
  // The RTDB listener (RideSignalService) will handle ride discovery
  // once the app comes to foreground. No heavy work needed here.
  if (message.data['type'] == 'new_ride') {
    // App woken from background/killed — RTDB listener will sync on resume.
    return;
  }
}

final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Global SyncEngine instance — accessible to all screens via Provider
late final ActionQueueService actionQueueService;
late final SyncEngine syncEngine;
late final FirestoreRideRepository rideRepository;
late final FirebaseAuthRepository authRepository;
late final AnalyticsService analyticsService;

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Only await the bare essentials — dotenv + Firebase Auth need to be ready
  await dotenv.load(fileName: ".env");
  await Firebase.initializeApp(options: FirebaseConfig.firebaseOptions);

  await FirebaseAppCheck.instance.activate(
    androidProvider: kDebugMode
        ? AndroidProvider.debug
        : AndroidProvider.playIntegrity,
  );

  // Initialize Crashlytics and Global Error Handling
  await ErrorHandler.initialize();

  // Initialize Hive for persistent action queue
  await Hive.initFlutter();
  actionQueueService = ActionQueueService();
  await actionQueueService.init();
  syncEngine = SyncEngine(actionQueueService);
  syncEngine.start();

  rideRepository = FirestoreRideRepository(syncEngine: syncEngine);
  authRepository = FirebaseAuthRepository();
  analyticsService = AnalyticsService();

  // Remove splash immediately — UI is ready to render
  FlutterNativeSplash.remove();
  runApp(const ManaYatraDriverApp());

  // Initialize FCM in the background (non-blocking)
  _initFCM();
}

/// Sets up Firebase Cloud Messaging listeners.
/// Called after runApp so the splash screen doesn't wait for FCM handshake.
void _initFCM() {
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Handle messages when the app is in foreground
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    final type = message.data['type'];

    // New ride notification — RTDB listener handles this in foreground
    if (type == 'new_ride') {
      return;
    }

    if (type == 'ride_status') {
      return;
    }

    // Regular notification messages (e.g., admin broadcasts, driver approval)
    if (message.notification != null) {
      final ctx = navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        CustomToast.show(
          context: ctx,
          message:
              '${message.notification?.title ?? ''}\n${message.notification?.body ?? ''}',
        );
      }
    }
  });

  // Handle clicks on notifications when app is in background
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    final type = message.data['type'];
    if (type == 'subscription_alert') {
      final ctx = navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        Navigator.push(ctx, MaterialPageRoute(builder: (_) => const SubscriptionScreen()));
      }
    }
  });
}

class ManaYatraDriverApp extends StatelessWidget {
  const ManaYatraDriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DriverProvider()),
        ChangeNotifierProvider(create: (_) => ConnectivityProvider()),
        ChangeNotifierProvider.value(value: syncEngine),
        Provider<RideRepository>.value(value: rideRepository),
        Provider<AuthRepository>.value(value: authRepository),
      ],
      child: MaterialApp(
        scaffoldMessengerKey: rootScaffoldMessengerKey,
        navigatorKey: navigatorKey,
        title: 'Gaman - Driver',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: UpgradeAlert(
          showIgnore: true,
          showLater: true,
          upgrader: Upgrader(),
          child: const AuthGate(),
        ),
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            ),
          );
        }

        if (authSnap.data == null) {
          return const LoginScreen();
        }

        final user = authSnap.data!;

        // FCM Topics
        FirebaseMessaging.instance.subscribeToTopic('drivers');
        FirebaseMessaging.instance.subscribeToTopic('driver_${user.uid}');

        // Set user in provider (this kicks off the profile listener in DriverProvider)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final provider = context.read<DriverProvider>();
          if (provider.user?.uid != user.uid) {
            provider.setUser(user);
            provider.loadPersistedState();
          }
        });

        // Use Consumer to react to DriverProvider state changes
        return Consumer<DriverProvider>(
          builder: (context, provider, _) {
            // Wait for initial profile load
            if (provider.user == null ||
                provider.authLoading ||
                provider.profileLoading) {
              return const Scaffold(
                body: Center(
                  child: CircularProgressIndicator(color: AppTheme.primary),
                ),
              );
            }

            // Handle Profile states from Provider
            if (!provider.hasProfile) {
              return const OnboardingScreen();
            }

            if (provider.isBlocked) {
              return _buildBlockedScreen();
            }

            // Rejected — show reason and allow resubmission
            final isRejected = provider.profile?['isRejected'];
            if (isRejected == true || isRejected == 'true') {
              final reason =
                  provider.profile?['rejectionReason'] as String? ??
                  'Your documents did not meet our requirements.';
              return RejectedScreen(rejectionReason: reason);
            }

            if (!provider.isApproved) {
              return const PendingScreen();
            }

            // NOTE: Subscription check removed — drivers can access dashboard
            // even with expired subscription. They'll be kept offline and prompted
            // to renew when trying to go online.

            // All clear — check for persisted active ride first
            return Consumer<DriverProvider>(
              builder: (context, dp, _) {
                if (dp.persistedRideId != null) {
                  return ActiveRideScreen(rideId: dp.persistedRideId!);
                }
                return const DashboardScreen();
              },
            );
          },
        );
      },
    );
  }

  Widget _buildBlockedScreen() {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🚫', style: TextStyle(fontSize: 60)),
              const SizedBox(height: 24),
              Text(
                'Account Blocked',
                style: GoogleFonts.inter(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Your account has been blocked. Contact support.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  color: AppTheme.text2,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => FirebaseAuth.instance.signOut(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: AppTheme.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Logout',
                    style: GoogleFonts.inter(
                      color: AppTheme.text2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
