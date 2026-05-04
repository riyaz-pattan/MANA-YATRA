// lib/screens/rides_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/theme.dart';

class RidesScreen extends StatefulWidget {
  const RidesScreen({super.key});
  @override
  State<RidesScreen> createState() => _RidesScreenState();
}

class _RidesScreenState extends State<RidesScreen> {
  String _filter = 'active';

  @override
  Widget build(BuildContext context) {
    final statuses = _filter == 'active'
        ? ['searching', 'bidding', 'matched', 'started']
        : ['completed', 'cancelled'];

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('rides')
          .where('status', whereIn: statuses)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
        }
        final rides = snap.data!.docs.map((d) {
          final data = d.data() as Map<String, dynamic>;
          data['id'] = d.id;
          return data;
        }).toList();

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('🚗 Rides', style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('Monitor all ride activity', style: GoogleFonts.inter(fontSize: 14, color: AppTheme.text3)),
              const SizedBox(height: 20),
              Row(
                children: ['active', 'history'].map((f) {
                  final sel = _filter == f;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _filter = f),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: sel ? AppTheme.primary : AppTheme.surface,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(f == 'active' ? 'Active / Live' : 'History',
                            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: sel ? Colors.white : AppTheme.text2)),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              ...rides.map((ride) {
                final status = ride['status'] ?? '';
                final sColor = status == 'completed' ? AppTheme.text3 : status == 'cancelled' ? AppTheme.danger : status == 'started' ? AppTheme.success : AppTheme.warning;
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
                  child: Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(ride['id'].toString().substring(0, 8), style: const TextStyle(color: AppTheme.text3, fontSize: 11, fontFamily: 'monospace')),
                      const SizedBox(height: 4),
                      Text(ride['pickup']?['short_name'] ?? '—', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14)),
                      Text('→ ${ride['drop']?['short_name'] ?? '—'}', style: GoogleFonts.inter(color: AppTheme.text3, fontSize: 12)),
                    ])),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: sColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                        child: Text(status, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: sColor))),
                      const SizedBox(height: 6),
                      Text('₹${ride['finalPrice'] ?? ride['riderBid'] ?? '—'}', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: ride['finalPrice'] != null ? AppTheme.success : AppTheme.text3)),
                    ]),
                  ]),
                );
              }),
              if (rides.isEmpty) Center(child: Padding(padding: const EdgeInsets.all(40), child: Text('No rides found', style: GoogleFonts.inter(color: AppTheme.text3)))),
            ],
          ),
        );
      },
    );
  }
}
