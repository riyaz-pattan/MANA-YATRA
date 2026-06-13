// lib/presentation/screens/feature_flags_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
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
      await FirebaseDatabase.instance.ref('config/feature_flags').update({
        key: value,
        'updatedAt': ServerValue.timestamp,
      });
      
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

    return StreamBuilder<DatabaseEvent>(
      stream: FirebaseDatabase.instance.ref('config').onValue,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final rawData = snapshot.data?.snapshot.value;
        final Map<String, dynamic> configMap = rawData is Map 
            ? Map<String, dynamic>.from(rawData)
            : {};

        final Map<String, dynamic> data = configMap['feature_flags'] is Map 
            ? Map<String, dynamic>.from(configMap['feature_flags'])
            : {};
            
        final Map<String, dynamic> versionsData = configMap['app_versions'] is Map 
            ? Map<String, dynamic>.from(configMap['app_versions'])
            : {};

        // Merge backend data with local pessimistic state to prevent jitter
        data.forEach((key, val) {
          if (!_localFlags.containsKey(key)) {
            _localFlags[key] = val;
          }
        });

        final List<Map<String, dynamic>> standardFlags = [
          {'key': 'enable_referrals', 'name': 'Referral Program', 'desc': 'Allow users to refer friends.'},
          {'key': 'maintenance_mode', 'name': 'Maintenance Mode', 'desc': 'Disables app access for all non-admin users.', 'isDangerous': true},
        ];

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('Remote Configuration', style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, color: textColor)),
            const SizedBox(height: 8),
            Text('Manage Force App Updates and Feature Flags globally.', style: GoogleFonts.inter(color: text3Color)),
            const SizedBox(height: 32),

            // App Versions Configuration
            AppVersionsCard(
              appType: 'rider',
              versions: versionsData['rider'] is Map ? versionsData['rider'] : {},
              bg: bg,
              border: border,
              textColor: textColor,
              text3Color: text3Color,
            ),
            AppVersionsCard(
              appType: 'driver',
              versions: versionsData['driver'] is Map ? versionsData['driver'] : {},
              bg: bg,
              border: border,
              textColor: textColor,
              text3Color: text3Color,
            ),

            const SizedBox(height: 16),
            Text('Feature Flags', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: textColor)),
            const SizedBox(height: 16),
            
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

class AppVersionsCard extends StatefulWidget {
  final String appType;
  final Map<dynamic, dynamic> versions;
  final Color bg, border, textColor, text3Color;

  const AppVersionsCard({
    super.key,
    required this.appType,
    required this.versions,
    required this.bg,
    required this.border,
    required this.textColor,
    required this.text3Color,
  });

  @override
  State<AppVersionsCard> createState() => _AppVersionsCardState();
}

class _AppVersionsCardState extends State<AppVersionsCard> {
  late TextEditingController _latestCtrl;
  late TextEditingController _minCtrl;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _latestCtrl = TextEditingController(text: widget.versions['latest_version']?.toString() ?? '1.0.0');
    _minCtrl = TextEditingController(text: widget.versions['min_required_version']?.toString() ?? '1.0.0');
  }

  @override
  void didUpdateWidget(AppVersionsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.versions['latest_version'] != widget.versions['latest_version']) {
      _latestCtrl.text = widget.versions['latest_version']?.toString() ?? '1.0.0';
    }
    if (oldWidget.versions['min_required_version'] != widget.versions['min_required_version']) {
      _minCtrl.text = widget.versions['min_required_version']?.toString() ?? '1.0.0';
    }
  }

  @override
  void dispose() {
    _latestCtrl.dispose();
    _minCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await FirebaseDatabase.instance.ref('config/app_versions/${widget.appType}').set({
        'latest_version': _latestCtrl.text.trim(),
        'min_required_version': _minCtrl.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved ${widget.appType} versions')));
      }
    } catch(e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.danger));
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: widget.bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: widget.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(widget.appType == 'rider' ? Icons.person : Icons.drive_eta, color: widget.textColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${widget.appType.toUpperCase()} APP VERSIONS', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: widget.textColor)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _latestCtrl,
                  style: TextStyle(color: widget.textColor),
                  decoration: InputDecoration(
                    labelText: 'Latest Version',
                    labelStyle: TextStyle(color: widget.text3Color),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: widget.border)),
                    focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppTheme.brandBlue)),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _minCtrl,
                  style: TextStyle(color: widget.textColor),
                  decoration: InputDecoration(
                    labelText: 'Min Required Version',
                    labelStyle: TextStyle(color: widget.text3Color),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: widget.border)),
                    focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppTheme.brandBlue)),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.brandBlue, minimumSize: Size.zero, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24)),
                child: _isSaving 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Save', style: TextStyle(color: Colors.white)),
              ),
            ],
          )
        ],
      )
    );
  }
}
