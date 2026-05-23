// lib/presentation/screens/earnings_report_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/auth_provider.dart';

class EarningsReportScreen extends ConsumerWidget {
  const EarningsReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 1024;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('payments')
          .orderBy('createdAt', descending: true)
          .limit(100)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Error loading earnings', style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText)),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final payments = snapshot.data!.docs;
        double totalEarnings = 0;
        for (var doc in payments) {
          final data = doc.data() as Map<String, dynamic>;
          totalEarnings += ((data['amount'] ?? 0) as num).toDouble();
        }

        return SingleChildScrollView(
          padding: EdgeInsets.all(isDesktop ? 32 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Financials & Earnings',
                    style: GoogleFonts.inter(
                      fontSize: isDesktop ? 24 : 20,
                      fontWeight: FontWeight.w700,
                      color: isDark ? AppTheme.darkText : AppTheme.lightText,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.download, size: 16),
                    label: const Text('Export Report'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 40),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ── Total Earnings Card ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppTheme.brandTeal, AppTheme.brandBlue],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.brandBlue.withValues(alpha: 0.2),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total Subscription Revenue',
                      style: GoogleFonts.inter(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '₹${totalEarnings.toStringAsFixed(2)}',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              Text(
                'Recent Transactions',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppTheme.darkText : AppTheme.lightText,
                ),
              ),
              const SizedBox(height: 16),

              if (payments.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Text('No transactions yet.', style: GoogleFonts.inter(color: isDark ? AppTheme.darkText3 : AppTheme.lightText3)),
                  ),
                )
              else
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minWidth: width - (isDesktop ? 300 : 32)),
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(
                            isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2,
                          ),
                          dataRowMinHeight: 64,
                          dataRowMaxHeight: 64,
                          columns: const [
                            DataColumn(label: Text('Transaction ID')),
                            DataColumn(label: Text('Date')),
                            DataColumn(label: Text('Type')),
                            DataColumn(label: Text('Method')),
                            DataColumn(label: Text('Status')),
                            DataColumn(label: Text('Amount')),
                          ],
                          rows: payments.map((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            return _buildTransactionRow(doc.id, data, isDark);
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  DataRow _buildTransactionRow(String id, Map<String, dynamic> data, bool isDark) {
    final amount = ((data['amount'] ?? 0) as num).toDouble();
    final method = data['method'] ?? 'UPI';
    final createdAt = data['createdAt'] as Timestamp?;
    final dateStr = createdAt != null 
        ? DateFormat('MMM dd, yyyy HH:mm').format(createdAt.toDate())
        : 'Unknown';

    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;
    final text2Color = isDark ? AppTheme.darkText2 : AppTheme.lightText2;

    return DataRow(
      cells: [
        DataCell(Text(id.substring(0, 10).toUpperCase(), style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600, color: text2Color))),
        DataCell(Text(dateStr, style: GoogleFonts.inter(color: textColor))),
        DataCell(Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: AppTheme.brandBlue.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: const Icon(Icons.subscriptions, size: 14, color: AppTheme.brandBlue),
            ),
            const SizedBox(width: 8),
            Text('Subscription', style: GoogleFonts.inter(fontWeight: FontWeight.w500, color: textColor)),
          ],
        )),
        DataCell(Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2, borderRadius: BorderRadius.circular(4)),
          child: Text(method, style: GoogleFonts.inter(fontSize: 12, color: text2Color)),
        )),
        DataCell(Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: AppTheme.success.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
          child: Text('SUCCESS', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.success)),
        )),
        DataCell(Text('+₹${amount.toStringAsFixed(0)}', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: AppTheme.success, fontSize: 15))),
      ],
    );
  }
}
