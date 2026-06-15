import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/theme.dart';
import '../services/google_maps_service.dart';
import '../utils/custom_toast.dart';
import 'profile_details_screen.dart';
import 'settings_screen.dart';
import 'support_screen.dart';
import '../utils/skeleton.dart';
import 'package:provider/provider.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isPlacesExpanded = false;
  // ── Emergency Contact Logic ────────────────────────────────────
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isAdding = false;

  Future<void> _saveEmergencyContact({Map<String, dynamic>? oldContact}) async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();

    if (name.isEmpty || phone.isEmpty) {
      CustomToast.show(context: context, message: 'Please enter both name and phone', isError: true);
      return;
    }

    // Basic phone validation (at least 10 digits)
    if (phone.replaceAll(RegExp(r'\D'), '').length < 10) {
       CustomToast.show(context: context, message: 'Please enter a valid phone number', isError: true);
       return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _isAdding = true);

    try {
      final newContact = {
        'name': name,
        'phone': phone,
        'addedAt': oldContact?['addedAt'] ?? DateTime.now().toIso8601String(),
      };

      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'emergencyContacts': [newContact]
      });

      _nameController.clear();
      _phoneController.clear();
      if (!mounted) return;
      Navigator.pop(context); // Close the bottom sheet
      CustomToast.show(context: context, message: oldContact == null ? 'Emergency contact added' : 'Emergency contact updated');
    } catch (e) {
      if (!mounted) return;
      CustomToast.show(context: context, message: 'Failed to save contact', isError: true);
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }

  Future<void> _removeEmergencyContact(Map<String, dynamic> contact) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Remove Emergency Contact?',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        content: Text('This will remove your emergency contact.',
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
      try {
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'emergencyContacts': FieldValue.delete()
        });
        if (mounted) CustomToast.show(context: context, message: 'Contact removed');
      } catch (e) {
        if (mounted) CustomToast.show(context: context, message: 'Failed to remove contact', isError: true);
      }
    }
  }

  void _showContactBottomSheet({Map<String, dynamic>? contactToEdit}) {
    if (contactToEdit != null) {
      _nameController.text = contactToEdit['name'] ?? '';
      _phoneController.text = contactToEdit['phone'] ?? '';
    } else {
      _nameController.clear();
      _phoneController.clear();
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                contactToEdit == null ? 'Add Emergency Contact' : 'Edit Emergency Contact',
                style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'This person will be notified when you use the SOS button during a ride.',
                style: GoogleFonts.inter(fontSize: 13, color: AppTheme.text3),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Contact Name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  prefixIcon: Icon(Icons.phone_outlined),
                  hintText: '+91 00000 00000',
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isAdding ? null : () => _saveEmergencyContact(oldContact: contactToEdit),
                  child: _isAdding 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(contactToEdit == null ? 'Save Contact' : 'Update Contact'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
    final userDoc = Provider.of<DocumentSnapshot?>(context);

    Widget content;
    if (uid == null) {
      content = const Center(child: Text("Not signed in"));
    } else if (userDoc == null) {
      content = ListView(
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
    } else {
      final data = userDoc.data() as Map<String, dynamic>?;
      final name = data?['name'] ?? 'Rider';
      final phone = FirebaseAuth.instance.currentUser?.phoneNumber ?? 'Unknown';
      final createdAt = data?['createdAt'] as Timestamp?;
      final memberSince = createdAt != null ? createdAt.toDate().year.toString() : '2026';
      final totalRides = data?['totalRides'] ?? 0;

      content = ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        children: [
          // ── Header Profile Info ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.bg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.border.withValues(alpha: 0.5)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const CircleAvatar(
                  radius: 36,
                  backgroundColor: AppTheme.bg2,
                  child: Icon(Icons.person, size: 36, color: AppTheme.text3),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.text),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        phone,
                        style: GoogleFonts.inter(fontSize: 14, color: AppTheme.text2),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, color: AppTheme.primary),
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                  ),
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileDetailsScreen()));
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          
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
          _buildSectionTitle('Saved Places'),
          _buildSavedPlacesSection(data),

          const SizedBox(height: 24),
          _buildSectionTitle('Emergency Contact'),
          _buildEmergencyContactSection(data),
          
          const SizedBox(height: 24),
        ],
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Text('Profile', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 24, letterSpacing: -0.5, color: AppTheme.text)),
        backgroundColor: AppTheme.bg,
        elevation: 0,
        centerTitle: true,
      ),
      body: content,
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

    for (var i = 0; i < (_isPlacesExpanded ? customPlaces.length : (customPlaces.isNotEmpty ? 1 : 0)); i++) {
      final place = customPlaces[i];
      children.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Divider(color: AppTheme.border.withValues(alpha: 0.5), height: 1, indent: 44),
      ));
      children.add(_buildCustomPlaceRow(place));
    }

    if (customPlaces.isNotEmpty) {
      children.add(
        InkWell(
          onTap: () => setState(() => _isPlacesExpanded = !_isPlacesExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(_isPlacesExpanded ? 'Show Less' : 'Show All Saved Places', style: GoogleFonts.inter(color: AppTheme.primary, fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(width: 4),
                Icon(_isPlacesExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: AppTheme.primary, size: 20),
              ],
            ),
          ),
        ),
      );
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
            Icon(_getIconForPlaceName(label), size: 24, color: AppTheme.text),
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

  Widget _buildEmergencyContactSection(Map<String, dynamic>? data) {
    final contacts = (data?['emergencyContacts'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final contact = contacts.isNotEmpty ? contacts.first : null;

    return InkWell(
      onTap: contact == null ? () => _showContactBottomSheet(contactToEdit: null) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Icon(contact != null ? Icons.emergency_share : Icons.emergency_share_outlined, size: 24, color: contact != null ? AppTheme.danger : AppTheme.text3),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contact?['name'] ?? 'Add Emergency Contact',
                    style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.text),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    contact?['phone'] ?? 'For SOS alerts during a ride',
                    style: GoogleFonts.inter(fontSize: 13, color: contact != null ? AppTheme.text2 : AppTheme.text3),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (contact != null) ...[
              IconButton(
                icon: const Icon(Icons.edit, size: 20, color: AppTheme.primary),
                onPressed: () => _showContactBottomSheet(contactToEdit: contact),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              IconButton(
                icon: const Icon(Icons.delete, size: 20, color: AppTheme.danger),
                onPressed: () => _removeEmergencyContact(contact),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ] else
              const Icon(Icons.add, size: 20, color: AppTheme.text),
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

  IconData _getIconForPlaceName(String name) {
    final lowerName = name.toLowerCase();
    
    // Gym / Fitness
    if (lowerName.contains('gym') || lowerName.contains('fitness') || lowerName.contains('workout') || lowerName.contains('club')) {
      return Icons.fitness_center;
    }
    // Education
    if (lowerName.contains('school') || lowerName.contains('college') || lowerName.contains('university') || lowerName.contains('academy')) {
      return Icons.school;
    }
    // Health / Hospital
    if (lowerName.contains('hospital') || lowerName.contains('clinic') || lowerName.contains('doctor') || lowerName.contains('medical')) {
      return Icons.local_hospital;
    }
    // Food / Cafe
    if (lowerName.contains('cafe') || lowerName.contains('coffee') || lowerName.contains('bakery') || lowerName.contains('starbucks')) {
      return Icons.local_cafe;
    }
    // Restaurant
    if (lowerName.contains('restaurant') || lowerName.contains('food') || lowerName.contains('pizza') || lowerName.contains('burger') || lowerName.contains('hotel') || lowerName.contains('dhaba')) {
      return Icons.restaurant;
    }
    // Shopping / Mall
    if (lowerName.contains('mall') || lowerName.contains('shop') || lowerName.contains('store') || lowerName.contains('market') || lowerName.contains('mart')) {
      return Icons.shopping_bag;
    }
    // Travel / Transport
    if (lowerName.contains('airport') || lowerName.contains('flight')) {
      return Icons.local_airport;
    }
    if (lowerName.contains('station') || lowerName.contains('railway') || lowerName.contains('train')) {
      return Icons.train;
    }
    if (lowerName.contains('bus') || lowerName.contains('stand')) {
      return Icons.directions_bus;
    }
    // Entertainment
    if (lowerName.contains('movie') || lowerName.contains('cinema') || lowerName.contains('theatre') || lowerName.contains('theater')) {
      return Icons.movie;
    }
    if (lowerName.contains('park') || lowerName.contains('garden')) {
      return Icons.park;
    }
    // Work / Office
    if (lowerName.contains('office') || lowerName.contains('work') || lowerName.contains('company') || lowerName.contains('tech')) {
      return Icons.business;
    }
    // Friends / Family
    if (lowerName.contains('friend') || lowerName.contains('mom') || lowerName.contains('dad') || lowerName.contains('brother') || lowerName.contains('sister') || lowerName.contains('uncle') || lowerName.contains('aunt') || lowerName.contains('house')) {
      return Icons.house;
    }
    // Bank / Finance
    if (lowerName.contains('bank') || lowerName.contains('atm')) {
      return Icons.account_balance;
    }
    // Religious
    if (lowerName.contains('temple') || lowerName.contains('church') || lowerName.contains('mosque') || lowerName.contains('mandir') || lowerName.contains('masjid') || lowerName.contains('gurudwara')) {
      return Icons.place; 
    }

    // Default Fallback
    return Icons.star_rounded;
  }
}

