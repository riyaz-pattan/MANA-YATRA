// lib/presentation/screens/financials_hub_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/auth_provider.dart';
import 'earnings_report_screen.dart';
import 'payouts_screen.dart';
import 'pricing_config_screen.dart';

class FinancialsHubScreen extends ConsumerWidget {
  const FinancialsHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final bg = isDark ? AppTheme.darkBg : AppTheme.lightBg;
    final surface = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final border = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;
    final text3Color = isDark ? AppTheme.darkText3 : AppTheme.lightText3;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: surface,
          elevation: 0,
          title: Text('Financials & Pricing', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: textColor)),
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
                  Tab(text: 'Overview'),
                  Tab(text: 'Pricing Config'),
                ],
              ),
            ),
          ),
        ),
        body: const TabBarView(
          children: [
            EarningsReportScreen(),
            PricingConfigScreen(),
          ],
        ),
      ),
    );
  }
}
