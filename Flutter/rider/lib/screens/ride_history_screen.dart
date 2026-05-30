// lib/screens/ride_history_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../utils/pdf_generator.dart';
import '../config/theme.dart';
import '../utils/skeleton.dart';
import '../providers/ride_provider.dart';
import '../services/google_maps_service.dart';
import 'main_screen.dart';

class RideHistoryScreen extends StatefulWidget {
  const RideHistoryScreen({super.key});

  @override
  State<RideHistoryScreen> createState() => _RideHistoryScreenState();
}

class _RideHistoryScreenState extends State<RideHistoryScreen> {
  String _selectedFilter = 'All'; // 'All', 'Completed', 'Cancelled'

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text("Not logged in")));
    }

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Text('Ride History', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        backgroundColor: AppTheme.surface,
        elevation: 0,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filters
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                _buildFilterChip('All'),
                const SizedBox(width: 8),
                _buildFilterChip('Completed'),
                const SizedBox(width: 8),
                _buildFilterChip('Cancelled'),
              ],
            ),
          ),
          
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('rides')
                  .where('riderId', isEqualTo: user.uid)
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

                var docs = snapshot.data?.docs.toList() ?? [];
                
                // Filter locally
                if (_selectedFilter != 'All') {
                  docs = docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final status = data['status']?.toString().toLowerCase() ?? '';
                    if (_selectedFilter == 'Completed') {
                      return status == 'completed';
                    } else if (_selectedFilter == 'Cancelled') {
                      return status == 'cancelled' || status == 'declined';
                    }
                    return true;
                  }).toList();
                }

                // Sort locally to avoid needing a composite index
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

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final ride = docs[index].data() as Map<String, dynamic>;
                    return _buildRideCard(ride);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    final isSelected = _selectedFilter == label;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedFilter = label;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary : AppTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? AppTheme.primary : AppTheme.border),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected ? Colors.black : AppTheme.text2,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.history, size: 64, color: AppTheme.text3),
          const SizedBox(height: 16),
          Text(
            'No rides found',
            style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.text2),
          ),
          const SizedBox(height: 8),
          Text(
            'Your ride history will appear here.',
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
    final vehicleType = ride['vehicleType'] ?? 'Unknown';
    
    final distance = ride['distanceKm']?.toStringAsFixed(1) ?? '0.0';
    final duration = ride['durationMin']?.toString() ?? '0';
    final driverName = ride['driverName'] ?? 'Unknown Driver';
    final vehicleNumber = ride['vehicleNumber'] ?? '';
    final status = ride['status']?.toString().toLowerCase() ?? '';

    final bool isCancelled = status == 'cancelled' || status == 'declined';
    final Color statusColor = isCancelled ? AppTheme.danger : AppTheme.success;

    final pLat = (ride['pickup']?['lat'] as num?)?.toDouble() ?? 0.0;
    final pLng = (ride['pickup']?['lng'] as num?)?.toDouble() ?? 0.0;
    final dLat = (ride['drop']?['lat'] as num?)?.toDouble() ?? 0.0;
    final dLng = (ride['drop']?['lng'] as num?)?.toDouble() ?? 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
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
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isCancelled ? 'Cancelled' : '₹$fare',
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: statusColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!isCancelled) ...[
            Row(
              children: [
                Icon(Icons.person, size: 16, color: AppTheme.text2),
                const SizedBox(width: 6),
                Text(
                  driverName,
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.text),
                ),
                if (vehicleNumber.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.border,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      vehicleNumber,
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.text2),
                    ),
                  ),
                ]
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
          ],
          _buildLocationRow(Icons.my_location, AppTheme.primary, pickup.toString()),
          const SizedBox(height: 16),
          _buildLocationRow(Icons.location_on, AppTheme.danger, dropoff.toString()),
          const SizedBox(height: 16),
          if (ride['pickup'] != null && ride['drop'] != null && pLat != 0.0 && dLat != 0.0)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 120,
                width: double.infinity,
                child: IgnorePointer(
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: LatLng(
                        (pLat + dLat) / 2,
                        (pLng + dLng) / 2,
                      ),
                      zoom: 12,
                    ),
                    liteModeEnabled: true,
                    zoomControlsEnabled: false,
                    myLocationButtonEnabled: false,
                    mapToolbarEnabled: false,
                    markers: {
                      Marker(markerId: const MarkerId('pickup'), position: LatLng(pLat, pLng)),
                      Marker(markerId: const MarkerId('drop'), position: LatLng(dLat, dLng)),
                    },
                    polylines: {
                      Polyline(
                        polylineId: const PolylineId('route'),
                        points: [LatLng(pLat, pLng), LatLng(dLat, dLng)],
                        color: AppTheme.primary,
                        width: 4,
                      ),
                    },
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),
          const Divider(color: AppTheme.border, height: 1),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.start,
            children: [
              _buildActionButton(Icons.refresh, 'Ride Again', () => _rideAgain(ride)),
              if (!isCancelled) _buildActionButton(Icons.receipt_long, 'Receipt', () => PdfGenerator.generateAndPrintReceipt(ride)),
              _buildActionButton(Icons.support_agent, 'Support', () => _reportIssue(ride)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, VoidCallback onTap) {
    return ActionChip(
      backgroundColor: AppTheme.bg2,
      side: const BorderSide(color: AppTheme.border),
      avatar: Icon(icon, size: 16, color: AppTheme.text2),
      label: Text(label, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.text2)),
      onPressed: onTap,
    );
  }

  void _rideAgain(Map<String, dynamic> ride) {
    if (ride['pickup'] == null || ride['drop'] == null) return;
    
    final provider = context.read<RideProvider>();
    final pLat = (ride['pickup']['lat'] as num).toDouble();
    final pLng = (ride['pickup']['lng'] as num).toDouble();
    final dLat = (ride['drop']['lat'] as num).toDouble();
    final dLng = (ride['drop']['lng'] as num).toDouble();
    final pName = ride['pickup']['display_name'] ?? ride['pickup']['short_name'] ?? '';
    final dName = ride['drop']['display_name'] ?? ride['drop']['short_name'] ?? '';
    
    provider.setPickup(LocationResult(
      lat: pLat, 
      lng: pLng, 
      displayName: pName,
      shortName: pName,
      placeId: ride['pickup']['place_id'] ?? 'unknown',
    ));
    provider.setDrop(LocationResult(
      lat: dLat, 
      lng: dLng, 
      displayName: dName,
      shortName: dName,
      placeId: ride['drop']['place_id'] ?? 'unknown',
    ));
    
    // Switch to Home tab
    mainScreenKey.currentState?.switchTab(0);
    
    // If we're pushed on top (e.g., from ProfileScreen), pop until we see MainScreen
    if (Navigator.canPop(context)) {
      Navigator.popUntil(context, (route) => route.isFirst);
    }
  }

  void _reportIssue(Map<String, dynamic> ride) {
    final rideId = ride['id'] ?? 'Unknown';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('Report an Issue', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        content: Text('Do you need help with ride $rideId?', style: GoogleFonts.inter(color: AppTheme.text2)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.text3)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              // Open support modal/screen
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            child: Text('Contact Support', style: GoogleFonts.inter(color: Colors.black)),
          ),
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
