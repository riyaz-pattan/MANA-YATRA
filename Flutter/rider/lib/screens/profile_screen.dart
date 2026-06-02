import 'dart:async';
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
import '../utils/skeleton.dart';

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
    final customNameCtrl = TextEditingController();
    List<PlacePrediction> predictions = [];
    bool searching = false;
    Timer? debounce;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bg,
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
                    if (label == 'Custom Place') ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: customNameCtrl,
                        style: GoogleFonts.inter(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Enter name for custom place...',
                          labelText: 'Place Name',
                          prefixIcon: const Icon(Icons.edit, size: 20),
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
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextField(
                      controller: searchCtrl,
                      autofocus: label != 'Custom Place',
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
                      onChanged: (q) {
                        if (debounce?.isActive ?? false) debounce!.cancel();
                        if (q.isEmpty) {
                          setSheetState(() => predictions = []);
                          return;
                        }
                        setSheetState(() => searching = true);
                        debounce = Timer(const Duration(milliseconds: 1000), () async {
                          final res = await GoogleMapsService.getPlacePredictions(q);
                          setSheetState(() {
                            predictions = res;
                            searching = false;
                          });
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
                                final detailMap = detail.toMap();
                                if (label == 'Custom Place') {
                                  detailMap['short_name'] = customNameCtrl.text.trim().isEmpty 
                                      ? (detail.shortName.isNotEmpty ? detail.shortName : detail.displayName)
                                      : customNameCtrl.text.trim();
                                  
                                  await FirebaseFirestore.instance
                                      .collection('users')
                                      .doc(uid)
                                      .update({
                                    'savedCustomPlaces': FieldValue.arrayUnion([detailMap])
                                  });
                                } else {
                                  await FirebaseFirestore.instance
                                      .collection('users')
                                      .doc(uid)
                                      .update({firestoreKey: detailMap});
                                }
                                
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
        backgroundColor: AppTheme.bg,
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

  Future<void> _removeCustomPlace(Map<String, dynamic> placeMap) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final label = placeMap['short_name'] ?? 'Custom Place';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bg,
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
          .update({
        'savedCustomPlaces': FieldValue.arrayRemove([placeMap])
      });
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
        title: Text('Profile', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 24, letterSpacing: -0.5, color: AppTheme.text)),
        backgroundColor: AppTheme.bg,
        elevation: 0,
        centerTitle: true,
      ),
      body: uid == null 
          ? const Center(child: Text("Not signed in"))
          : StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                    children: const [
                      SkeletonBox(width: double.infinity, height: 96, borderRadius: 16),
                      SizedBox(height: 24),
                      SkeletonBox(width: 100, height: 16, borderRadius: 4),
                      SizedBox(height: 12),
                      SkeletonBox(width: double.infinity, height: 180, borderRadius: 16),
                      SizedBox(height: 24),
                      SkeletonBox(width: 100, height: 16, borderRadius: 4),
                      SizedBox(height: 12),
                      SkeletonBox(width: double.infinity, height: 140, borderRadius: 16),
                    ],
                  );
                }

                final data = snapshot.data!.data() as Map<String, dynamic>?;
                final name = data?['name'] ?? 'Rider';
                final phone = FirebaseAuth.instance.currentUser?.phoneNumber ?? 'Unknown';
                final createdAt = data?['createdAt'] as Timestamp?;
                final memberSince = createdAt != null ? createdAt.toDate().year.toString() : '2026';
                final totalRides = data?['totalRides'] ?? 0;

                return ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                  children: [
                    // ── Header Profile Info ──
                    Column(
                      children: [
                        const CircleAvatar(
                          radius: 48,
                          backgroundColor: AppTheme.bg2,
                          child: Icon(Icons.person, size: 48, color: AppTheme.text3),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          name,
                          style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w800, color: AppTheme.text),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          phone,
                          style: GoogleFonts.inter(fontSize: 16, color: AppTheme.text2),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: () {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileDetailsScreen()));
                          },
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(140, 40),
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            side: const BorderSide(color: AppTheme.border, width: 1),
                          ),
                          child: Text('Edit Profile', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    
                    // ── Stats ──
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Column(
                          children: [
                            Text(
                              totalRides.toString(),
                              style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w800, color: AppTheme.text),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Total Rides',
                              style: GoogleFonts.inter(fontSize: 13, color: AppTheme.text2),
                            ),
                          ],
                        ),
                        Container(width: 1, height: 40, color: AppTheme.border.withValues(alpha: 0.5)),
                        Column(
                          children: [
                            Text(
                              memberSince,
                              style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w800, color: AppTheme.text),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Member Since',
                              style: GoogleFonts.inter(fontSize: 13, color: AppTheme.text2),
                            ),
                          ],
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 24),
                    _buildSectionTitle('Dashboard'),
                    _buildSettingsGroup(
                      children: [
                        _buildTile(
                          icon: Icons.history,
                          title: 'Ride History',
                          onTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => const RideHistoryScreen()));
                          },
                          showDivider: true,
                        ),
                        _buildTile(
                          icon: Icons.emergency_share_outlined,
                          title: 'Emergency Contacts',
                          onTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => const EmergencyContactsScreen()));
                          },
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 24),
                    _buildSectionTitle('Saved Places'),
                    _buildSavedPlacesSection(data),

                    const SizedBox(height: 24),
                    _buildSectionTitle('Preferences'),
                    _buildSettingsGroup(
                      children: [
                        _buildTile(
                          icon: Icons.settings_outlined,
                          title: 'Settings',
                          onTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
                          },
                          showDivider: true,
                        ),
                        _buildTile(
                          icon: Icons.help_outline,
                          title: 'Help',
                          onTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => const SupportScreen()));
                          },
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
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

  Widget _buildTile({required IconData icon, required String title, required VoidCallback onTap, bool showDivider = false}) {
    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          onTap: onTap,
          leading: Icon(icon, color: AppTheme.text, size: 24),
          title: Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 16, color: AppTheme.text)),
          trailing: const Icon(Icons.chevron_right, color: AppTheme.text3, size: 20),
        ),
        if (showDivider)
          Divider(height: 1, indent: 44, color: AppTheme.border.withValues(alpha: 0.5)),
      ],
    );
  }

  Widget _buildSavedPlacesSection(Map<String, dynamic>? data) {
    final homePlace = data?['savedHome'] as Map<String, dynamic>?;
    final workPlace = data?['savedWork'] as Map<String, dynamic>?;
    final customPlaces = (data?['savedCustomPlaces'] as List<dynamic>?)
        ?.map((e) => e as Map<String, dynamic>)
        .toList() ?? [];

    final children = <Widget>[
      _buildSavedPlaceRow(
        icon: Icons.home_rounded,
        label: 'Home',
        address: homePlace?['short_name'],
        firestoreKey: 'savedHome',
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Divider(color: AppTheme.border.withValues(alpha: 0.5), height: 1, indent: 44),
      ),
      _buildSavedPlaceRow(
        icon: Icons.work_rounded,
        label: 'Work',
        address: workPlace?['short_name'],
        firestoreKey: 'savedWork',
      ),
    ];

    for (var i = 0; i < customPlaces.length; i++) {
      final place = customPlaces[i];
      children.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Divider(color: AppTheme.border.withValues(alpha: 0.5), height: 1, indent: 44),
      ));
      children.add(_buildCustomPlaceRow(place));
    }

    if (customPlaces.length < 5) {
      children.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Divider(color: AppTheme.border.withValues(alpha: 0.5), height: 1, indent: 44),
      ));
      children.add(_buildSavedPlaceRow(
        icon: Icons.star_rounded,
        label: 'Custom Place',
        address: null,
        firestoreKey: 'savedCustomPlaces',
      ));
    }

    return Column(
      children: children,
    );
  }

  Widget _buildCustomPlaceRow(Map<String, dynamic> place) {
    final label = place['short_name'] ?? 'Custom Place';
    final address = place['display_name'] ?? '';

    return InkWell(
      onTap: () {}, // Custom places are added via the bottom sheet, not edited directly once added
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            const Icon(Icons.star_rounded, size: 24, color: AppTheme.text),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.text),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    address,
                    style: GoogleFonts.inter(fontSize: 13, color: AppTheme.text2),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20, color: AppTheme.text3),
              onPressed: () => _removeCustomPlace(place),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
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
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, size: 24, color: isSet ? AppTheme.text : AppTheme.text3),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.text),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isSet ? address : 'Tap to add $label location',
                    style: GoogleFonts.inter(fontSize: 13, color: isSet ? AppTheme.text2 : AppTheme.text3),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (isSet)
              IconButton(
                icon: const Icon(Icons.close, size: 20, color: AppTheme.text3),
                onPressed: () => _removeSavedPlace(firestoreKey, label),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              )
            else
              const Icon(Icons.add, size: 20, color: AppTheme.text),
          ],
        ),
      ),
    );
  }
}

