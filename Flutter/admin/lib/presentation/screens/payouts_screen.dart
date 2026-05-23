// lib/presentation/screens/payouts_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/auth_provider.dart';

class PayoutsScreen extends ConsumerStatefulWidget {
  const PayoutsScreen({super.key});

  @override
  ConsumerState<PayoutsScreen> createState() => _PayoutsScreenState();
}

class _PayoutsScreenState extends ConsumerState<PayoutsScreen> {
  Future<void> _processPayout(String id, String status) async {
    try {
      await FirebaseFirestore.instance.collection('payout_requests').doc(id).update({
        'status': status,
        'processedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Payout marked as $status')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to process payout: $e'), backgroundColor: AppTheme.danger),
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
      stream: FirebaseFirestore.instance.collection('payout_requests').where('status', isEqualTo: 'pending').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        
        final requests = snapshot.data?.docs ?? [];

        if (requests.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.account_balance_wallet_outlined, size: 64, color: AppTheme.brandBlue.withValues(alpha: 0.5)),
                const SizedBox(height: 16),
                Text('No Pending Payouts', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: textColor)),
                const SizedBox(height: 8),
                Text('All driver withdrawal requests have been processed.', style: GoogleFonts.inter(color: text3Color)),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(24),
          itemCount: requests.length,
          separatorBuilder: (_, __) => const SizedBox(height: 16),
          itemBuilder: (context, index) {
            final data = requests[index].data() as Map<String, dynamic>;
            final id = requests[index].id;
            final driverName = data['driverName'] ?? 'Unknown Driver';
            final amount = data['amount'] ?? 0;
            final bankDetails = data['bankDetails'] ?? 'No bank info provided';
            final timestamp = data['createdAt'] as Timestamp?;
            final dateStr = timestamp != null ? DateFormat('MMM d, y, h:mm a').format(timestamp.toDate()) : 'Unknown Date';

            return Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: border),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.currency_rupee, color: AppTheme.warning),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(driverName, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: textColor)),
                            const SizedBox(width: 8),
                            Text('requested ₹$amount', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.success)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(dateStr, style: GoogleFonts.inter(fontSize: 12, color: text3Color)),
                        const SizedBox(height: 8),
                        Text('Bank: $bankDetails', style: GoogleFonts.inter(fontSize: 13, color: isDark ? AppTheme.darkText2 : AppTheme.lightText2)),
                      ],
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () => _processPayout(id, 'rejected'),
                    style: OutlinedButton.styleFrom(foregroundColor: AppTheme.danger, side: const BorderSide(color: AppTheme.danger)),
                    child: const Text('Reject'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () => _processPayout(id, 'paid'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success, foregroundColor: Colors.white),
                    child: const Text('Mark Paid'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
