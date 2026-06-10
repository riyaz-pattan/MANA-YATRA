// lib/presentation/screens/feature_flags_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/audit_log_service.dart';

class FeatureFlagsScreen extends ConsumerStatefulWidget {
  const FeatureFlagsScreen({super.key});

  @override
  ConsumerState<FeatureFlagsScreen> createState() => _FeatureFlagsScreenState();
}

class _FeatureFlagsScreenState extends ConsumerState<FeatureFlagsScreen> {
  final Map<String, dynamic> _localFlags = {};

  Future<void> _updateFlag(String key, bool value) async {
    setState(() {
      _localFlags[key] = value;
    });

    try {
      final admin = ref.read(adminUserProvider).valueOrNull;
      if (true) {
        await AuditLogService.logAction(
          action: 'toggled_feature_flag',
          targetId: key,
          admin: admin,
          details: 'Flag $key changed to $value'
        );
      }
      await FirebaseFirestore.instance.collection('config').doc('feature_flags').set({
        key: value,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feature flag "$key" updated to $value')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update flag: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final bg = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final border = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;
    final text3Color = isDark ? AppTheme.darkText3 : AppTheme.lightText3;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('config').doc('feature_flags').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};

        // Merge backend data with local pessimistic state to prevent jitter
        data.forEach((key, val) {
          if (!_localFlags.containsKey(key)) {
            _localFlags[key] = val;
          }
        });

        final List<Map<String, dynamic>> standardFlags = [
          {'key': 'enable_referrals', 'name': 'Referral Program', 'desc': 'Allow users to refer friends.'},
          {'key': 'enable_wallet', 'name': 'In-App Wallet', 'desc': 'Enable the digital wallet feature for payments.'},
          {'key': 'maintenance_mode', 'name': 'Maintenance Mode', 'desc': 'Disables app access for all non-admin users.', 'isDangerous': true},
          {'key': 'surge_pricing', 'name': 'Surge Pricing', 'desc': 'Enable dynamic surge pricing across active zones.'},
        ];

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('Remote Configuration', style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, color: textColor)),
            const SizedBox(height: 8),
            Text('Toggle platform features in real-time.', style: GoogleFonts.inter(color: text3Color)),
            const SizedBox(height: 32),
            
            ...standardFlags.map((flag) {
              final key = flag['key'] as String;
              final bool val = data[key] ?? _localFlags[key] ?? false;
              final bool isDangerous = flag['isDangerous'] == true;

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isDangerous && val ? AppTheme.danger : border, width: isDangerous && val ? 2 : 1),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(flag['name'], style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: isDangerous && val ? AppTheme.danger : textColor)),
                          const SizedBox(height: 4),
                          Text(flag['desc'], style: GoogleFonts.inter(fontSize: 14, color: text3Color)),
                        ],
                      ),
                    ),
                    Switch(
                      value: val,
                      activeColor: isDangerous ? AppTheme.danger : AppTheme.success,
                      onChanged: (newValue) => _updateFlag(key, newValue),
                    ),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }
}
