// lib/screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/theme.dart';
import 'referral_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Settings', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        backgroundColor: AppTheme.surface,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _buildSectionTitle('Tools'),
          _buildSettingTile(
            icon: Icons.monitor_heart_outlined,
            title: 'App Diagnostics',
            onTap: _showDiagnosticsDialog,
          ),
          _buildSettingTile(
            icon: Icons.card_giftcard,
            title: 'Refer & Earn',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ReferralScreen()),
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionTitle('About'),
          _buildSettingTile(
            icon: Icons.description_outlined,
            title: 'Terms & Conditions',
            onTap: () async {
              final Uri url = Uri.parse('https://manayatra.com/terms');
              if (await canLaunchUrl(url)) await launchUrl(url);
            },
          ),
          _buildSettingTile(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy Policy',
            onTap: () async {
              final Uri url = Uri.parse('https://manayatra.com/privacy');
              if (await canLaunchUrl(url)) await launchUrl(url);
            },
          ),
          
          const SizedBox(height: 48),
          Center(
            child: Text(
              'Driver App Version 1.0.0',
              style: GoogleFonts.inter(fontSize: 14, color: AppTheme.text3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        title,
        style: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppTheme.text2,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildSettingTile({required IconData icon, required String title, required VoidCallback onTap}) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AppTheme.text),
      title: Text(
        title,
        style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w500, color: AppTheme.text),
      ),
      trailing: const Icon(Icons.chevron_right, color: AppTheme.text3),
      onTap: onTap,
    );
  }

  void _showDiagnosticsDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setState) {
          bool isChecking = true;
          Future.delayed(const Duration(seconds: 2), () {
            if (context.mounted) {
              setState(() => isChecking = false);
            }
          });

          return AlertDialog(
            backgroundColor: AppTheme.surface,
            title: Text('App Diagnostics', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isChecking) ...[
                  const CircularProgressIndicator(color: AppTheme.primary),
                  const SizedBox(height: 16),
                  Text('Checking system health...', style: GoogleFonts.inter(color: AppTheme.text2)),
                ] else ...[
                  const Icon(Icons.check_circle, color: AppTheme.success, size: 48),
                  const SizedBox(height: 16),
                  _buildDiagnosticRow(Icons.gps_fixed, 'GPS Signal', 'Strong'),
                  _buildDiagnosticRow(Icons.wifi, 'Network Connection', 'Connected'),
                  _buildDiagnosticRow(Icons.cloud_done_outlined, 'Server Status', 'Operational'),
                ],
              ],
            ),
            actions: [
              if (!isChecking)
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Close', style: GoogleFonts.inter(color: AppTheme.primary, fontWeight: FontWeight.bold)),
                ),
            ],
          );
        });
      },
    );
  }

  Widget _buildDiagnosticRow(IconData icon, String label, String status) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.text2),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: GoogleFonts.inter(fontSize: 14, color: AppTheme.text2))),
          Text(status, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.success)),
        ],
      ),
    );
  }
}
