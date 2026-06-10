// lib/screens/emergency_contacts_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/theme.dart';
import '../utils/custom_toast.dart';

class EmergencyContactsScreen extends StatefulWidget {
  const EmergencyContactsScreen({super.key});

  @override
  State<EmergencyContactsScreen> createState() => _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState extends State<EmergencyContactsScreen> {
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isAdding = false;

  Future<void> _saveContact({Map<String, dynamic>? oldContact}) async {
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

      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      List contacts = doc.data()?['emergencyContacts'] ?? [];

      if (oldContact != null) {
        final index = contacts.indexWhere((c) => c['phone'] == oldContact['phone'] && c['name'] == oldContact['name']);
        if (index != -1) {
          contacts[index] = newContact;
        } else {
          contacts.add(newContact);
        }
      } else {
        contacts.add(newContact);
      }

      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'emergencyContacts': contacts
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

  Future<void> _removeContact(Map<String, dynamic> contact) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'emergencyContacts': FieldValue.arrayRemove([contact])
      });
      if (mounted) CustomToast.show(context: context, message: 'Contact removed');
    } catch (e) {
      if (mounted) CustomToast.show(context: context, message: 'Failed to remove contact', isError: true);
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
                  onPressed: _isAdding ? null : () => _saveContact(oldContact: contactToEdit),
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

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Text('Emergency Contacts', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 24, letterSpacing: -0.5, color: AppTheme.text)),
        backgroundColor: AppTheme.bg,
        elevation: 0,
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>?;
          final contacts = (data?['emergencyContacts'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];

          if (contacts.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(40.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppTheme.danger.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.emergency_share, size: 48, color: AppTheme.danger),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'No Emergency Contacts',
                      style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Add family or friends who should be notified in case of an emergency.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(color: AppTheme.text3, height: 1.5),
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                      onPressed: () => _showContactBottomSheet(),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Contact'),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 16),
            itemCount: contacts.length,
            separatorBuilder: (_, __) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Divider(height: 1, indent: 72, color: AppTheme.border.withValues(alpha: 0.5)),
            ),
            itemBuilder: (context, index) {
              final contact = contacts[index];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: CircleAvatar(
                  backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                  child: Text(
                    contact['name']?[0] ?? '?',
                    style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold),
                  ),
                ),
                title: Text(
                  contact['name'] ?? 'Unknown',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: AppTheme.text),
                ),
                subtitle: Text(
                  contact['phone'] ?? '',
                  style: GoogleFonts.inter(color: AppTheme.text2, fontSize: 13),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, color: AppTheme.primary, size: 22),
                      onPressed: () => _showContactBottomSheet(contactToEdit: contact),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: AppTheme.danger, size: 22),
                      onPressed: () => _removeContact(contact),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
