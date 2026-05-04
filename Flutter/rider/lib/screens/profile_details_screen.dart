// lib/screens/profile_details_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/theme.dart';
import '../utils/custom_toast.dart';

class ProfileDetailsScreen extends StatefulWidget {
  const ProfileDetailsScreen({super.key});

  @override
  State<ProfileDetailsScreen> createState() => _ProfileDetailsScreenState();
}

class _ProfileDetailsScreenState extends State<ProfileDetailsScreen> {
  String _name = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = doc.data();
    if (mounted) {
      setState(() {
        _name = data?['name'] ?? 'Rider';
        _loading = false;
      });
    }
  }

  Future<void> _editName() async {
    final controller = TextEditingController(text: _name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Edit Name', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.words,
          autofocus: true,
          style: GoogleFonts.inter(fontSize: 16),
          decoration: InputDecoration(
            hintText: 'Enter your full name',
            hintStyle: GoogleFonts.inter(color: AppTheme.text3),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.text3)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            style: ElevatedButton.styleFrom(minimumSize: const Size(80, 40)),
            child: Text('Save', style: GoogleFonts.inter()),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && result != _name) {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await FirebaseFirestore.instance.collection('users').doc(uid).update({'name': result});
      setState(() => _name = result);
      if (mounted) {
        CustomToast.show(context: context, message: 'Name updated');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = FirebaseAuth.instance.currentUser?.phoneNumber ?? 'Unknown';

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Text('Edit Profile', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        backgroundColor: AppTheme.surface,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                
                _buildInfoTile('Full Name', _name, _editName),
                const Divider(height: 1),
                _buildInfoTile('Phone Number', phone, null),
              ],
            ),
    );
  }

  Widget _buildInfoTile(String label, String value, VoidCallback? onTap) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      title: Text(label, style: GoogleFonts.inter(fontSize: 12, color: AppTheme.text3)),
      subtitle: Text(value, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.text)),
      trailing: onTap != null ? const Icon(Icons.edit, size: 18, color: AppTheme.primary) : null,
      onTap: onTap,
    );
  }
}
