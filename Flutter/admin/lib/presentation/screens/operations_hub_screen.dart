// lib/presentation/screens/operations_hub_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/auth_provider.dart';
import 'sos_alerts_screen.dart';
import 'notification_settings_screen.dart';
import 'driver_approvals_screen.dart';

class OperationsHubScreen extends ConsumerWidget {
  const OperationsHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final bg = isDark ? AppTheme.darkBg : AppTheme.lightBg;
    final surface = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final border = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;
    final text3Color = isDark ? AppTheme.darkText3 : AppTheme.lightText3;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: surface,
          elevation: 0,
          title: Text('Operations & Safety', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: textColor)),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: Container(
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: border))),
              child: TabBar(
                labelColor: AppTheme.brandBlue,
                unselectedLabelColor: text3Color,
                indicatorColor: AppTheme.brandBlue,
                indicatorWeight: 3,
                tabs: const [
                  Tab(text: 'SOS Alerts'),
                  Tab(text: 'Push Notifications'),
                  Tab(text: 'Driver Approvals'),
                ],
              ),
            ),
          ),
        ),
        body: const TabBarView(
          children: [
            SOSAlertsScreen(),
            NotificationSettingsScreen(),
            DriverApprovalsScreen(),
          ],
        ),
      ),
    );
  }
}
