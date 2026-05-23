// lib/presentation/screens/rides_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/auth_provider.dart';
import 'package:intl/intl.dart';

// Provider to manage the selected tab (Live vs History)
final rideTabProvider = StateProvider<String>((ref) => 'live');

// Provider for the currently selected active ride (for map view)
final selectedRideProvider = StateProvider<String?>((ref) => null);

class RidesScreen extends ConsumerWidget {
  const RidesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.download, size: 16),
                label: const Text('Export Data'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 40),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Tabs ──
          Row(
            children: [
              _TabButton(
                label: 'Live / Active Rides',
                isActive: tab == 'live',
                onTap: () => ref.read(rideTabProvider.notifier).state = 'live',
                icon: Icons.route,
              ),
              const SizedBox(width: 12),
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
                        Icon(Icons.filter_list, size: 20, color: isDark ? AppTheme.darkText2 : AppTheme.lightText2),
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
                            final isSelected = ref.watch(selectedRideProvider) == doc.id;
                            return _LiveRideCard(
                              id: doc.id,
                              data: data,
                              isSelected: isSelected,
                              isDark: isDark,
                              onTap: () => ref.read(selectedRideProvider.notifier).state = doc.id,
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

          // Right: Map Placeholder
          if (isDesktop)
            Expanded(
              flex: 6,
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                  image: const DecorationImage(
                    image: NetworkImage('https://maps.googleapis.com/maps/api/staticmap?center=17.3850,78.4867&zoom=13&size=800x800&style=feature:all|element:labels.text.fill|color:0x8ec3b9&style=feature:all|element:labels.text.stroke|color:0x1a3646&style=feature:administrative.country|element:geometry.stroke|color:0x4b6878&style=feature:administrative.land_parcel|element:labels.text.fill|color:0x64779e&style=feature:administrative.province|element:geometry.stroke|color:0x4b6878&style=feature:landscape.man_made|element:geometry.stroke|color:0x334e87&style=feature:landscape.natural|element:geometry|color:0x021019&style=feature:poi|element:geometry|color:0x283d6a&style=feature:poi|element:labels.text.fill|color:0x6f9ba5&style=feature:poi|element:labels.text.stroke|color:0x1d2c4d&style=feature:poi.park|element:geometry.fill|color:0x023e58&style=feature:poi.park|element:labels.text.fill|color:0x3C7680&style=feature:road|element:geometry|color:0x304a7d&style=feature:road|element:labels.text.fill|color:0x98a5be&style=feature:road|element:labels.text.stroke|color:0x1d2c4d&style=feature:road.highway|element:geometry|color:0x2c6675&style=feature:road.highway|element:geometry.stroke|color:0x255763&style=feature:road.highway|element:labels.text.fill|color:0xb0d5ce&style=feature:road.highway|element:labels.text.stroke|color:0x023e58&style=feature:transit|element:labels.text.fill|color:0x98a5be&style=feature:transit|element:labels.text.stroke|color:0x1d2c4d&style=feature:transit.line|element:geometry.fill|color:0x283d6a&style=feature:transit.station|element:geometry|color:0x3a4762&style=feature:water|element:geometry|color:0x0e1626&style=feature:water|element:labels.text.fill|color:0x4e6d70&sensor=false'),
                    fit: BoxFit.cover,
                  ),
                ),
                child: Stack(
                  children: [
                    // Simulated overlay for Map view
                    Container(
                      decoration: BoxDecoration(
                        color: isDark ? Colors.black.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
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
        ],
      ),
    );
  }

  Widget _buildHistoryLayout(BuildContext context, WidgetRef ref, bool isDark, bool isDesktop) {
    final width = MediaQuery.of(context).size.width;
    
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('rides')
          .where('status', whereIn: ['completed', 'cancelled'])
          .orderBy('createdAt', descending: true)
          .limit(100)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final rides = snap.data!.docs;

        return Container(
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
                    DataColumn(label: Text('Date & Time')),
                    DataColumn(label: Text('Ride ID')),
                    DataColumn(label: Text('Rider / Driver')),
                    DataColumn(label: Text('Route')),
                    DataColumn(label: Text('Status')),
                    DataColumn(label: Text('Fare')),
                    DataColumn(label: Text('Actions')),
                  ],
                  rows: rides.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return _buildHistoryDataRow(doc.id, data, isDark);
                  }).toList(),
                ),
              ),
            ),
          ),
        );
      },
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
        DataCell(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(children: [
              const Icon(Icons.circle, size: 8, color: AppTheme.success),
              const SizedBox(width: 4),
              Expanded(child: Text(pickup, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 12, color: textColor))),
            ]),
            const SizedBox(height: 2),
            Row(children: [
              const Icon(Icons.location_on, size: 8, color: AppTheme.danger),
              const SizedBox(width: 4),
              Expanded(child: Text(drop, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 12, color: textColor))),
            ]),
          ],
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
          onPressed: () {},
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

  const _LiveRideCard({required this.id, required this.data, required this.isSelected, required this.isDark, required this.onTap});

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
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                  child: Text(status.toUpperCase(), style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: statusColor)),
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
                Icon(Icons.chevron_right, size: 20, color: isDark ? AppTheme.darkText3 : AppTheme.lightText3),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
