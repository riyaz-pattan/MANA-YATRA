// lib/screens/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/theme.dart';
import '../main.dart';
import '../providers/driver_provider.dart';
import '../utils/skeleton.dart';
import 'profile_status_screen.dart';
import 'delete_account_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DriverProvider>();
    final profile = provider.profile;

    if (profile == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text('My Profile', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
          backgroundColor: AppTheme.bg,
          elevation: 0,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: const [
                SkeletonBox(width: 100, height: 100, borderRadius: 50),
                SizedBox(height: 16),
                SkeletonBox(width: 140, height: 28, borderRadius: 8),
                SizedBox(height: 4),
                SkeletonBox(width: 120, height: 24, borderRadius: 12),
                SizedBox(height: 32),
                SkeletonBox(width: double.infinity, height: 72, borderRadius: 16),
                SizedBox(height: 16),
                SkeletonBox(width: double.infinity, height: 72, borderRadius: 16),
                SizedBox(height: 16),
                SkeletonBox(width: double.infinity, height: 72, borderRadius: 16),
              ],
            ),
          ),
        ),
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
          color: AppTheme.bg,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // Profile Photo
                GestureDetector(
                  onTap: () {
                    final imageUrl = profile['documents']?['selfieUrl'];
                    if (imageUrl != null) {
                      showDialog(
                        context: context,
                        builder: (ctx) => Dialog(
                          backgroundColor: Colors.transparent,
                          insetPadding: EdgeInsets.zero,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              InteractiveViewer(
                                child: Image.network(imageUrl),
                              ),
                              Positioned(
                                top: 40,
                                right: 20,
                                child: IconButton(
                                  icon: const Icon(Icons.close, color: Colors.white, size: 30),
                                  onPressed: () => Navigator.pop(ctx),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                  },
                  child: CircleAvatar(
                    radius: 50,
                    backgroundColor: AppTheme.primary,
                    backgroundImage: profile['documents']?['selfieUrl'] != null
                        ? NetworkImage(profile['documents']['selfieUrl'])
                        : null,
                    child: profile['documents']?['selfieUrl'] == null
                        ? const Icon(Icons.person, size: 50, color: Colors.white)
                        : null,
                  ),
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
                const SizedBox(height: 24),

                // Details
                const Divider(height: 1, color: AppTheme.border),
                _buildInfoTile(Icons.phone, 'Phone Number', profile['phone'] ?? ''),
                const Divider(height: 1, color: AppTheme.border),
                _buildUpiTile(context, profile['upiId']),
                const Divider(height: 1, color: AppTheme.border),
                _buildInfoTile(Icons.electric_rickshaw, 'Vehicle Type', (profile['vehicleType'] ?? '').toString().toUpperCase()),
                const Divider(height: 1, color: AppTheme.border),
                _buildInfoTile(Icons.pin, 'Vehicle Number', profile['vehicleNumber'] ?? ''),
                const Divider(height: 1, color: AppTheme.border),
                
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await FirebaseAuth.instance.signOut();
                      if (context.mounted) {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const AuthGate()),
                          (_) => false,
                        );
                      }
                    },
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
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: AppTheme.primary, size: 20),
      ),
      title: Text(title, style: GoogleFonts.inter(color: AppTheme.text3, fontSize: 12)),
      subtitle: Text(value, style: GoogleFonts.inter(color: AppTheme.text, fontWeight: FontWeight.w600, fontSize: 16)),
    );
  }

  Widget _buildUpiTile(BuildContext context, String? currentUpi) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.qr_code, color: AppTheme.primary, size: 20),
      ),
      title: Text('UPI ID', style: GoogleFonts.inter(color: AppTheme.text3, fontSize: 12)),
      subtitle: Text(
        currentUpi != null && currentUpi.isNotEmpty ? currentUpi : 'Not set',
        style: GoogleFonts.inter(
          color: currentUpi != null && currentUpi.isNotEmpty ? AppTheme.text : AppTheme.warning,
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.edit, color: AppTheme.primary, size: 20),
        onPressed: () => _showUpiEditDialog(context, currentUpi),
      ),
    );
  }

  void _showUpiEditDialog(BuildContext context, String? currentUpi) {
    final controller = TextEditingController(text: currentUpi);
    final formKey = GlobalKey<FormState>();
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: AppTheme.bg,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Update UPI ID',
                    style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: controller,
                    decoration: InputDecoration(
                      hintText: 'e.g. name@bank',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppTheme.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppTheme.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppTheme.primary),
                      ),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return 'Please enter a UPI ID';
                      if (!RegExp(r'^[a-zA-Z0-9.\-_]{2,256}@[a-zA-Z]{2,64}$').hasMatch(val)) {
                        return 'Invalid UPI ID format';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: isLoading ? null : () => Navigator.pop(ctx),
                          child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.text3, fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: isLoading
                              ? null
                              : () async {
                                  if (formKey.currentState!.validate()) {
                                    setState(() => isLoading = true);
                                    try {
                                      final uid = FirebaseAuth.instance.currentUser?.uid;
                                      if (uid != null) {
                                        await FirebaseFirestore.instance
                                            .collection('drivers')
                                            .doc(uid)
                                            .update({'upiId': controller.text.trim()});
                                      }
                                      if (ctx.mounted) Navigator.pop(ctx);
                                    } catch (e) {
                                      setState(() => isLoading = false);
                                    }
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: isLoading
                              ? const SizedBox(
                                  width: 20, height: 20,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : Text('Save', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
