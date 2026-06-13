// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'config/firebase_config.dart';
import 'config/theme.dart';
import 'providers/ride_provider.dart';
import 'providers/connectivity_provider.dart';
import 'services/pricing_service.dart';

import 'screens/login_screen.dart';
import 'screens/main_screen.dart';
import 'screens/profile_setup_screen.dart';

import 'screens/active_ride_screen.dart';
import 'screens/matching_screen.dart';
import 'screens/custom_splash_screen.dart';
import 'screens/maintenance_screen.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'utils/custom_toast.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'services/action_queue_service.dart';
import 'services/local_notifications_service.dart';
import 'services/sync_engine.dart';
import 'services/error_handler.dart';
import 'repositories/ride_repository.dart';
import 'repositories/auth_repository.dart';
import 'services/analytics_service.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:in_app_update/in_app_update.dart';
import 'dart:io';
import 'utils/version_utils.dart';
import 'screens/force_update_screen.dart';
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
late final PricingService pricingService;
late final PackageInfo packageInfo;

void main() {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  runApp(const AppInitializer());
}

class AppInitializer extends StatefulWidget {
  const AppInitializer({super.key});

  @override
  State<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer> {
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FlutterNativeSplash.remove();
    });

    await Future.wait([
      Future.delayed(const Duration(milliseconds: 1500)),
      () async {
        await dotenv.load(fileName: ".env");
        await Firebase.initializeApp(options: FirebaseConfig.firebaseOptions);

        final remoteConfig = FirebaseRemoteConfig.instance;
        await remoteConfig.setConfigSettings(RemoteConfigSettings(
          fetchTimeout: const Duration(minutes: 1),
          minimumFetchInterval: const Duration(minutes: 1), // Reduced for testing dynamic ads
        ));
        try {
          await remoteConfig.fetchAndActivate();
        } catch (e) {
          debugPrint('Failed to fetch remote config: $e');
        }

        await FirebaseAppCheck.instance.activate(
          androidProvider: kDebugMode
              ? AndroidProvider.debug
              : AndroidProvider.playIntegrity,
        );

        await ErrorHandler.initialize();

        await Hive.initFlutter();
        actionQueueService = ActionQueueService();
        await actionQueueService.init();
        syncEngine = SyncEngine(actionQueueService);
        syncEngine.start();

        // Initialize pricing service
        pricingService = PricingService();
        await pricingService.init();

        packageInfo = await PackageInfo.fromPlatform();

        rideRepository = FirestoreRideRepository(syncEngine: syncEngine);
        authRepository = FirebaseAuthRepository();
        analyticsService = AnalyticsService();

        _initFCM();
        LocalNotificationsService.initialize();
      }(),
    ]);

    if (mounted) {
      setState(() {
        _initialized = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const CustomSplashScreen(),
      );
    }
    return const ManaYatraRiderApp();
  }
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

      if (type == 'broadcast') {
        LocalNotificationsService.display(message);
      } else {
        final ctx = navigatorKey.currentContext;
        if (ctx != null && ctx.mounted) {
          CustomToast.show(
            context: ctx,
            message:
                '${message.notification?.title ?? ''}\n${message.notification?.body ?? ''}',
          );
        }
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
        ChangeNotifierProvider.value(value: pricingService),
        Provider<RideRepository>.value(value: rideRepository),
        Provider<AuthRepository>.value(value: authRepository),
      ],
      child: StreamBuilder<DatabaseEvent>(
        stream: FirebaseDatabase.instance.ref('config').onValue,
        builder: (context, configSnap) {
          final rawData = configSnap.data?.snapshot.value;
          final rawMap = rawData as Map<dynamic, dynamic>?;
          final isMaintenance = rawMap != null && rawMap['feature_flags']?['maintenance_mode'] == true;

          final appVersionsRaw = rawMap?['app_versions'];
          final appVersions = appVersionsRaw is Map ? appVersionsRaw['rider'] as Map? : null;
          final minVersion = appVersions?['min_required_version']?.toString() ?? '0.0.0';
          final latestVersion = appVersions?['latest_version']?.toString() ?? '0.0.0';
          final currentVersion = packageInfo.version;

          final isForceUpdate = compareVersions(currentVersion, minVersion) < 0;
          final needsFlexibleUpdate = !isForceUpdate && compareVersions(currentVersion, latestVersion) < 0;

          return MaterialApp(
            scaffoldMessengerKey: rootScaffoldMessengerKey,
            navigatorKey: navigatorKey,
            title: 'Gaman - Rider',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.darkTheme,
            builder: (context, child) {
              return Consumer<RideProvider>(
                builder: (context, provider, _) {
                  final hasActiveRide = provider.persistedRideId != null;
                  
                  if (isForceUpdate) {
                    return const ForceUpdateScreen();
                  }

                  // Lock out if maintenance is ON and the user does NOT have an active ride
                  if (isMaintenance && !hasActiveRide) {
                    return const MaintenanceScreen();
                  }
                  return child!;
                },
              );
            },
            home: FlexibleUpdateWrapper(
              needsFlexibleUpdate: needsFlexibleUpdate,
              child: const AuthGate(),
            ),
          );
        }
      ),
    );
  }
}

class FlexibleUpdateWrapper extends StatefulWidget {
  final bool needsFlexibleUpdate;
  final Widget child;
  const FlexibleUpdateWrapper({super.key, required this.needsFlexibleUpdate, required this.child});

  @override
  State<FlexibleUpdateWrapper> createState() => _FlexibleUpdateWrapperState();
}

class _FlexibleUpdateWrapperState extends State<FlexibleUpdateWrapper> {
  bool _updateTriggered = false;

  @override
  void didUpdateWidget(FlexibleUpdateWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    _checkUpdate();
  }

  @override
  void initState() {
    super.initState();
    _checkUpdate();
  }

  void _checkUpdate() {
    if (widget.needsFlexibleUpdate && !_updateTriggered && Platform.isAndroid) {
      _updateTriggered = true;
      _triggerInAppUpdate();
    }
  }

  Future<void> _triggerInAppUpdate() async {
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability == UpdateAvailability.updateAvailable) {
        await InAppUpdate.startFlexibleUpdate();
        await InAppUpdate.completeFlexibleUpdate();
      }
    } catch (e) {
      debugPrint("InAppUpdate Error: \$e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
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
          return const CustomSplashScreen();
        }
        if (!snapshot.hasData || snapshot.data == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (context.mounted) {
              final provider = context.read<RideProvider>();
              if (provider.user != null) {
                provider.setUser(null);
                // The rider just logged out! Delete the FCM token so this
                // device stops receiving notifications for the old account.
                try {
                  await FirebaseMessaging.instance.deleteToken();
                } catch (e) {
                  debugPrint('Error deleting FCM token on logout: $e');
                }
              }
            }
          });
          return const LoginScreen();
        }

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

          // Save FCM token to Firestore for targeted notifications
          FirebaseMessaging.instance.getToken().then((token) {
            if (token != null) {
              FirebaseFirestore.instance.collection('users').doc(user.uid).set(
                {'fcmToken': token},
                SetOptions(merge: true),
              );
            }
          });
          // Listen for token refreshes
          FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
            FirebaseFirestore.instance.collection('users').doc(user.uid).set(
              {'fcmToken': newToken},
              SetOptions(merge: true),
            );
          });

          // Check for a persisted active ride (offline startup recovery)
          return StreamProvider<DocumentSnapshot?>.value(
            value: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
            initialData: null,
            child: Selector<RideProvider, RideProvider>(
              selector: (context, provider) => provider,
              builder: (context, provider, _) {
                final persistedRideId = provider.persistedRideId;
                final status = provider.persistedRideStatus;
                
                if (persistedRideId != null) {
                  if (status == 'searching' || status == 'bidding') {
                    return MatchingScreen(rideId: persistedRideId);
                  } else {
                    return ActiveRideScreen(rideId: persistedRideId);
                  }
                }
                return _NameCheckGate(user: user);
              },
            ),
          );
      },
    );
  }
}

class _NameCheckGate extends StatelessWidget {
  final User user;
  const _NameCheckGate({required this.user});

  @override
  Widget build(BuildContext context) {
    final doc = Provider.of<DocumentSnapshot?>(context);

    if (doc == null) {
      return const CustomSplashScreen();
    }

    final data = doc.data() as Map<String, dynamic>?;
    final hasName =
        data != null &&
        data.containsKey('name') &&
        (data['name']?.toString() ?? '').trim().isNotEmpty;

    // If we have data, but it's from cache AND we don't have a name yet,
    // it might be because the server hasn't sent the real document yet.
    // So we show loading until we hear from the server to prevent a flash.
    if (doc.metadata.isFromCache && !hasName) {
      return const CustomSplashScreen();
    }

    if (hasName) {
      return MainScreen(key: mainScreenKey);
    }
    return const ProfileSetupScreen();
  }
}
