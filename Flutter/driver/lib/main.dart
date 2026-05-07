// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'config/firebase_config.dart';
import 'package:google_fonts/google_fonts.dart';
import 'config/theme.dart';
import 'providers/driver_provider.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/pending_screen.dart';
import 'screens/subscription_screen.dart';
import 'screens/dashboard_screen.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'utils/custom_toast.dart';

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

final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await Firebase.initializeApp(options: FirebaseConfig.firebaseOptions);
  
  // Base FCM initialization
  FirebaseMessaging messaging = FirebaseMessaging.instance;
  await messaging.requestPermission();

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Handle messages when the app is in foreground
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    final type = message.data['type'];

    // New ride notification
    // If app is in foreground, RTDB listener will pick it up instantly.
    // We don't need to show a SnackBar or Toast to avoid redundancy.
    if (type == 'new_ride') {
      return;
    }
    
    if (type == 'ride_status') {
      return;
    }

    // Regular notification messages (e.g., admin broadcasts, driver approval)
    if (message.notification != null) {
      final ctx = navigatorKey.currentContext;
      if (ctx != null) {
        CustomToast.show(
          context: ctx,
          message: '${message.notification?.title ?? ''}\n${message.notification?.body ?? ''}',
        );
      }
    }
  });

  runApp(const ManaYatraDriverApp());
}

class ManaYatraDriverApp extends StatelessWidget {
  const ManaYatraDriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => DriverProvider(),
      child: MaterialApp(
        scaffoldMessengerKey: rootScaffoldMessengerKey,
        navigatorKey: navigatorKey,
        title: 'Mana Yatra - Driver',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const AuthGate(),
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

        // Set user in provider
        WidgetsBinding.instance.addPostFrameCallback((_) {
          context.read<DriverProvider>().setUser(user);
        });

        // Listen to driver profile
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('drivers')
              .doc(user.uid)
              .snapshots(),
          builder: (context, profileSnap) {
            if (profileSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(
                  child: CircularProgressIndicator(color: AppTheme.primary),
                ),
              );
            }

            final profileData =
                profileSnap.data?.data() as Map<String, dynamic>?;

            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (profileData != null) {
                // Convert Timestamp to DateTime for subscription
                final processed = Map<String, dynamic>.from(profileData);
                if (processed['subscriptionActiveUntil'] is Timestamp) {
                  processed['subscriptionActiveUntil'] =
                      (processed['subscriptionActiveUntil'] as Timestamp)
                          .toDate();
                }
                context.read<DriverProvider>().setProfile(processed);
              }
            });

            // No profile = show onboarding
            if (!profileSnap.data!.exists || profileData == null) {
              return const OnboardingScreen();
            }

            // Blocked
            final isBlocked = profileData['isBlocked'];
            if (isBlocked == true || isBlocked == 'true') {
              return _buildBlockedScreen();
            }

            // Not approved = pending
            final isApproved = profileData['isApproved'];
            if (isApproved != true && isApproved != 'true') {
              return const PendingScreen();
            }

            // Check subscription
            final subUntil = profileData['subscriptionActiveUntil'];
            DateTime? subDate;
            if (subUntil is Timestamp) {
              subDate = subUntil.toDate();
            } else if (subUntil is DateTime) {
              subDate = subUntil;
            }

            if (subDate == null || subDate.isBefore(DateTime.now())) {
              return const SubscriptionScreen();
            }

            // All clear — show dashboard
            return const DashboardScreen();
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
