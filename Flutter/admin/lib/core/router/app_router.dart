// lib/core/router/app_router.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../providers/auth_provider.dart';
import '../../presentation/layouts/admin_shell.dart';
import '../../presentation/screens/dashboard_screen.dart';
import '../../presentation/screens/drivers_screen.dart';
import '../../presentation/screens/users_screen.dart';
import '../../presentation/screens/rides_screen.dart';
import '../../presentation/screens/financials_hub_screen.dart';
import '../../presentation/screens/operations_hub_screen.dart';
import '../../presentation/screens/support_hub_screen.dart';
import '../../presentation/screens/system_hub_screen.dart';
import '../../presentation/screens/login_screen.dart';
import '../../presentation/screens/driver_profile_screen.dart';
import '../../presentation/screens/rider_profile_screen.dart';

// Create a GlobalKey for the root navigator
final rootNavigatorKey = GlobalKey<NavigatorState>();
final shellNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(firebaseAuthProvider);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    redirect: (context, state) {
      final isAuth = authState.valueOrNull != null;
      final isLoggingIn = state.uri.path == '/login';

      if (!isAuth && !isLoggingIn) return '/login';
      if (isAuth && isLoggingIn) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const AdminLoginScreen(),
      ),
      ShellRoute(
        navigatorKey: shellNavigatorKey,
        builder: (context, state, child) {
          // Calculate the selected index based on the current location
          final location = state.uri.path;
          int selectedIndex = 0;
          if (location.startsWith('/drivers')) selectedIndex = 1;
          else if (location.startsWith('/riders')) selectedIndex = 2;
          else if (location.startsWith('/rides')) selectedIndex = 3;
          else if (location.startsWith('/financials')) selectedIndex = 4;
          else if (location.startsWith('/operations')) selectedIndex = 5;
          else if (location.startsWith('/support')) selectedIndex = 6;
          else if (location.startsWith('/system')) selectedIndex = 7;

          return AdminShell(
            selectedIndex: selectedIndex,
            onDestinationSelected: (index) {
              final route = allNavItems[index].routeKey;
              context.go('/$route');
            },
            child: child,
          );
        },
        routes: [
          GoRoute(
            path: '/',
            redirect: (_, __) => '/dashboard',
          ),
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/drivers',
            builder: (context, state) => const DriversScreen(),
          ),
          GoRoute(
            path: '/driver/:id',
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return DriverProfileScreen(driverId: id);
            },
          ),
          GoRoute(
            path: '/riders',
            builder: (context, state) => const UsersScreen(),
          ),
          GoRoute(
            path: '/rider/:id',
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return RiderProfileScreen(riderId: id);
            },
          ),
          GoRoute(
            path: '/rides',
            builder: (context, state) => const RidesScreen(),
          ),
          GoRoute(
            path: '/financials',
            builder: (context, state) => const FinancialsHubScreen(),
          ),
          GoRoute(
            path: '/operations',
            builder: (context, state) => const OperationsHubScreen(),
          ),
          GoRoute(
            path: '/support',
            builder: (context, state) => const SupportHubScreen(),
          ),

          GoRoute(
            path: '/system',
            builder: (context, state) => const SystemHubScreen(),
          ),
        ],
      ),
    ],
  );
});
