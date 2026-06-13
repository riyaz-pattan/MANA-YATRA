// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'config/firebase_config.dart';
import 'core/theme/app_theme.dart';
import 'core/providers/auth_provider.dart';
import 'core/router/app_router.dart';
import 'core/services/admin_notification_service.dart';

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Initialize Firebase
  await Firebase.initializeApp(options: FirebaseConfig.firebaseOptions);

  // Remove splash immediately — UI is ready to render
  FlutterNativeSplash.remove();

  runApp(const ProviderScope(child: ManaYatraAdminApp()));
}

class ManaYatraAdminApp extends ConsumerWidget {
  const ManaYatraAdminApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'Gaman Admin Console',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) {
        AdminNotificationService().initialize(context);
        return child!;
      },
    );
  }
}
