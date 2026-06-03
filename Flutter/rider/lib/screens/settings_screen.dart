import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'support_screen.dart';
import 'about_screen.dart';
import 'delete_account_screen.dart';
import 'login_screen.dart';
import '../config/theme.dart';
import '../main.dart';
import '../utils/skeleton.dart';
import 'package:package_info_plus/package_info_plus.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<void> _loadSettingsFuture;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadSettingsFuture = _initSettings();
  }

  Future<void> _initSettings() async {
    await Future.delayed(const Duration(milliseconds: 600));
    final packageInfo = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _appVersion = packageInfo.version;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Text('Settings', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 24, letterSpacing: -0.5, color: AppTheme.text)),
        backgroundColor: AppTheme.bg,
        elevation: 0,
        centerTitle: true,
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
                      final Uri url = Uri.parse('https://gamanrides.netlify.app/terms-of-service');
                      if (await canLaunchUrl(url)) await launchUrl(url);
                    },
                    showDivider: true,
                  ),
                  _buildSettingTile(
                    icon: Icons.privacy_tip_outlined,
                    title: 'Privacy Policy',
                    onTap: () async {
                      final Uri url = Uri.parse('https://gamanrides.netlify.app/privacy-policy');
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
                          MaterialPageRoute(builder: (_) => const AuthGate()),
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
                  'App Version $_appVersion',
                  style: GoogleFonts.inter(fontSize: 14, color: AppTheme.text3, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
  Widget _buildShimmerLoading() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SkeletonBox(width: 100, height: 16, borderRadius: 4),
        const SizedBox(height: 16),
        const SkeletonBox(width: double.infinity, height: 48, borderRadius: 8),
        const SizedBox(height: 24),
        const SkeletonBox(width: 100, height: 16, borderRadius: 4),
        const SizedBox(height: 16),
        const SkeletonBox(width: double.infinity, height: 140, borderRadius: 8),
        const SizedBox(height: 24),
        const SkeletonBox(width: 100, height: 16, borderRadius: 4),
        const SizedBox(height: 16),
        const SkeletonBox(width: double.infinity, height: 100, borderRadius: 8),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 16),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppTheme.text3,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildSettingsGroup({required List<Widget> children}) {
    return Column(
      children: children,
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
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          leading: Icon(icon, color: iconColor ?? AppTheme.text, size: 24),
          title: Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 16, 
              fontWeight: FontWeight.w600, 
              color: textColor ?? AppTheme.text,
            ),
          ),
          trailing: trailing ?? const Icon(Icons.chevron_right, color: AppTheme.text3, size: 20),
          onTap: onTap,
        ),
        if (showDivider)
          Divider(height: 1, indent: 44, color: AppTheme.border.withValues(alpha: 0.5)),
      ],
    );
  }
}
