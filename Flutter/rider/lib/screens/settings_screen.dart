import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'support_screen.dart';
import 'about_screen.dart';
import 'delete_account_screen.dart';
import 'login_screen.dart';
import '../config/theme.dart';
import '../utils/skeleton.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<void> _loadSettingsFuture;
  bool _promoNotificationsEnabled = true;
  String _themeMode = 'System Default';

  @override
  void initState() {
    super.initState();
    // Simulate a brief loading state to show shimmer (as requested for UI polish)
    _loadSettingsFuture = Future.delayed(const Duration(milliseconds: 600));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Text('Settings', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        backgroundColor: AppTheme.surface,
        elevation: 0,
      ),
      body: FutureBuilder<void>(
        future: _loadSettingsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildShimmerLoading();
          }

          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _buildSectionTitle('General'),
              _buildSettingsGroup(
                children: [
                  _buildSettingTile(
                    icon: Icons.info_outline,
                    title: 'About Gaman',
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutScreen()));
                    },
                  ),
                ],
              ),
              
              const SizedBox(height: 24),
              _buildSectionTitle('Preferences'),
              _buildSettingsGroup(
                children: [
                  _buildSwitchTile(
                    icon: Icons.notifications_active_outlined,
                    title: 'Promotional Alerts',
                    value: _promoNotificationsEnabled,
                    onChanged: (val) {
                      setState(() => _promoNotificationsEnabled = val);
                      // TODO: Save preference locally/remotely
                    },
                    showDivider: true,
                  ),
                  _buildSettingTile(
                    icon: Icons.dark_mode_outlined,
                    title: 'App Theme',
                    trailing: Text(_themeMode, style: GoogleFonts.inter(color: AppTheme.text3, fontSize: 13, fontWeight: FontWeight.w500)),
                    onTap: _showThemeDialog,
                  ),
                ],
              ),
              
              const SizedBox(height: 24),
              _buildSectionTitle('Support'),
              _buildSettingsGroup(
                children: [
                  _buildSettingTile(
                    icon: Icons.help_outline,
                    title: 'Help Center',
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const SupportScreen()));
                    },
                    showDivider: true,
                  ),
                  _buildSettingTile(
                    icon: Icons.description_outlined,
                    title: 'Terms of Service',
                    onTap: () async {
                      final Uri url = Uri.parse('https://manayatra.com/terms');
                      if (await canLaunchUrl(url)) await launchUrl(url);
                    },
                    showDivider: true,
                  ),
                  _buildSettingTile(
                    icon: Icons.privacy_tip_outlined,
                    title: 'Privacy Policy',
                    onTap: () async {
                      final Uri url = Uri.parse('https://manayatra.com/privacy');
                      if (await canLaunchUrl(url)) await launchUrl(url);
                    },
                  ),
                ],
              ),
              
              const SizedBox(height: 24),
              _buildSectionTitle('Account'),
              _buildSettingsGroup(
                children: [
                  _buildSettingTile(
                    icon: Icons.logout,
                    title: 'Log Out',
                    textColor: AppTheme.danger,
                    iconColor: AppTheme.danger,
                    onTap: () async {
                      await FirebaseAuth.instance.signOut();
                      if (context.mounted) {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const LoginScreen()),
                          (_) => false,
                        );
                      }
                    },
                    showDivider: true,
                  ),
                  _buildSettingTile(
                    icon: Icons.delete_forever_outlined,
                    title: 'Delete Account',
                    textColor: AppTheme.danger,
                    iconColor: AppTheme.danger,
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const DeleteAccountScreen()));
                    },
                  ),
                ],
              ),
              
              const SizedBox(height: 48),
              Center(
                child: Text(
                  'App Version 1.0.0',
                  style: GoogleFonts.inter(fontSize: 14, color: AppTheme.text3, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showThemeDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('Choose Theme', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: ['System Default', 'Light Mode', 'Dark Mode'].map((mode) {
            return RadioListTile<String>(
              title: Text(mode, style: GoogleFonts.inter(fontSize: 15)),
              value: mode,
              groupValue: _themeMode,
              activeColor: AppTheme.primary,
              onChanged: (val) {
                if (val != null) {
                  setState(() => _themeMode = val);
                  // TODO: Implement actual theme provider switching here
                  Navigator.pop(ctx);
                }
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildShimmerLoading() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SkeletonBox(width: 100, height: 16, borderRadius: 4),
        const SizedBox(height: 16),
        const SkeletonBox(width: double.infinity, height: 64, borderRadius: 16),
        const SizedBox(height: 24),
        const SkeletonBox(width: 100, height: 16, borderRadius: 4),
        const SizedBox(height: 16),
        const SkeletonBox(width: double.infinity, height: 180, borderRadius: 16),
        const SizedBox(height: 24),
        const SkeletonBox(width: 100, height: 16, borderRadius: 4),
        const SizedBox(height: 16),
        const SkeletonBox(width: double.infinity, height: 120, borderRadius: 16),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
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

  Widget _buildSettingsGroup({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon, 
    required String title, 
    required VoidCallback onTap,
    Color? textColor,
    Color? iconColor,
    bool showDivider = false,
    Widget? trailing,
  }) {
    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.bg2,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor ?? AppTheme.primary, size: 20),
          ),
          title: Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 15, 
              fontWeight: FontWeight.w500, 
              color: textColor ?? AppTheme.text,
            ),
          ),
          trailing: trailing ?? const Icon(Icons.chevron_right, color: AppTheme.text3, size: 20),
          onTap: onTap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        if (showDivider)
          const Divider(height: 1, indent: 56, endIndent: 16, color: AppTheme.border),
      ],
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool showDivider = false,
  }) {
    return Column(
      children: [
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          secondary: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.bg2,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: AppTheme.primary, size: 20),
          ),
          title: Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: AppTheme.text,
            ),
          ),
          value: value,
          onChanged: onChanged,
          activeColor: AppTheme.success,
        ),
        if (showDivider)
          const Divider(height: 1, indent: 56, endIndent: 16, color: AppTheme.border),
      ],
    );
  }
}
