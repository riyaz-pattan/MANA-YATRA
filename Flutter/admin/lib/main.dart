// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_fonts/google_fonts.dart';
import 'config/firebase_config.dart';
import 'config/theme.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'screens/login_screen.dart';
import 'screens/drivers_screen.dart';
import 'screens/users_screen.dart';
import 'screens/rides_screen.dart';
import 'screens/analytics_screen.dart';
import 'screens/earnings_report_screen.dart';
import 'screens/document_management_screen.dart';
import 'screens/notification_settings_screen.dart';
import 'screens/account_handling_screen.dart';

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  
  // Only await the bare essential — Firebase Auth needs to be ready
  await Firebase.initializeApp(options: FirebaseConfig.firebaseOptions);
  
  // Remove splash immediately — UI is ready to render
  FlutterNativeSplash.remove();
  runApp(const ManaYatraAdminApp());

  // Initialize FCM in the background (non-blocking)
  _initFCM();
}

/// Sets up Firebase Cloud Messaging — permission + topic subscription.
/// Called after runApp so the splash screen doesn't wait for network calls.
Future<void> _initFCM() async {
  final messaging = FirebaseMessaging.instance;
  await messaging.requestPermission();
  await messaging.subscribeToTopic('admins');
}

class ManaYatraAdminApp extends StatelessWidget {
  const ManaYatraAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mana Yatra - Admin',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            ),
          );
        }
        if (snap.data == null) return const AdminLoginScreen();
        return const AdminShell();
      },
    );
  }
}

// ── Navigation Items ──
class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final Widget screen;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.screen,
  });
}

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});
  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _selectedIndex = 0;

  // Bottom nav shows only the 4 primary screens
  static const _bottomNavScreens = <_NavItem>[
    _NavItem(
      icon: Icons.dashboard_outlined,
      activeIcon: Icons.dashboard,
      label: 'Dashboard',
      screen: AnalyticsScreen(),
    ),
    _NavItem(
      icon: Icons.people_outline,
      activeIcon: Icons.people,
      label: 'Drivers',
      screen: DriversScreen(),
    ),
    _NavItem(
      icon: Icons.directions_car_outlined,
      activeIcon: Icons.directions_car,
      label: 'Rides',
      screen: RidesScreen(),
    ),
    _NavItem(
      icon: Icons.menu,
      activeIcon: Icons.menu,
      label: 'More',
      screen: SizedBox.shrink(), // placeholder – opens drawer
    ),
  ];

  // Drawer-only screens (accessed via "More" or swipe drawer)
  static const _drawerOnlyScreens = <_NavItem>[
    _NavItem(
      icon: Icons.person_outline,
      activeIcon: Icons.person,
      label: 'Users',
      screen: UsersScreen(),
    ),
    _NavItem(
      icon: Icons.account_balance_wallet_outlined,
      activeIcon: Icons.account_balance_wallet,
      label: 'Earnings',
      screen: EarningsReportScreen(),
    ),
    _NavItem(
      icon: Icons.description_outlined,
      activeIcon: Icons.description,
      label: 'Documents',
      screen: DocumentManagementScreen(),
    ),
    _NavItem(
      icon: Icons.notifications_outlined,
      activeIcon: Icons.notifications,
      label: 'Alerts',
      screen: NotificationSettingsScreen(),
    ),
    _NavItem(
      icon: Icons.group_remove_outlined,
      activeIcon: Icons.group_remove,
      label: 'Account Requests',
      screen: AccountHandlingScreen(),
    ),
  ];

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Track if we're on a "drawer" screen
  bool _isDrawerScreen = false;
  int _drawerScreenIndex = 0;

  Widget get _currentScreen {
    if (_isDrawerScreen) {
      return _drawerOnlyScreens[_drawerScreenIndex].screen;
    }
    return _bottomNavScreens[_selectedIndex].screen;
  }

  String get _currentTitle {
    if (_isDrawerScreen) {
      return _drawerOnlyScreens[_drawerScreenIndex].label;
    }
    return _bottomNavScreens[_selectedIndex].label;
  }

  void _onBottomNavTap(int index) {
    if (index == 3) {
      // "More" button → open the drawer
      _scaffoldKey.currentState?.openDrawer();
      return;
    }
    setState(() {
      _selectedIndex = index;
      _isDrawerScreen = false;
    });
  }

  void _onDrawerItemTap(int drawerIndex) {
    Navigator.pop(context); // close drawer
    setState(() {
      _isDrawerScreen = true;
      _drawerScreenIndex = drawerIndex;
      _selectedIndex = -1; // deselect bottom nav
    });
  }

  void _onDrawerPrimaryTap(int bottomIndex) {
    Navigator.pop(context);
    setState(() {
      _selectedIndex = bottomIndex;
      _isDrawerScreen = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded, size: 24),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: Text(
          _currentTitle,
          style: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppTheme.text,
          ),
        ),
        actions: [
          // Notification bell
          IconButton(
            icon: const Icon(
              Icons.notifications_none_rounded,
              color: AppTheme.text2,
            ),
            onPressed: () {
              setState(() {
                _isDrawerScreen = true;
                _drawerScreenIndex = 3; // Alerts
                _selectedIndex = -1;
              });
            },
          ),
          // Profile / Logout
          PopupMenuButton<String>(
            icon: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppTheme.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.border),
              ),
              child: const Icon(Icons.person, size: 18, color: AppTheme.text2),
            ),
            onSelected: (v) {
              if (v == 'logout') FirebaseAuth.instance.signOut();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Text(
                  user?.email ?? 'Admin',
                  style: GoogleFonts.inter(fontSize: 13, color: AppTheme.text3),
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    const Icon(Icons.logout, size: 18, color: AppTheme.danger),
                    const SizedBox(width: 8),
                    Text(
                      'Sign Out',
                      style: GoogleFonts.inter(
                        color: AppTheme.danger,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppTheme.border),
        ),
      ),

      // ── Drawer ──
      drawer: _buildDrawer(user),

      // ── Body ──
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: KeyedSubtree(
          key: ValueKey('$_selectedIndex-$_isDrawerScreen-$_drawerScreenIndex'),
          child: _currentScreen,
        ),
      ),

      // ── Bottom Navigation (4 items only) ──
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(height: 1, color: AppTheme.border),
          NavigationBar(
            height: 64,
            selectedIndex: _isDrawerScreen
                ? 3
                : (_selectedIndex < 0 ? 0 : _selectedIndex),
            onDestinationSelected: _onBottomNavTap,
            backgroundColor: AppTheme.bg,
            elevation: 0,
            indicatorColor: AppTheme.primary.withValues(alpha: 0.06),
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: _bottomNavScreens.map((item) {
              return NavigationDestination(
                icon: Icon(item.icon),
                selectedIcon: Icon(item.activeIcon),
                label: item.label,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer(User? user) {
    return Drawer(
      backgroundColor: AppTheme.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(0)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Drawer Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Text(
                        'M',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Mana Yatra',
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Admin Panel',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppTheme.text3,
                    ),
                  ),
                  if (user?.email != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      user!.email!,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppTheme.text3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Container(height: 1, color: AppTheme.border),

            const SizedBox(height: 8),

            // ── Primary Navigation ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'MAIN',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.text3,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 4),
            ...List.generate(3, (i) {
              final item = _bottomNavScreens[i];
              final isActive = !_isDrawerScreen && _selectedIndex == i;
              return _drawerTile(
                icon: isActive ? item.activeIcon : item.icon,
                label: item.label,
                isActive: isActive,
                onTap: () => _onDrawerPrimaryTap(i),
              );
            }),

            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'MANAGEMENT',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.text3,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 4),
            ...List.generate(_drawerOnlyScreens.length, (i) {
              final item = _drawerOnlyScreens[i];
              final isActive = _isDrawerScreen && _drawerScreenIndex == i;
              return _drawerTile(
                icon: isActive ? item.activeIcon : item.icon,
                label: item.label,
                isActive: isActive,
                onTap: () => _onDrawerItemTap(i),
              );
            }),

            const Spacer(),

            // ── Logout ──
            Container(height: 1, color: AppTheme.border),
            _drawerTile(
              icon: Icons.logout,
              label: 'Sign Out',
              isActive: false,
              onTap: () {
                Navigator.pop(context);
                FirebaseAuth.instance.signOut();
              },
              isDanger: true,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _drawerTile({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    bool isDanger = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: isActive ? AppTheme.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isDanger
                      ? AppTheme.danger
                      : isActive
                      ? AppTheme.text
                      : AppTheme.text2,
                ),
                const SizedBox(width: 14),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                    color: isDanger
                        ? AppTheme.danger
                        : isActive
                        ? AppTheme.text
                        : AppTheme.text2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
