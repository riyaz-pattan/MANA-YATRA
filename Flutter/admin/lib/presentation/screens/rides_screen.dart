// lib/presentation/screens/rides_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/auth_provider.dart';
import '../widgets/ride_live_map.dart';
import 'ride_pdf_export.dart';

// Provider to manage the selected tab (Live vs History)
final rideTabProvider = StateProvider<String>((ref) => 'live');

// Provider for the currently selected active ride (for map view)
final selectedRideProvider = StateProvider<String?>((ref) => null);

class RidesScreen extends ConsumerStatefulWidget {
  const RidesScreen({super.key});

  @override
  ConsumerState<RidesScreen> createState() => _RidesScreenState();
}

class _RidesScreenState extends ConsumerState<RidesScreen> {
  static const int _limit = 20;

  // History Pagination State
  List<DocumentSnapshot> _historyRides = [];
  bool _isLoadingHistory = false;
  bool _hasMoreHistory = true;
  DocumentSnapshot? _lastHistoryDoc;
  String _searchQuery = '';
  Set<String> _selectedRideIds = {};

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchHistory({bool loadMore = false}) async {
    if (_isLoadingHistory) return;
    if (loadMore && !_hasMoreHistory) return;

    setState(() => _isLoadingHistory = true);

    try {
      Query q = FirebaseFirestore.instance.collection('rides');

      if (_searchQuery.isNotEmpty) {
        // Simple prefix search for Ride ID (document ID is not queryable via range, but maybe riderId or driverName)
        // Wait, Firestore doesn't allow searching by document ID using >= / <= easily unless using __name__.
        // Since we want to search by Ride ID, we can do exactly that if we use __name__
        q = q
            .where(FieldPath.documentId, isGreaterThanOrEqualTo: _searchQuery)
            .where(FieldPath.documentId, isLessThanOrEqualTo: '$_searchQuery\uf8ff');
      } else {
        q = q
            .where('status', whereIn: ['completed', 'cancelled'])
            .orderBy('createdAt', descending: true);
      }

      q = q.limit(_limit);

      if (loadMore && _lastHistoryDoc != null) {
        q = q.startAfterDocument(_lastHistoryDoc!);
      }

      final snap = await q.get();

      setState(() {
        if (loadMore) {
          _historyRides.addAll(snap.docs);
        } else {
          _historyRides = snap.docs;
        }
        _hasMoreHistory = snap.docs.length == _limit;
        if (snap.docs.isNotEmpty) {
          _lastHistoryDoc = snap.docs.last;
        }
        _isLoadingHistory = false;
      });
    } catch (e) {
      debugPrint('Error fetching history: $e');
      setState(() => _isLoadingHistory = false);
    }
  }

  void _onSearchChanged(String val) {
    setState(() {
      _searchQuery = val.trim();
      _historyRides.clear();
      _lastHistoryDoc = null;
      _hasMoreHistory = true;
      _selectedRideIds.clear();
    });
    _fetchHistory();
  }

  Future<void> _exportData() async {
    if (_selectedRideIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No rides selected to export')));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Generating PDF...')));
    
    final selectedDocs = _historyRides.where((d) => _selectedRideIds.contains(d.id)).toList();
    final ridesData = selectedDocs.map((d) => d.data() as Map<String, dynamic>).toList();
    final ridesIds = selectedDocs.map((d) => d.id).toList();

    await RidePdfExport.generateAndPrint(ridesData, ridesIds);
  }

  Future<void> _forceCancelRide(String rideId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Force Cancel Ride?'),
        content: const Text('This will cancel the ride immediately. Use this only if the driver/rider apps are stuck.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger, foregroundColor: Colors.white),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance.collection('rides').doc(rideId).update({
        'status': 'cancelled',
        'cancelReason': 'Admin Force Cancellation',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ref.read(selectedRideProvider.notifier).state = null;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ride cancelled successfully.')));
      }
    }
  }

  void _showRideDetailsModal(String id, Map<String, dynamic> data, bool isDark) {
    showDialog(
      context: context,
      builder: (context) {
        final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;
        final text2Color = isDark ? AppTheme.darkText2 : AppTheme.lightText2;
        final bgColor = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
        
        final createdAt = data['createdAt'] as Timestamp?;
        final updatedAt = data['updatedAt'] as Timestamp?;
        final status = data['status'] ?? 'unknown';
        final driverName = data['driverName'] ?? 'No Driver';
        final riderId = data['riderId'] ?? '';
        final driverId = data['driverId'] ?? '';
        final fare = data['finalPrice']?.toString() ?? '0';

        return Dialog(
          backgroundColor: bgColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: 500,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Ride Details', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: textColor)),
                    IconButton(icon: Icon(Icons.close, color: textColor), onPressed: () => Navigator.pop(context)),
                  ],
                ),
                const Divider(),
                const SizedBox(height: 16),
                
                // Timeline
                Text('Timeline', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: text2Color)),
                const SizedBox(height: 8),
                _buildTimelineRow('Created', createdAt, textColor),
                _buildTimelineRow('Last Updated', updatedAt, textColor),
                const SizedBox(height: 16),

                // Participants
                Text('Participants', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: text2Color)),
                const SizedBox(height: 8),
                ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text('Rider ID: $riderId', style: TextStyle(color: textColor, fontSize: 13)),
                  trailing: IconButton(icon: const Icon(Icons.open_in_new, size: 18), onPressed: () {
                    Navigator.pop(context);
                    if (riderId.isNotEmpty) context.push('/rider/$riderId');
                  }),
                ),
                ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.local_taxi)),
                  title: Text('Driver: $driverName', style: TextStyle(color: textColor, fontSize: 13)),
                  subtitle: Text(driverId, style: TextStyle(color: text2Color, fontSize: 11)),
                  trailing: IconButton(icon: const Icon(Icons.open_in_new, size: 18), onPressed: () {
                    Navigator.pop(context);
                    if (driverId.isNotEmpty) context.push('/driver/$driverId');
                  }),
                ),
                const SizedBox(height: 16),

                // Fare
                Text('Financials', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: text2Color)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Status', style: TextStyle(color: textColor)),
                    Text(status.toUpperCase(), style: TextStyle(fontWeight: FontWeight.bold, color: status == 'completed' ? AppTheme.success : AppTheme.danger)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total Fare', style: TextStyle(color: textColor)),
                    Text('₹$fare', style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTimelineRow(String label, Timestamp? time, Color textColor) {
    if (time == null) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: textColor, fontSize: 14)),
          Text(DateFormat('MMM dd, yyyy HH:mm:ss').format(time.toDate()), style: TextStyle(color: textColor, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final tab = ref.watch(rideTabProvider);
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 1024;

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
                'Ride Management',
                style: GoogleFonts.inter(
                  fontSize: isDesktop ? 24 : 20,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppTheme.darkText : AppTheme.lightText,
                ),
              ),
              if (_selectedRideIds.isNotEmpty)
                Row(
                  children: [
                    Text(
                      '${_selectedRideIds.length} selected',
                      style: TextStyle(
                        color: isDark ? AppTheme.darkText2 : AppTheme.lightText2,
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: _exportData,
                      icon: const Icon(Icons.picture_as_pdf, size: 16),
                      label: const Text('Save to PDF'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.brandBlue,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 40),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Tabs (Wrapped for Mobile) ──
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _TabButton(
                label: 'Live / Active Rides',
                isActive: tab == 'live',
                onTap: () => ref.read(rideTabProvider.notifier).state = 'live',
                icon: Icons.route,
              ),
              _TabButton(
                label: 'Ride History',
                isActive: tab == 'history',
                onTap: () => ref.read(rideTabProvider.notifier).state = 'history',
                icon: Icons.history,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Content ──
          if (tab == 'live') _buildLiveLayout(context, ref, isDark, isDesktop),
          if (tab == 'history') _buildHistoryLayout(context, ref, isDark, isDesktop),
        ],
      ),
    );
  }

  Widget _buildLiveLayout(BuildContext context, WidgetRef ref, bool isDark, bool isDesktop) {
    final activeRideId = ref.watch(selectedRideProvider);

    return SizedBox(
      height: 600, // Fixed height for split view
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: Active Rides List
          Expanded(
            flex: 4,
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Ongoing Rides', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: isDark ? AppTheme.darkText : AppTheme.lightText)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('rides')
                          .where('status', whereIn: ['searching', 'bidding', 'matched', 'started'])
                          .orderBy('createdAt', descending: true)
                          .snapshots(),
                      builder: (context, snap) {
                        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                        final rides = snap.data!.docs;
                        
                        if (rides.isEmpty) {
                          return Center(child: Text('No active rides currently.', style: TextStyle(color: isDark ? AppTheme.darkText3 : AppTheme.lightText3)));
                        }

                        // Auto-select first ride if none selected
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          final selected = ref.read(selectedRideProvider);
                          if (selected == null && rides.isNotEmpty) {
                            ref.read(selectedRideProvider.notifier).state = rides.first.id;
                          }
                        });

                        return ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: rides.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final doc = rides[index];
                            final data = doc.data() as Map<String, dynamic>;
                            final isSelected = activeRideId == doc.id;
                            return _LiveRideCard(
                              id: doc.id,
                              data: data,
                              isSelected: isSelected,
                              isDark: isDark,
                              onTap: () => ref.read(selectedRideProvider.notifier).state = doc.id,
                              onCancel: () => _forceCancelRide(doc.id),
                              onInfo: () => _showRideDetailsModal(doc.id, data, isDark),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (isDesktop) const SizedBox(width: 24),

          // Right: Adaptive Live Map
          if (isDesktop)
            Expanded(
              flex: 6,
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    children: [
                      // Render Map Stream
                      if (activeRideId != null)
                        StreamBuilder<DocumentSnapshot>(
                          stream: FirebaseFirestore.instance.collection('rides').doc(activeRideId).snapshots(),
                          builder: (context, snap) {
                            if (!snap.hasData || !snap.data!.exists) {
                              return const Center(child: Text('Ride not found.'));
                            }
                            final data = snap.data!.data() as Map<String, dynamic>;
                            final status = data['status'] as String? ?? '';
                            
                            // If the ride was cancelled or completed, clear the map selection
                            if (status == 'cancelled' || status == 'completed') {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (ref.read(selectedRideProvider) == activeRideId) {
                                  ref.read(selectedRideProvider.notifier).state = null;
                                }
                              });
                              return Center(
                                child: Text(
                                  'Ride was $status. Select another live ride.', 
                                  style: TextStyle(color: isDark ? AppTheme.darkText2 : AppTheme.lightText2),
                                ),
                              );
                            }
                            
                            return RideLiveMap(
                              rideData: data,
                              isDark: isDark,
                            );
                          },
                        )
                      else
                        Center(child: Text('Select a live ride from the list to track its location.', style: TextStyle(color: isDark ? AppTheme.darkText2 : AppTheme.lightText2))),
                      
                      if (activeRideId != null)
                        Positioned(
                          top: 16, right: 16,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppTheme.success, shape: BoxShape.circle)),
                                const SizedBox(width: 8),
                                Text('Live Tracking Active', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? AppTheme.darkText : AppTheme.lightText)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHistoryLayout(BuildContext context, WidgetRef ref, bool isDark, bool isDesktop) {
    final width = MediaQuery.of(context).size.width;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search Bar
        SizedBox(
          width: isDesktop ? 300 : double.infinity,
          child: TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText),
            decoration: InputDecoration(
              hintText: 'Search Ride ID...',
              hintStyle: TextStyle(color: isDark ? AppTheme.darkText2 : AppTheme.lightText2),
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Data Table
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DataTable(
                      headingRowColor: WidgetStateProperty.all(isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2),
                      dataRowMinHeight: 64,
                      dataRowMaxHeight: 64,
                      columns: const [
                        DataColumn(label: Text('')), // Checkbox
                        DataColumn(label: Text('Date & Time')),
                        DataColumn(label: Text('Ride ID')),
                        DataColumn(label: Text('Rider / Driver')),
                        DataColumn(label: Text('Route')),
                        DataColumn(label: Text('Status')),
                        DataColumn(label: Text('Fare')),
                        DataColumn(label: Text('Actions')),
                      ],
                      rows: _historyRides.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        return _buildHistoryDataRow(doc.id, data, isDark);
                      }).toList(),
                    ),
                    if (_isLoadingHistory)
                      const Padding(
                        padding: EdgeInsets.all(32.0),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    if (!_isLoadingHistory && _historyRides.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Center(
                          child: Text('No ride history found.', style: TextStyle(color: isDark ? AppTheme.darkText2 : AppTheme.lightText2)),
                        ),
                      ),
                    if (!_isLoadingHistory && _hasMoreHistory)
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Center(
                          child: TextButton(
                            onPressed: () => _fetchHistory(loadMore: true),
                            child: const Text('Load More'),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  DataRow _buildHistoryDataRow(String id, Map<String, dynamic> data, bool isDark) {
    final createdAt = data['createdAt'] as Timestamp?;
    final dateStr = createdAt != null 
        ? DateFormat('MMM dd, HH:mm').format(createdAt.toDate())
        : 'Unknown';
    
    final driverName = data['driverName'] ?? 'No Driver';
    final riderId = (data['riderId'] ?? '').toString();
    final pickup = data['pickup']?['short_name'] ?? 'Unknown';
    final drop = data['drop']?['short_name'] ?? 'Unknown';
    final status = data['status'] ?? 'unknown';
    final fare = data['finalPrice']?.toString() ?? '-';

    final isCompleted = status == 'completed';
    final statusColor = isCompleted ? AppTheme.success : AppTheme.danger;

    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;
    final text2Color = isDark ? AppTheme.darkText2 : AppTheme.lightText2;

    return DataRow(
      cells: [
        DataCell(Checkbox(
          value: _selectedRideIds.contains(id),
          onChanged: (val) {
            setState(() {
              if (val == true) _selectedRideIds.add(id);
              else _selectedRideIds.remove(id);
            });
          },
        )),
        DataCell(Text(dateStr, style: GoogleFonts.inter(color: text2Color, fontSize: 13))),
        DataCell(Text(id.substring(0, 8).toUpperCase(), style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600, color: textColor))),
        DataCell(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('D: $driverName', style: GoogleFonts.inter(fontWeight: FontWeight.w500, color: textColor, fontSize: 13)),
            Text('R: ...${riderId.length > 4 ? riderId.substring(riderId.length - 4) : riderId}', style: GoogleFonts.inter(color: text2Color, fontSize: 12)),
          ],
        )),
        DataCell(SizedBox(
          width: 160,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(children: [
                const Icon(Icons.circle, size: 8, color: AppTheme.success),
                const SizedBox(width: 4),
                Flexible(child: Text(pickup, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 12, color: textColor))),
              ]),
              const SizedBox(height: 2),
              Row(children: [
                const Icon(Icons.location_on, size: 8, color: AppTheme.danger),
                const SizedBox(width: 4),
                Flexible(child: Text(drop, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 12, color: textColor))),
              ]),
            ],
          ),
        )),
        DataCell(Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
          child: Text(status.toUpperCase(), style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: statusColor)),
        )),
        DataCell(Text(isCompleted ? '₹$fare' : '₹0', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: textColor))),
        DataCell(IconButton(
          icon: const Icon(Icons.receipt_long, size: 20),
          color: AppTheme.info,
          tooltip: 'View Details',
          onPressed: () => _showRideDetailsModal(id, data, isDark),
        )),
      ],
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final IconData icon;

  const _TabButton({required this.label, required this.isActive, required this.onTap, required this.icon});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.brandBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isActive ? AppTheme.brandBlue : AppTheme.brandBlue.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: isActive ? Colors.white : AppTheme.brandBlue),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color: isActive ? Colors.white : AppTheme.brandBlue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveRideCard extends StatelessWidget {
  final String id;
  final Map<String, dynamic> data;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onCancel;
  final VoidCallback onInfo;

  const _LiveRideCard({
    required this.id, 
    required this.data, 
    required this.isSelected, 
    required this.isDark, 
    required this.onTap,
    required this.onCancel,
    required this.onInfo,
  });

  @override
  Widget build(BuildContext context) {
    final status = data['status'] ?? 'unknown';
    final pickup = data['pickup']?['short_name'] ?? 'Unknown';
    final drop = data['drop']?['short_name'] ?? 'Unknown';
    final fare = data['finalPrice']?.toString() ?? data['riderBid']?.toString() ?? '-';

    Color statusColor = AppTheme.info;
    if (status == 'searching' || status == 'bidding') statusColor = AppTheme.warning;
    if (status == 'started') statusColor = AppTheme.success;

    final bgColor = isSelected
        ? (isDark ? AppTheme.brandBlue.withValues(alpha: 0.15) : AppTheme.brandBlue.withValues(alpha: 0.08))
        : (isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2);
    final borderColor = isSelected ? AppTheme.brandBlue : Colors.transparent;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('ID: ${id.substring(0, 8).toUpperCase()}', style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: isDark ? AppTheme.darkText3 : AppTheme.lightText3)),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                      child: Text(status.toUpperCase(), style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: statusColor)),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: onInfo,
                      child: const Icon(Icons.info_outline, size: 20, color: AppTheme.brandBlue),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.circle, size: 10, color: AppTheme.success),
                const SizedBox(width: 8),
                Expanded(child: Text(pickup, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: isDark ? AppTheme.darkText : AppTheme.lightText))),
              ],
            ),
            Container(
              margin: const EdgeInsets.only(left: 4, top: 4, bottom: 4),
              height: 12,
              width: 2,
              color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
            ),
            Row(
              children: [
                const Icon(Icons.location_on, size: 12, color: AppTheme.danger),
                const SizedBox(width: 6),
                Expanded(child: Text(drop, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: isDark ? AppTheme.darkText : AppTheme.lightText))),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Fare: ₹$fare', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.success)),
                // Force Cancel Button
                TextButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.cancel, size: 16),
                  label: const Text('Force Cancel'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.danger,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
