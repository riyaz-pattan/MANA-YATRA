// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'config/firebase_config.dart';
import 'config/theme.dart';
import 'providers/ride_provider.dart';
import 'providers/connectivity_provider.dart';

import 'screens/login_screen.dart';
import 'screens/main_screen.dart';
import 'screens/profile_setup_screen.dart';
import 'screens/account_deletion_pending_screen.dart';
import 'screens/active_ride_screen.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
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
    androidProvider: AndroidProvider.playIntegrity,
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
  runApp(const ManaYatraRiderApp());

  // Initialize FCM in the background (non-blocking)
  _initFCM();
}

/// Sets up Firebase Cloud Messaging listeners.
/// Called after runApp so the splash screen doesn't wait for FCM handshake.
void _initFCM() {
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    if (message.notification != null) {
      final type = message.data['type'];

      if (type == 'ride_status') {
        return;
      }

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
}

class ManaYatraRiderApp extends StatelessWidget {
  const ManaYatraRiderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => RideProvider()),
        ChangeNotifierProvider(create: (_) => ConnectivityProvider()),
        ChangeNotifierProvider.value(value: syncEngine),
        Provider<RideRepository>.value(value: rideRepository),
        Provider<AuthRepository>.value(value: authRepository),
      ],
      child: MaterialApp(
        scaffoldMessengerKey: rootScaffoldMessengerKey,
        navigatorKey: navigatorKey,
        title: 'Mana Yatra - Rider',
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
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            ),
          );
        }
        if (snapshot.hasData && snapshot.data != null) {
          final user = snapshot.data!;
          // Set user in provider and load any persisted ride state
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              final provider = context.read<RideProvider>();
              provider.setUser(user);
              provider.loadPersistedState();
            }
          });

          // Subscribe to FCM Topics
          FirebaseMessaging.instance.subscribeToTopic('riders');
          FirebaseMessaging.instance.subscribeToTopic('rider_${user.uid}');

          // Check for a persisted active ride (offline startup recovery)
          return Consumer<RideProvider>(
            builder: (context, rideProvider, _) {
              if (rideProvider.persistedRideId != null) {
                return ActiveRideScreen(
                  rideId: rideProvider.persistedRideId!,
                );
              }
              return _NameCheckGate(user: user);
            },
          );
        }
        return const LoginScreen();
      },
    );
  }
}

/// Checks if the user has a name in Firestore; if not, routes to ProfileSetupScreen.
/// StatefulWidget so the future is created once and not re-fired on parent rebuilds.
class _NameCheckGate extends StatefulWidget {
  final User user;
  const _NameCheckGate({required this.user});

  @override
  State<_NameCheckGate> createState() => _NameCheckGateState();
}

class _NameCheckGateState extends State<_NameCheckGate> {
  late Future<DocumentSnapshot> _future;

  @override
  void initState() {
    super.initState();
    _future = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.user.uid)
        .get();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            ),
          );
        }

        // Handle errors gracefully — don't loop to ProfileSetup on network errors
        if (snap.hasError) {
          return const MainScreen();
        }

        final data = snap.data?.data() as Map<String, dynamic>?;
        final hasName =
            data != null &&
            data.containsKey('name') &&
            (data['name']?.toString() ?? '').trim().isNotEmpty;

        if (hasName) {
          return const MainScreen();
        }
        return const ProfileSetupScreen();
      },
    );
  }
}
