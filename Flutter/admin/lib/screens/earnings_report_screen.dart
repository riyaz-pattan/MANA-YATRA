// lib/screens/earnings_report_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/theme.dart';

class EarningsReportScreen extends StatelessWidget {
  const EarningsReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('payments')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: AppTheme.primary),
          );
        }

        final payments = snapshot.data!.docs;
        if (payments.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 48,
                  color: AppTheme.text3.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 12),
                Text(
                  'No earnings data available.',
                  style: GoogleFonts.inter(color: AppTheme.text3),
                ),
              ],
            ),
          );
        }

        double totalEarnings = 0;
        for (var doc in payments) {
          final data = doc.data() as Map<String, dynamic>;
          totalEarnings += ((data['amount'] ?? 0) as num).toDouble();
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Earnings Report',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Subscription revenue overview.',
                style: GoogleFonts.inter(fontSize: 13, color: AppTheme.text3),
              ),
              const SizedBox(height: 20),

              // ── Total Earnings Card ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppTheme.success.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      'Total Subscription Earnings',
                      style: GoogleFonts.inter(
                        color: AppTheme.text2,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '₹${totalEarnings.toStringAsFixed(2)}',
                      style: GoogleFonts.inter(
                        color: AppTheme.success,
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              Text(
                'RECENT TRANSACTIONS',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.text3,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 14),

              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: payments.length,
                itemBuilder: (context, index) {
                  final p = payments[index].data() as Map<String, dynamic>;
                  final amount = ((p['amount'] ?? 0) as num).toDouble();
                  final method = p['method'] ?? 'Unknown';
                  final date = p['createdAt'] != null
                      ? (p['createdAt'] as Timestamp)
                          .toDate()
                          .toString()
                          .split(' ')[0]
                      : 'N/A';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.bg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.success.withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.arrow_downward,
                            color: AppTheme.success,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Subscription Fee',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: AppTheme.text,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$method • $date',
                                style: GoogleFonts.inter(
                                  color: AppTheme.text3,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '+₹${amount.toStringAsFixed(0)}',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: AppTheme.success,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
