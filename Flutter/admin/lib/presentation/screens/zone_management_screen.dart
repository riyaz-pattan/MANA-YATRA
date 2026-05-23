// lib/presentation/screens/zone_management_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/auth_provider.dart';

class ZoneManagementScreen extends ConsumerWidget {
  const ZoneManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;
    final text3Color = isDark ? AppTheme.darkText3 : AppTheme.lightText3;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.map_outlined, size: 80, color: AppTheme.brandBlue.withValues(alpha: 0.5)),
          const SizedBox(height: 24),
          Text('Geofence & Zones', style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, color: textColor)),
          const SizedBox(height: 8),
          Text('Map integration coming soon.', style: GoogleFonts.inter(fontSize: 16, color: text3Color)),
        ],
      ),
    );
  }
}
