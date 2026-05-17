// lib/screens/ride_earnings_history_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/theme.dart';
import '../utils/skeleton.dart';

class RideEarningsHistoryScreen extends StatelessWidget {
  const RideEarningsHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text("Not logged in")));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Earnings History', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        backgroundColor: AppTheme.surface,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('rides')
            .where('driverId', isEqualTo: user.uid)
            .where('status', isEqualTo: 'completed')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: 4,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, __) => const RideHistoryCardSkeleton(),
            );
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error loading history: ${snapshot.error}'));
          }

          final docs = snapshot.data?.docs.toList() ?? [];
          
          docs.sort((a, b) {
             final aData = a.data() as Map<String, dynamic>;
             final bData = b.data() as Map<String, dynamic>;
             final aTime = (aData['completedAt'] ?? aData['createdAt']) as Timestamp?;
             final bTime = (bData['completedAt'] ?? bData['createdAt']) as Timestamp?;
             if (aTime == null && bTime == null) return 0;
             if (aTime == null) return 1;
             if (bTime == null) return -1;
             return bTime.compareTo(aTime);
          });

          if (docs.isEmpty) {
            return _buildEmptyState();
          }

          double totalEarnings = 0;
          for (var doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            final fareStr = data['finalPrice']?.toString() ?? '0';
            totalEarnings += double.tryParse(fareStr) ?? 0.0;
          }

          return Column(
            children: [
              _buildEarningsSummary(totalEarnings, docs.length),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final ride = docs[index].data() as Map<String, dynamic>;
                    return _buildRideCard(ride);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEarningsSummary(double total, int rides) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Column(
        children: [
          Text(
            'Total Earnings',
            style: GoogleFonts.inter(fontSize: 14, color: AppTheme.text2),
          ),
          const SizedBox(height: 8),
          Text(
            '₹${total.toStringAsFixed(0)}',
            style: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.bold, color: AppTheme.success),
          ),
          const SizedBox(height: 8),
          Text(
            '$rides Rides Completed',
            style: GoogleFonts.inter(fontSize: 14, color: AppTheme.text2),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.account_balance_wallet_outlined, size: 64, color: AppTheme.text3),
          const SizedBox(height: 16),
          Text(
            'No earnings yet',
            style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.text2),
          ),
          const SizedBox(height: 8),
          Text(
            'Complete rides to see your earnings here.',
            style: GoogleFonts.inter(fontSize: 14, color: AppTheme.text3),
          ),
        ],
      ),
    );
  }

  Widget _buildRideCard(Map<String, dynamic> ride) {
    final pickup = ride['pickup'] != null ? (ride['pickup']['display_name'] ?? ride['pickup']['short_name'] ?? 'Unknown Pickup') : 'Unknown Pickup';
    final dropoff = ride['drop'] != null ? (ride['drop']['display_name'] ?? ride['drop']['short_name'] ?? 'Unknown Dropoff') : 'Unknown Dropoff';
    final fare = ride['finalPrice']?.toString() ?? '0';
    final timestamp = (ride['completedAt'] ?? ride['createdAt']) as Timestamp?;
    final date = timestamp != null ? _formatDate(timestamp.toDate()) : 'Unknown Date';
    
    final distance = ride['distanceKm']?.toStringAsFixed(1) ?? '0.0';
    final duration = ride['durationMin']?.toString() ?? '0';
    final vehicleType = ride['vehicleType'] ?? 'Unknown';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                date,
                style: GoogleFonts.inter(fontSize: 14, color: AppTheme.text2, fontWeight: FontWeight.w500),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '+₹$fare',
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.success),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildInfoChip(Icons.electric_rickshaw, vehicleType.toString().toUpperCase()),
              const SizedBox(width: 12),
              _buildInfoChip(Icons.route, '$distance km'),
              const SizedBox(width: 12),
              _buildInfoChip(Icons.schedule, '$duration min'),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: AppTheme.border, height: 1),
          const SizedBox(height: 16),
          _buildLocationRow(Icons.my_location, AppTheme.primary, pickup.toString()),
          const SizedBox(height: 16),
          _buildLocationRow(Icons.location_on, AppTheme.danger, dropoff.toString()),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppTheme.text3),
        const SizedBox(width: 4),
        Text(
          text,
          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.text2),
        ),
      ],
    );
  }

  Widget _buildLocationRow(IconData icon, Color color, String address) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            address,
            style: GoogleFonts.inter(fontSize: 14, color: AppTheme.text),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime dt) {
    return "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }
}
