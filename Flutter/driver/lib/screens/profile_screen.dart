// lib/screens/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../config/theme.dart';
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
                const SizedBox(height: 24),
                _buildScorecard(profile),
                const SizedBox(height: 16),
                _buildCompliments(profile),
                const SizedBox(height: 32),

                // Details
                _buildInfoTile(Icons.phone, 'Phone Number', profile['phone'] ?? ''),
                _buildUpiTile(context, profile['upiId']),
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
  Widget _buildScorecard(Map<String, dynamic> profile) {
    final rating = profile['rating']?.toString() ?? '4.9';
    final totalRides = profile['totalRides']?.toString() ?? '0';

    final wonBids = profile['wonBids'] as num? ?? 0;
    final totalBids = profile['totalBids'] as num? ?? 0;
    final completedRides = profile['completedRides'] as num? ?? 0;

    String completionRate = '100%';
    if (wonBids > 0) {
      completionRate = '${(completedRides / wonBids * 100).toStringAsFixed(0)}%';
    } else if (profile.containsKey('completionRate')) {
      completionRate = profile['completionRate']?.toString() ?? '100%';
    }

    String winRate = '--%';
    if (totalBids > 0) {
      winRate = '${(wonBids / totalBids * 100).toStringAsFixed(0)}%';
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Expanded(child: _buildScoreItem(Icons.star_rounded, rating, 'Rating', AppTheme.warning)),
          Container(height: 40, width: 1, color: AppTheme.border),
          Expanded(child: _buildScoreItem(Icons.route, totalRides, 'Rides', AppTheme.primary)),
          Container(height: 40, width: 1, color: AppTheme.border),
          Expanded(child: _buildScoreItem(Icons.check_circle_outline, completionRate, 'Completion', AppTheme.success)),
          Container(height: 40, width: 1, color: AppTheme.border),
          Expanded(child: _buildScoreItem(Icons.emoji_events_outlined, winRate, 'Win Rate', AppTheme.text)),
        ],
      ),
    );
  }

  Widget _buildScoreItem(IconData icon, String value, String label, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                value,
                style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.text),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 11, color: AppTheme.text2),
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildCompliments(Map<String, dynamic> profile) {
    final Map<String, dynamic> complimentsMap = 
        (profile['compliments'] as Map?)?.cast<String, dynamic>() ?? {};
        
    List<String> displayTags = [];
    if (complimentsMap.isEmpty) {
      displayTags = ['Clean Vehicle', 'Polite', 'Great Music', 'Safe Driving'];
    } else {
      final entries = complimentsMap.entries.toList()
        ..sort((a, b) => (b.value as num).compareTo(a.value as num));
      displayTags = entries.take(4).map((e) => '${e.key} (${e.value})').toList();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Compliments & Tags', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.text2)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: displayTags.map((tag) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.bg2,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.border),
            ),
            child: Text(tag, style: GoogleFonts.inter(fontSize: 13, color: AppTheme.text, fontWeight: FontWeight.w500)),
          )).toList(),
        ),
      ],
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

  Widget _buildUpiTile(BuildContext context, String? currentUpi) {
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
            child: const Icon(Icons.qr_code, color: AppTheme.primary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('UPI ID', style: GoogleFonts.inter(color: AppTheme.text3, fontSize: 13)),
                const SizedBox(height: 4),
                Text(
                  currentUpi != null && currentUpi.isNotEmpty ? currentUpi : 'Not set',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600, 
                    fontSize: 16,
                    color: currentUpi != null && currentUpi.isNotEmpty ? AppTheme.text : AppTheme.warning,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit, color: AppTheme.primary, size: 20),
            onPressed: () => _showUpiEditDialog(context, currentUpi),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
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
          backgroundColor: AppTheme.surface,
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
