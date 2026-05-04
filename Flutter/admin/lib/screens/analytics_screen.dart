// lib/screens/analytics_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/theme.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  Map<String, dynamic>? _stats;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final allRides = await FirebaseFirestore.instance.collection('rides').get();
    final completed = await FirebaseFirestore.instance
        .collection('rides')
        .where('status', isEqualTo: 'completed')
        .get();
    final cancelled = await FirebaseFirestore.instance
        .collection('rides')
        .where('status', isEqualTo: 'cancelled')
        .get();
    final allDrivers =
        await FirebaseFirestore.instance.collection('drivers').get();
    final online = await FirebaseFirestore.instance
        .collection('drivers')
        .where('isOnline', isEqualTo: true)
        .get();

    double totalRevenue = 0;
    for (final d in completed.docs) {
      totalRevenue += ((d.data()['finalPrice'] ?? 0) as num).toDouble();
    }

    final approvedCount = allDrivers.docs
        .where((d) => (d.data())['isApproved'] == true)
        .length;

    if (!mounted) return;

    setState(() {
      _stats = {
        'totalRides': allRides.size,
        'completed': completed.size,
        'cancelled': cancelled.size,
        'totalDrivers': allDrivers.size,
        'online': online.size,
        'approved': approvedCount,
        'revenue': totalRevenue,
        'rate': allRides.size > 0
            ? ((completed.size / allRides.size) * 100).toStringAsFixed(1)
            : '0',
      };
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }
    final s = _stats!;
    return RefreshIndicator(
      onRefresh: _loadStats,
      color: AppTheme.primary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Welcome Banner ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome back',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Mana Yatra Admin',
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${s['totalRides']} total rides · ${s['online']} drivers online',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: Colors.white60,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Rides Section ──
            _sectionLabel('Rides'),
            const SizedBox(height: 12),
            Row(
              children: [
                _statCard('Total', '${s['totalRides']}', AppTheme.text),
                const SizedBox(width: 12),
                _statCard('Completed', '${s['completed']}', AppTheme.success),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _statCard('Cancelled', '${s['cancelled']}', AppTheme.danger),
                const SizedBox(width: 12),
                _statCard('Rate', '${s['rate']}%', AppTheme.accent),
              ],
            ),
            const SizedBox(height: 28),

            // ── Drivers Section ──
            _sectionLabel('Drivers'),
            const SizedBox(height: 12),
            Row(
              children: [
                _statCard('Total', '${s['totalDrivers']}', AppTheme.text),
                const SizedBox(width: 12),
                _statCard('Approved', '${s['approved']}', AppTheme.success),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _statCard('Online', '${s['online']}', AppTheme.info),
                const SizedBox(width: 12),
                const Expanded(child: SizedBox()),
              ],
            ),
            const SizedBox(height: 28),

            // ── Revenue Section ──
            _sectionLabel('Revenue'),
            const SizedBox(height: 12),
            Row(
              children: [
                _statCard(
                  'Fare Volume',
                  '₹${(s['revenue'] as double).toStringAsFixed(0)}',
                  AppTheme.success,
                  sub: 'total rider payments',
                ),
                const SizedBox(width: 12),
                _statCard(
                  'Subscription',
                  '₹${(s['approved'] as int) * 15}',
                  AppTheme.warning,
                  sub: '₹15/day × approved',
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: AppTheme.text3,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _statCard(String label, String value, Color color, {String? sub}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppTheme.bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppTheme.text2,
              ),
            ),
            if (sub != null) ...[
              const SizedBox(height: 2),
              Text(
                sub,
                style: GoogleFonts.inter(fontSize: 11, color: AppTheme.text3),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
