// lib/screens/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../config/theme.dart';
import '../providers/driver_provider.dart';
import 'profile_status_screen.dart';
import 'delete_account_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DriverProvider>();
    final profile = provider.profile;

    if (profile == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!provider.isApproved) {
      return const ProfileStatusScreen();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('My Profile', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        backgroundColor: AppTheme.bg,
        elevation: 0,
      ),
      body: Container(
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppTheme.bg, AppTheme.bg2],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // Profile Photo
                CircleAvatar(
                  radius: 50,
                  backgroundColor: AppTheme.primary,
                  backgroundImage: profile['documents']?['selfieUrl'] != null
                      ? NetworkImage(profile['documents']['selfieUrl'])
                      : null,
                  child: profile['documents']?['selfieUrl'] == null
                      ? const Icon(Icons.person, size: 50, color: Colors.white)
                      : null,
                ),
                const SizedBox(height: 16),
                Text(
                  profile['name'] ?? 'Driver',
                  style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Verified Partner',
                    style: GoogleFonts.inter(color: AppTheme.success, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 32),

                // Details
                _buildInfoTile(Icons.phone, 'Phone Number', profile['phone'] ?? ''),
                _buildInfoTile(Icons.electric_rickshaw, 'Vehicle Type', (profile['vehicleType'] ?? '').toString().toUpperCase()),
                _buildInfoTile(Icons.pin, 'Vehicle Number', profile['vehicleNumber'] ?? ''),
                
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: OutlinedButton.icon(
                    onPressed: () => FirebaseAuth.instance.signOut(),
                    icon: const Icon(Icons.logout, color: AppTheme.danger),
                    label: Text(
                      'Log Out',
                      style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.danger),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppTheme.danger),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const DeleteAccountScreen()),
                      );
                    },
                    child: Text(
                      'Delete Account',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.text3,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String title, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppTheme.primary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.inter(color: AppTheme.text3, fontSize: 13)),
                const SizedBox(height: 4),
                Text(value, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 16)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
