// lib/screens/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/theme.dart';
import '../services/google_maps_service.dart';
import '../utils/custom_toast.dart';
import 'profile_details_screen.dart';
import 'ride_history_screen.dart';
import 'settings_screen.dart';
import 'support_screen.dart';
import 'emergency_contacts_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // ── Saved Places Logic ────────────────────────────────────
  Future<void> _editSavedPlace(String label, String firestoreKey) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final searchCtrl = TextEditingController();
    List<PlacePrediction> predictions = [];
    bool searching = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.8,
                ),
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle bar
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppTheme.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Icon(
                          label == 'Home' ? Icons.home : Icons.work,
                          color: AppTheme.primary,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Text('Set $label Location',
                            style: GoogleFonts.inter(
                                fontSize: 20, fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: searchCtrl,
                      autofocus: true,
                      style: GoogleFonts.inter(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Search for $label location...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  searchCtrl.clear();
                                  setSheetState(() => predictions = []);
                                },
                              )
                            : null,
                      ),
                      onChanged: (q) async {
                        if (q.isEmpty) {
                          setSheetState(() => predictions = []);
                          return;
                        }
                        setSheetState(() => searching = true);
                        final res = await GoogleMapsService.getPlacePredictions(q);
                        setSheetState(() {
                          predictions = res;
                          searching = false;
                        });
                      },
                    ),
                    if (searching)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(
                            child: CircularProgressIndicator(
                                color: AppTheme.primary, strokeWidth: 2)),
                      ),
                    
                    // Results list
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: predictions.length,
                        padding: const EdgeInsets.only(top: 8),
                        itemBuilder: (context, index) {
                          final p = predictions[index];
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppTheme.bg2,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.location_on_outlined,
                                  size: 18, color: AppTheme.primary),
                            ),
                            title: Text(p.primaryText,
                                style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w600, fontSize: 14)),
                            subtitle: Text(p.secondaryText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                    color: AppTheme.text3, fontSize: 12)),
                            onTap: () async {
                              setSheetState(() => searching = true);
                              
                              // Fetch full details (lat/lng) for the selected place
                              final detail = await GoogleMapsService.getPlaceDetails(p.placeId);
                              
                              if (detail != null) {
                                await FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(uid)
                                    .update({firestoreKey: detail.toMap()});
                                
                                if (ctx.mounted) Navigator.pop(ctx);
                                if (!context.mounted) return;
                                CustomToast.show(
                                    context: context,
                                    message: '$label location saved');
                              } else {
                                setSheetState(() => searching = false);
                                if (!context.mounted) return;
                                CustomToast.show(
                                    context: context,
                                    message: 'Failed to fetch location details');
                              }
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _removeSavedPlace(String firestoreKey, String label) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Remove $label?',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        content: Text('This will remove your saved $label location.',
            style: GoogleFonts.inter(color: AppTheme.text2)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                Text('Cancel', style: GoogleFonts.inter(color: AppTheme.text3)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger,
              minimumSize: const Size(80, 40),
            ),
            child: Text('Remove', style: GoogleFonts.inter()),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({firestoreKey: FieldValue.delete()});
      if (mounted) {
        CustomToast.show(
            context: context, message: '$label location removed');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Text('My Profile', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        backgroundColor: AppTheme.surface,
        elevation: 0,
      ),
      body: uid == null 
          ? const Center(child: Text("Not signed in"))
          : StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
                }

                final data = snapshot.data!.data() as Map<String, dynamic>?;
                final name = data?['name'] ?? 'Rider';
                final phone = FirebaseAuth.instance.currentUser?.phoneNumber ?? 'Unknown';

                return ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                  children: [
                    // ── Header Profile Info ──
                    GestureDetector(
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileDetailsScreen()));
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Row(
                          children: [
                            const CircleAvatar(
                              radius: 32,
                              backgroundColor: AppTheme.bg2,
                              child: Icon(Icons.person, size: 32, color: AppTheme.text3),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.text),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    phone,
                                    style: GoogleFonts.inter(fontSize: 14, color: AppTheme.text2),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right, color: AppTheme.text3),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    Text('Dashboard', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.text2, letterSpacing: 1.2)),
                    const SizedBox(height: 8),
                    _buildTile(
                      icon: Icons.history,
                      title: 'Ride History',
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const RideHistoryScreen()));
                      },
                    ),
                    _buildTile(
                      icon: Icons.emergency_share_outlined,
                      title: 'Emergency Contacts',
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const EmergencyContactsScreen()));
                      },
                    ),
                    _buildTile(
                      icon: Icons.payment,
                      title: 'Payment',
                      onTap: () {
                        CustomToast.show(context: context, message: 'Payment module coming soon');
                      },
                    ),
                    
                    const SizedBox(height: 24),
                    Text('Saved Places', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.text2, letterSpacing: 1.2)),
                    const SizedBox(height: 8),
                    _buildSavedPlacesSection(data),

                    const SizedBox(height: 24),
                    Text('Preferences', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.text2, letterSpacing: 1.2)),
                    const SizedBox(height: 8),
                    _buildTile(
                      icon: Icons.settings_outlined,
                      title: 'Settings',
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
                      },
                    ),
                    _buildTile(
                      icon: Icons.help_outline,
                      title: 'Help',
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const SupportScreen()));
                      },
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildTile({required IconData icon, required String title, required VoidCallback onTap}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.bg2,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppTheme.primary, size: 20),
        ),
        title: Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 16)),
        trailing: const Icon(Icons.chevron_right, color: AppTheme.text3),
      ),
    );
  }

  Widget _buildSavedPlacesSection(Map<String, dynamic>? data) {
    final homePlace = data?['savedHome'] as Map<String, dynamic>?;
    final workPlace = data?['savedWork'] as Map<String, dynamic>?;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          _buildSavedPlaceRow(
            icon: Icons.home_rounded,
            label: 'Home',
            address: homePlace?['short_name'],
            firestoreKey: 'savedHome',
          ),
          Divider(color: AppTheme.border, height: 24),
          _buildSavedPlaceRow(
            icon: Icons.work_rounded,
            label: 'Work',
            address: workPlace?['short_name'],
            firestoreKey: 'savedWork',
          ),
        ],
      ),
    );
  }

  Widget _buildSavedPlaceRow({
    required IconData icon,
    required String label,
    required String? address,
    required String firestoreKey,
  }) {
    final isSet = address != null;

    return InkWell(
      onTap: () => _editSavedPlace(label, firestoreKey),
      borderRadius: BorderRadius.circular(12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: isSet ? AppTheme.primary.withValues(alpha: 0.1) : AppTheme.bg2,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 22, color: isSet ? AppTheme.primary : AppTheme.text3),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.text),
                ),
                const SizedBox(height: 2),
                Text(
                  isSet ? address : 'Tap to add $label location',
                  style: GoogleFonts.inter(fontSize: 12, color: isSet ? AppTheme.text2 : AppTheme.text3),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (isSet)
            IconButton(
              icon: const Icon(Icons.close, size: 18, color: AppTheme.text3),
              onPressed: () => _removeSavedPlace(firestoreKey, label),
              tooltip: 'Remove',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            )
          else
            const Icon(Icons.add, size: 20, color: AppTheme.primary),
        ],
      ),
    );
  }
}

