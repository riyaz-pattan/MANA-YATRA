// lib/presentation/screens/account_handling_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/auth_provider.dart';

class AccountHandlingScreen extends ConsumerStatefulWidget {
  const AccountHandlingScreen({super.key});

  @override
  ConsumerState<AccountHandlingScreen> createState() => _AccountHandlingScreenState();
}

class _AccountHandlingScreenState extends ConsumerState<AccountHandlingScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  Future<void> _approveDeletion(String requestId, String uid, String role) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Approve Deletion?', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        content: Text('This will permanently delete the user from Authentication and Firestore. This action cannot be undone.', style: GoogleFonts.inter()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('Approve & Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Processing deletion...')));

    try {
      final callable = _functions.httpsCallable('approveAccountDeletion');
      final result = await callable.call({'requestId': requestId, 'uid': uid, 'role': role});

      if (!mounted) return;

      if (result.data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account successfully deleted.')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete: ${result.data['message']}')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 1024;
    
    final bg = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final border = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;
    final text2Color = isDark ? AppTheme.darkText2 : AppTheme.lightText2;
    final text3Color = isDark ? AppTheme.darkText3 : AppTheme.lightText3;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isDesktop ? 32 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Account Handling', style: GoogleFonts.inter(fontSize: isDesktop ? 24 : 20, fontWeight: FontWeight.w700, color: textColor)),
          const SizedBox(height: 8),
          Text('Manage user account deletion requests.', style: GoogleFonts.inter(fontSize: 14, color: text3Color)),
          const SizedBox(height: 32),

          StreamBuilder<QuerySnapshot>(
            stream: _firestore.collection('account_deletion_requests').where('status', isEqualTo: 'pending').orderBy('createdAt', descending: true).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: AppTheme.danger)));
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 60),
                    child: Column(
                      children: [
                        Icon(Icons.check_circle_outline, size: 64, color: AppTheme.success.withValues(alpha: 0.5)),
                        const SizedBox(height: 16),
                        Text('No pending deletion requests', style: GoogleFonts.inter(fontSize: 16, color: text2Color)),
                      ],
                    ),
                  ),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: docs.length,
                separatorBuilder: (context, index) => const SizedBox(height: 16),
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final requestId = docs[index].id;
                  final uid = data['uid'] ?? '';
                  final name = data['name'] ?? 'Unknown';
                  final phone = data['phone'] ?? 'Unknown';
                  final reason = data['reason'] ?? 'No reason provided';
                  final role = data['role'] ?? 'user';
                  final timestamp = data['createdAt'] as Timestamp?;
                  final date = timestamp?.toDate();

                  return Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: border)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(color: (role == 'driver' ? AppTheme.brandBlue : AppTheme.brandTeal).withValues(alpha: 0.1), shape: BoxShape.circle),
                                  child: Icon(role == 'driver' ? Icons.local_taxi : Icons.person, color: role == 'driver' ? AppTheme.brandBlue : AppTheme.brandTeal, size: 20),
                                ),
                                const SizedBox(width: 16),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(name, style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: textColor)),
                                    const SizedBox(height: 4),
                                    Text(phone, style: GoogleFonts.inter(fontSize: 13, color: text3Color)),
                                  ],
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(color: AppTheme.warning.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                              child: Text('PENDING', style: GoogleFonts.inter(color: AppTheme.warning, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            _buildInfoCol('Role', role.toUpperCase(), Icons.badge_outlined, text2Color, textColor),
                            const SizedBox(width: 40),
                            _buildInfoCol('Requested on', date != null ? DateFormat.yMMMd().format(date) : 'Unknown', Icons.calendar_today_outlined, text2Color, textColor),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(color: isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2, borderRadius: BorderRadius.circular(12)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Reason for deletion', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: text3Color)),
                              const SizedBox(height: 8),
                              Text(reason, style: GoogleFonts.inter(fontSize: 14, color: textColor, fontStyle: FontStyle.italic)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton.icon(
                            onPressed: () => _approveDeletion(requestId, uid, role),
                            icon: const Icon(Icons.delete_forever, size: 18),
                            label: const Text('Approve & Delete'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.danger,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCol(String label, String value, IconData icon, Color text2Color, Color textColor) {
    return Row(
      children: [
        Icon(icon, size: 16, color: text2Color),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: GoogleFonts.inter(color: text2Color, fontSize: 12)),
            const SizedBox(height: 2),
            Text(value, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14, color: textColor)),
          ],
        ),
      ],
    );
  }
}
