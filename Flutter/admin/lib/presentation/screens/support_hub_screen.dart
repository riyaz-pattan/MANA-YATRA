// lib/presentation/screens/support_hub_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/auth_provider.dart';
import 'support_tickets_screen.dart';
import 'document_management_screen.dart';

class SupportHubScreen extends ConsumerWidget {
  const SupportHubScreen({super.key});

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
          title: Text('Support & Moderation', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: textColor)),
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
                  Tab(text: 'Support Tickets'),
                  Tab(text: 'Document Reviews'),
                ],
              ),
            ),
          ),
        ),
        body: const TabBarView(
          children: [
            SupportTicketsScreen(),
            DocumentManagementScreen(),
          ],
        ),
      ),
    );
  }
}
