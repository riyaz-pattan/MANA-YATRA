// lib/presentation/layouts/admin_shell.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/auth_provider.dart';

/// Navigation item model for the sidebar/bottom nav.
class NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String routeKey;

  const NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.routeKey,
  });
}

/// All navigation items for the admin console.
const List<NavItem> allNavItems = [
  NavItem(
    icon: Icons.dashboard_outlined,
    activeIcon: Icons.dashboard_rounded,
    label: 'Dashboard',
    routeKey: 'dashboard',
  ),
  NavItem(
    icon: Icons.local_taxi_outlined,
    activeIcon: Icons.local_taxi_rounded,
    label: 'Drivers',
    routeKey: 'drivers',
  ),
  NavItem(
    icon: Icons.people_outlined,
    activeIcon: Icons.people_rounded,
    label: 'Riders',
    routeKey: 'riders',
  ),
  NavItem(
    icon: Icons.route_outlined,
    activeIcon: Icons.route_rounded,
    label: 'Rides',
    routeKey: 'rides',
  ),
  NavItem(
    icon: Icons.account_balance_wallet_outlined,
    activeIcon: Icons.account_balance_wallet_rounded,
    label: 'Financials',
    routeKey: 'financials',
  ),
  NavItem(
    icon: Icons.shield_outlined,
    activeIcon: Icons.shield_rounded,
    label: 'Operations',
    routeKey: 'operations',
  ),
  NavItem(
    icon: Icons.support_agent_outlined,
    activeIcon: Icons.support_agent_rounded,
    label: 'Support',
    routeKey: 'support',
  ),

  NavItem(
    icon: Icons.settings_outlined,
    activeIcon: Icons.settings_rounded,
    label: 'System',
    routeKey: 'system',
  ),
];

/// The responsive admin shell that provides:
/// - Desktop: Collapsible sidebar + top bar
/// - Mobile: Bottom navigation + drawer
class AdminShell extends ConsumerStatefulWidget {
  final Widget child;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const AdminShell({
    super.key,
    required this.child,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  @override
  ConsumerState<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends ConsumerState<AdminShell>
    with SingleTickerProviderStateMixin {
  late AnimationController _sidebarController;
  late Animation<double> _sidebarAnimation;

  @override
  void initState() {
    super.initState();
    _sidebarController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _sidebarAnimation = CurvedAnimation(
      parent: _sidebarController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _sidebarController.dispose();
    super.dispose();
  }

  void _toggleSidebar() {
    final isCollapsed = ref.read(sidebarCollapsedProvider);
    ref.read(sidebarCollapsedProvider.notifier).state = !isCollapsed;
    if (isCollapsed) {
      _sidebarController.reverse();
    } else {
      _sidebarController.forward();
    }
  }

  List<NavItem> _getVisibleNavItems() {
    return allNavItems;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 1024;
    final isTablet = screenWidth >= 768 && screenWidth < 1024;
    final isMobile = screenWidth < 768;
    final visibleItems = _getVisibleNavItems();
    
    final adminUserAsync = ref.watch(adminUserProvider);

    return adminUserAsync.when(
      data: (adminUser) {
        if (adminUser == null) {
          return _buildUnauthorizedScreen(isDark);
        }

        if (isMobile) {
          return _buildMobileLayout(visibleItems, isDark);
        }

        return _buildDesktopLayout(visibleItems, isDark, isCollapsed: isTablet);
      },
      loading: () => Scaffold(
        backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
        body: const Center(child: CircularProgressIndicator(color: AppTheme.brandBlue)),
      ),
      error: (_, __) => Scaffold(
        backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
        body: Center(
          child: Text(
            'Error loading admin session.',
            style: GoogleFonts.inter(color: isDark ? AppTheme.darkText : AppTheme.lightText),
          ),
        ),
      ),
    );
  }

  Widget _buildUnauthorizedScreen(bool isDark) {
    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.security, size: 64, color: AppTheme.danger),
              const SizedBox(height: 24),
              Text(
                'Unauthorized Access',
                style: GoogleFonts.inter(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppTheme.darkText : AppTheme.lightText,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Your account has not been granted access to the Admin Console. Please contact the Super Admin to configure your account in the database.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: isDark ? AppTheme.darkText2 : AppTheme.lightText2,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign Out'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.danger,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => FirebaseAuth.instance.signOut(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════
  //  DESKTOP / TABLET LAYOUT
  // ══════════════════════════════
  Widget _buildDesktopLayout(
    List<NavItem> items,
    bool isDark, {
    bool isCollapsed = false,
  }) {
    final collapsed = ref.watch(sidebarCollapsedProvider) || isCollapsed;
    final sidebarWidth = collapsed ? 72.0 : 260.0;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      body: Row(
        children: [
          // ── Sidebar ──
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: sidebarWidth,
            child: _buildSidebar(items, isDark, collapsed),
          ),

          // ── Main Content ──
          Expanded(
            child: Column(
              children: [
                _buildTopBar(isDark),
                Expanded(child: widget.child),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Sidebar ──
  Widget _buildSidebar(List<NavItem> items, bool isDark, bool collapsed, {VoidCallback? onNavItemTapped}) {
    final adminUser = ref.watch(adminUserProvider).valueOrNull;
    final bg = isDark ? AppTheme.sidebarDark : AppTheme.sidebarLight;
    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;
    final text2Color = isDark ? AppTheme.darkText2 : AppTheme.lightText2;
    final text3Color = isDark ? AppTheme.darkText3 : AppTheme.lightText3;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: Border(right: BorderSide(color: borderColor, width: 1)),
      ),
      child: SafeArea(
        child: Column(
        children: [
          // ── Logo Area ──
          Container(
            height: 64,
            padding: EdgeInsets.symmetric(horizontal: collapsed ? 16 : 20),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.brandBlue, AppTheme.brandTeal],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(
                    child: Text(
                      'M',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                if (!collapsed) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Gaman Admin',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: textColor,
                          ),
                        ),
                        Text(
                          'Admin Console',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: text3Color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          Divider(color: borderColor, height: 1),

          // ── Nav Items ──
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              children: [
                if (!collapsed)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: Text(
                      'NAVIGATION',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: text3Color,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ...List.generate(items.length, (i) {
                  final item = items[i];
                  final isActive = widget.selectedIndex == allNavItems.indexOf(item);
                  return Column(
                    children: [
                      _sidebarNavItem(
                        item: item,
                        isActive: isActive,
                        collapsed: collapsed,
                        isDark: isDark,
                        onTap: () {
                          widget.onDestinationSelected(allNavItems.indexOf(item));
                          onNavItemTapped?.call();
                        },
                      ),
                      if (i < items.length - 1)
                        Divider(color: borderColor.withValues(alpha: 0.5), height: 12),
                    ],
                  );
                }),
              ],
            ),
          ),

          Divider(color: borderColor, height: 1),

          // ── Bottom: Collapse toggle + User ──
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                // Collapse button
                if (MediaQuery.of(context).size.width >= 768) ...[
                  _sidebarNavItem(
                    item: const NavItem(
                      icon: Icons.menu_open_rounded,
                      activeIcon: Icons.menu_rounded,
                      label: 'Collapse',
                      routeKey: '',
                    ),
                    isActive: false,
                    collapsed: collapsed,
                    isDark: isDark,
                    onTap: _toggleSidebar,
                    customIcon: collapsed ? Icons.menu_rounded : Icons.menu_open_rounded,
                  ),
                  const SizedBox(height: 4),
                ],

                // Sign out
                _sidebarNavItem(
                  item: const NavItem(
                    icon: Icons.logout_rounded,
                    activeIcon: Icons.logout_rounded,
                    label: 'Sign Out',
                    routeKey: '',
                  ),
                  isActive: false,
                  collapsed: collapsed,
                  isDark: isDark,
                  onTap: () => FirebaseAuth.instance.signOut(),
                  isDanger: true,
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _sidebarNavItem({
    required NavItem item,
    required bool isActive,
    required bool collapsed,
    required bool isDark,
    required VoidCallback onTap,
    bool isDanger = false,
    IconData? customIcon,
  }) {
    final activeBg = isDark
        ? AppTheme.brandBlue.withValues(alpha: 0.12)
        : AppTheme.brandBlue.withValues(alpha: 0.08);
    final hoverBg = isDark
        ? Colors.white.withValues(alpha: 0.04)
        : Colors.black.withValues(alpha: 0.04);
    final activeTextColor = AppTheme.brandBlue;
    final textColor = isDark ? AppTheme.darkText2 : AppTheme.lightText2;
    final dangerColor = AppTheme.danger;

    return Tooltip(
      message: collapsed ? item.label : '',
      waitDuration: const Duration(milliseconds: 500),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Material(
          color: isActive ? activeBg : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            hoverColor: isActive ? null : hoverBg,
            onTap: onTap,
            child: Container(
              height: 52,
              padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 12),
              child: Row(
                mainAxisAlignment:
                    collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
                children: [
                  Icon(
                    customIcon ?? (isActive ? item.activeIcon : item.icon),
                    size: 20,
                    color: isDanger
                        ? dangerColor
                        : isActive
                            ? activeTextColor
                            : textColor,
                  ),
                  if (!collapsed) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        item.label,
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                          color: isDanger
                              ? dangerColor
                              : isActive
                                  ? activeTextColor
                                  : textColor,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Top Bar ──
  Widget _buildTopBar(bool isDark) {
    final adminUser = ref.watch(adminUserProvider).valueOrNull;
    final user = FirebaseAuth.instance.currentUser;
    final bg = isDark ? AppTheme.darkBg : AppTheme.lightBg2;
    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;
    final text2Color = isDark ? AppTheme.darkText2 : AppTheme.lightText2;
    final text3Color = isDark ? AppTheme.darkText3 : AppTheme.lightText3;
    final surfaceColor = isDark ? AppTheme.darkSurface : AppTheme.lightSurface2;

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: bg,
        border: Border(bottom: BorderSide(color: borderColor, width: 1)),
      ),
      child: Row(
        children: [
          // ── Search Bar ──
          Expanded(
            child: Container(
              height: 40,
              constraints: const BoxConstraints(maxWidth: 400),
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Icon(Icons.search, size: 18, color: text3Color),
                  ),
                  Expanded(
                    child: TextField(
                      style: GoogleFonts.inter(fontSize: 13, color: textColor),
                      decoration: InputDecoration(
                        hintText: 'Search drivers, rides, tickets...',
                        hintStyle: GoogleFonts.inter(fontSize: 13, color: text3Color),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        fillColor: Colors.transparent,
                        filled: true,
                        contentPadding: EdgeInsets.zero,
                        isDense: true,
                      ),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: borderColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '⌘K',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: text3Color,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 16),

          // ── Theme Toggle ──
          IconButton(
            icon: Icon(
              isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              size: 20,
              color: text2Color,
            ),
            onPressed: () {
              ref.read(themeModeProvider.notifier).state =
                  isDark ? ThemeMode.light : ThemeMode.dark;
            },
            tooltip: isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
          ),

          // ── Notifications ──
          Stack(
            children: [
              IconButton(
                icon: Icon(
                  Icons.notifications_outlined,
                  size: 20,
                  color: text2Color,
                ),
                onPressed: () {
                  // TODO: Open notifications panel
                },
                tooltip: 'Notifications',
              ),
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppTheme.danger,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(width: 8),

          // ── User Profile ──
          PopupMenuButton<String>(
            offset: const Offset(0, 48),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.brandBlue, AppTheme.brandTeal],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      (adminUser?.displayName?.isNotEmpty == true)
                          ? adminUser!.displayName.substring(0, 1).toUpperCase()
                          : 'A',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      adminUser?.displayName ?? 'Admin',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppTheme.brandBlue.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        (adminUser?.role ?? 'Admin').toUpperCase(),
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.brandBlue,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 4),
                Icon(Icons.expand_more, size: 16, color: text3Color),
              ],
            ),
            onSelected: (v) {
              if (v == 'logout') FirebaseAuth.instance.signOut();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Text(
                  user?.email ?? 'admin@manayatra.com',
                  style: GoogleFonts.inter(fontSize: 12, color: text3Color),
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    const Icon(Icons.logout, size: 16, color: AppTheme.danger),
                    const SizedBox(width: 8),
                    Text(
                      'Sign Out',
                      style: GoogleFonts.inter(
                        color: AppTheme.danger,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════
  //  MOBILE LAYOUT
  // ══════════════════════════════
  Widget _buildMobileLayout(List<NavItem> items, bool isDark) {
    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    // Show max 4 items in bottom nav, rest in drawer
    final bottomItems = items.take(4).toList();

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      drawer: Drawer(
        backgroundColor: isDark ? AppTheme.sidebarDark : AppTheme.sidebarLight,
        child: Builder(
          builder: (drawerContext) => _buildSidebar(items, isDark, false, onNavItemTapped: () {
            Navigator.of(drawerContext).pop();
          }),
        ),
      ),
      appBar: AppBar(
        backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg2,
        title: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.brandBlue, AppTheme.brandTeal],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Text(
                  'M',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Gaman Admin',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: isDark ? AppTheme.darkText : AppTheme.lightText,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              size: 20,
              color: isDark ? AppTheme.darkText2 : AppTheme.lightText2,
            ),
            onPressed: () {
              ref.read(themeModeProvider.notifier).state =
                  isDark ? ThemeMode.light : ThemeMode.dark;
            },
          ),
          IconButton(
            icon: Icon(
              Icons.notifications_outlined,
              size: 20,
              color: isDark ? AppTheme.darkText2 : AppTheme.lightText2,
            ),
            onPressed: () {},
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: borderColor),
        ),
      ),
      body: widget.child,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(height: 1, color: borderColor),
          NavigationBar(
            height: 64,
            selectedIndex: widget.selectedIndex < bottomItems.length
                ? widget.selectedIndex
                : 0,
            onDestinationSelected: (index) {
              if (index < bottomItems.length) {
                widget.onDestinationSelected(
                  allNavItems.indexOf(bottomItems[index]),
                );
              }
            },
            destinations: bottomItems.map((item) {
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
}
