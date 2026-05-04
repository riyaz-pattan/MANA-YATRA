// lib/screens/delete_account_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/theme.dart';
import '../utils/custom_toast.dart';
import 'login_screen.dart';

class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final TextEditingController _reasonController = TextEditingController();
  bool _isLoading = false;

  Future<void> _submitDeleteRequest() async {
    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      CustomToast.show(context: context, message: 'Please provide a reason', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('No user logged in');

      // Check if rider document exists to get phone/name details
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final phone = user.phoneNumber ?? userDoc.data()?['phone'] ?? 'Unknown';
      final name = userDoc.data()?['name'] ?? 'Unknown Rider';

      // Save delete request
      await FirebaseFirestore.instance.collection('account_deletion_requests').add({
        'uid': user.uid,
        'phone': phone,
        'name': name,
        'reason': reason,
        'role': 'rider',
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      await FirebaseAuth.instance.signOut();

      if (mounted) {
        CustomToast.show(
          context: context, 
          message: 'Account deletion request submitted successfully. You will be logged out.',
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        CustomToast.show(context: context, message: 'Failed to submit request: $e', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Text('Delete Account', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        backgroundColor: AppTheme.surface,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded, size: 64, color: AppTheme.danger),
            const SizedBox(height: 24),
            Text(
              'We are sorry to see you go',
              style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.text),
            ),
            const SizedBox(height: 16),
            Text(
              'If you delete your account, you will lose access to your ride history, saved places, and all personal data. '
              'This action is irreversible once approved by the admin.',
              style: GoogleFonts.inter(fontSize: 14, color: AppTheme.text2, height: 1.5),
            ),
            const SizedBox(height: 32),
            Text(
              'Reason for leaving (Required)',
              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.text),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _reasonController,
              maxLines: 4,
              maxLength: 500,
              decoration: InputDecoration(
                hintText: 'Please tell us why you are leaving...',
                hintStyle: GoogleFonts.inter(color: AppTheme.text3),
                filled: true,
                fillColor: AppTheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppTheme.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppTheme.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.danger),
                ),
              ),
            ),
            const SizedBox(height: 48),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submitDeleteRequest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.danger,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        'Submit Deletion Request',
                        style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
