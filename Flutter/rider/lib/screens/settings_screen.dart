// lib/screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'support_screen.dart';
import 'about_screen.dart';
import 'delete_account_screen.dart';
import 'login_screen.dart';
import '../config/theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Text('Settings', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        backgroundColor: AppTheme.surface,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _buildSectionTitle('General'),
          _buildSettingTile(
            icon: Icons.info_outline,
            title: 'About Mana Yatra',
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutScreen()));
            },
          ),
          
          const SizedBox(height: 24),
          _buildSectionTitle('Support'),
          _buildSettingTile(
            icon: Icons.help_outline,
            title: 'Help Center',
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SupportScreen()));
            },
          ),
          _buildSettingTile(
            icon: Icons.description_outlined,
            title: 'Terms of Service',
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
          
          const SizedBox(height: 24),
          _buildSectionTitle('Account'),
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
          
          const SizedBox(height: 48),
          Center(
            child: Text(
              'App Version 1.0.0',
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

  Widget _buildSettingTile({
    required IconData icon, 
    required String title, 
    required VoidCallback onTap,
    Color? textColor,
    Color? iconColor,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: iconColor ?? AppTheme.text),
      title: Text(
        title,
        style: GoogleFonts.inter(
          fontSize: 16, 
          fontWeight: FontWeight.w500, 
          color: textColor ?? AppTheme.text,
        ),
      ),
      trailing: const Icon(Icons.chevron_right, color: AppTheme.text3),
      onTap: onTap,
    );
  }
}
