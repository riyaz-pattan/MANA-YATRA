// lib/presentation/screens/driver_approvals_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/auth_provider.dart';

class DriverApprovalsScreen extends ConsumerStatefulWidget {
  const DriverApprovalsScreen({super.key});

  @override
  ConsumerState<DriverApprovalsScreen> createState() => _DriverApprovalsScreenState();
}

class _DriverApprovalsScreenState extends ConsumerState<DriverApprovalsScreen> {
  Future<void> _updateDriverStatus(String uid, String status) async {
    try {
      await FirebaseFirestore.instance.collection('drivers').doc(uid).update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Driver marked as $status')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update driver: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final bg = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final border = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;
    final text3Color = isDark ? AppTheme.darkText3 : AppTheme.lightText3;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('drivers').where('status', isEqualTo: 'pending_approval').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        
        final drivers = snapshot.data?.docs ?? [];

        if (drivers.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_outline, size: 64, color: AppTheme.success.withValues(alpha: 0.5)),
                const SizedBox(height: 16),
                Text('All caught up!', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: textColor)),
                const SizedBox(height: 8),
                Text('No pending driver approvals right now.', style: GoogleFonts.inter(color: text3Color)),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(24),
          itemCount: drivers.length,
          separatorBuilder: (_, __) => const SizedBox(height: 16),
          itemBuilder: (context, index) {
            final data = drivers[index].data() as Map<String, dynamic>;
            final id = drivers[index].id;
            final name = data['name'] ?? 'Unknown Driver';
            final phone = data['phone'] ?? 'No Phone';
            final vehicleType = data['vehicleType'] ?? 'Auto';

            return Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: border),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: AppTheme.brandBlue.withValues(alpha: 0.1),
                    child: Icon(Icons.person, color: AppTheme.brandBlue, size: 30),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                        const SizedBox(height: 4),
                        Text('$phone • $vehicleType', style: GoogleFonts.inter(color: text3Color)),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _showDocumentDialog(context, id, data, isDark),
                    icon: const Icon(Icons.assignment),
                    label: const Text('Review Docs'),
                    style: OutlinedButton.styleFrom(foregroundColor: textColor, side: BorderSide(color: border)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () => _updateDriverStatus(id, 'approved'),
                    icon: const Icon(Icons.check),
                    label: const Text('Approve'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success, foregroundColor: Colors.white),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showDocumentDialog(BuildContext context, String uid, Map<String, dynamic> data, bool isDark) {
    final bg = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bg,
        title: Text('Driver Documents', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: textColor)),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Aadhar Number: ${data['aadharNumber'] ?? 'Not provided'}', style: TextStyle(color: textColor)),
              const SizedBox(height: 8),
              Text('License Number: ${data['licenseNumber'] ?? 'Not provided'}', style: TextStyle(color: textColor)),
              const SizedBox(height: 8),
              Text('Vehicle RC: ${data['rcNumber'] ?? 'Not provided'}', style: TextStyle(color: textColor)),
              const SizedBox(height: 24),
              const Text('In a production app, actual document image URLs would be rendered here.'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _updateDriverStatus(uid, 'rejected');
            }, 
            child: const Text('Reject Driver', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
  }
}
