// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'config/firebase_config.dart';
import 'config/theme.dart';
import 'providers/ride_provider.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';
import 'screens/profile_setup_screen.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'utils/custom_toast.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: FirebaseConfig.firebaseOptions);
}

final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await Firebase.initializeApp(options: FirebaseConfig.firebaseOptions);
  
  // Base initialization (will request permissions if needed via PermissionHandler later)
  FirebaseMessaging messaging = FirebaseMessaging.instance;
  await messaging.requestPermission();

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    if (message.notification != null) {
      final type = message.data['type'];
      
      // If the user is actively using the app, don't spam them with ride status popups
      // because the UI will already be updating instantly via Firestore listeners.
      if (type == 'ride_status') {
        return;
      }

      final ctx = navigatorKey.currentContext;
      if (ctx != null) {
        CustomToast.show(
          context: ctx,
          message: '${message.notification?.title ?? ''}\n${message.notification?.body ?? ''}',
        );
      }
    }
  });

  runApp(const ManaYatraRiderApp());
}

class ManaYatraRiderApp extends StatelessWidget {
  const ManaYatraRiderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => RideProvider(),
      child: MaterialApp(
        scaffoldMessengerKey: rootScaffoldMessengerKey,
        navigatorKey: navigatorKey,
        title: 'Mana Yatra - Rider',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const AuthGate(),
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    _requestNotificationPermission();
  }

  Future<void> _requestNotificationPermission() async {
    final status = await Permission.notification.status;
    if (status.isDenied) {
      await Permission.notification.request();
    }
  }

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
          // Set user in provider
          WidgetsBinding.instance.addPostFrameCallback((_) {
            context.read<RideProvider>().setUser(user);
          });
          
          // Check if user has set their name
          return _NameCheckGate(user: user);
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
        final hasName = data != null &&
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

