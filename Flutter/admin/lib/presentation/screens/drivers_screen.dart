// lib/presentation/screens/drivers_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/auth_provider.dart';

// Provider to manage the selected filter
final driverFilterProvider = StateProvider<String>((ref) => 'all');

class DriversScreen extends ConsumerWidget {
  const DriversScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final filter = ref.watch(driverFilterProvider);
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 1024;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('drivers')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Text('Error loading drivers', style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText)),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final allDrivers = snap.data!.docs;
        
        final pendingCount = allDrivers.where((d) {
          final data = d.data() as Map<String, dynamic>;
          final isAppr = data['isApproved'] == true || data['isApproved'] == 'true';
          final isBlk = data['isBlocked'] == true || data['isBlocked'] == 'true';
          return !isAppr && !isBlk;
        }).length;
        
        final approvedCount = allDrivers.where((d) {
          final data = d.data() as Map<String, dynamic>;
          final isAppr = data['isApproved'] == true || data['isApproved'] == 'true';
          final isBlk = data['isBlocked'] == true || data['isBlocked'] == 'true';
          return isAppr && !isBlk;
        }).length;

        final blockedCount = allDrivers.where((d) {
          final data = d.data() as Map<String, dynamic>;
          return data['isBlocked'] == true || data['isBlocked'] == 'true';
        }).length;

        final filteredDrivers = allDrivers.where((d) {
          final data = d.data() as Map<String, dynamic>;
          final isAppr = data['isApproved'] == true || data['isApproved'] == 'true';
          final isBlk = data['isBlocked'] == true || data['isBlocked'] == 'true';
          if (filter == 'pending') return !isAppr && !isBlk;
          if (filter == 'approved') return isAppr && !isBlk;
          if (filter == 'blocked') return isBlk;
          return true;
        }).toList();

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
                    'Driver Management',
                    style: GoogleFonts.inter(
                      fontSize: isDesktop ? 24 : 20,
                      fontWeight: FontWeight.w700,
                      color: isDark ? AppTheme.darkText : AppTheme.lightText,
                    ),
                  ),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Downloading CSV... (Coming soon on Web)')),
                          );
                        },
                        icon: const Icon(Icons.download, size: 16),
                        label: const Text('Export CSV'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 40),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ── Filter Tabs ──
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _FilterTab(label: 'All', count: allDrivers.length, value: 'all', groupValue: filter),
                    const SizedBox(width: 8),
                    _FilterTab(label: 'Pending Review', count: pendingCount, value: 'pending', groupValue: filter),
                    const SizedBox(width: 8),
                    _FilterTab(label: 'Approved', count: approvedCount, value: 'approved', groupValue: filter),
                    const SizedBox(width: 8),
                    _FilterTab(label: 'Blocked', count: blockedCount, value: 'blocked', groupValue: filter),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── Data Table ──
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
                          DataColumn(label: Text('Driver Info')),
                          DataColumn(label: Text('Vehicle Type')),
                          DataColumn(label: Text('Status')),
                          DataColumn(label: Text('Rating')),
                          DataColumn(label: Text('Rides / Earnings')),
                          DataColumn(label: Text('Actions')),
                        ],
                        rows: filteredDrivers.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          return _buildDataRow(context, doc.id, data, isDark);
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

  DataRow _buildDataRow(BuildContext context, String id, Map<String, dynamic> data, bool isDark) {
    final docs = data['documents'] as Map<String, dynamic>?;
    final selfieUrl = docs?['selfieUrl'] as String?;
    final name = data['name'] ?? 'Unknown';
    final phone = data['phone'] ?? 'No Phone';
    final vehicleType = data['vehicleType'] ?? 'auto';
    final rating = data['rating']?.toString() ?? 'N/A';
    final totalRides = data['totalAssignedRides'] ?? 0;
    final totalEarnings = data['totalEarnings'] ?? 0;

    final isAppr = data['isApproved'] == true || data['isApproved'] == 'true';
    final isBlk = data['isBlocked'] == true || data['isBlocked'] == 'true';

    String status = 'Pending';
    Color statusColor = AppTheme.warning;
    if (isBlk) {
      status = 'Blocked';
      statusColor = AppTheme.danger;
    } else if (isAppr) {
      status = 'Approved';
      statusColor = AppTheme.success;
    }

    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;
    final text2Color = isDark ? AppTheme.darkText2 : AppTheme.lightText2;

    return DataRow(
      cells: [
        // Driver Info
        DataCell(Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2,
              child: (selfieUrl != null && selfieUrl.isNotEmpty)
                  ? ClipOval(
                      child: Image.network(
                        selfieUrl,
                        width: 36,
                        height: 36,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Icon(Icons.person, color: text2Color, size: 20),
                      ),
                    )
                  : Icon(Icons.person, color: text2Color, size: 20),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(name, style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: textColor)),
                Text(phone, style: GoogleFonts.inter(fontSize: 12, color: text2Color)),
              ],
            ),
          ],
        )),
        // Vehicle
        DataCell(Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(vehicleType == 'auto' ? '🛺' : '🏍️', style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 4),
              Text(vehicleType.toUpperCase(), style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: text2Color)),
            ],
          ),
        )),
        // Status
        DataCell(Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            status,
            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor),
          ),
        )),
        // Rating
        DataCell(Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star, color: AppTheme.warning, size: 16),
            const SizedBox(width: 4),
            Text(rating, style: GoogleFonts.inter(fontWeight: FontWeight.w500, color: textColor)),
          ],
        )),
        // Rides / Earnings
        DataCell(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('$totalRides rides', style: GoogleFonts.inter(fontWeight: FontWeight.w500, color: textColor)),
            Text('₹$totalEarnings', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.success)),
          ],
        )),
        // Actions
        DataCell(Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.visibility_outlined, size: 20),
              color: AppTheme.info,
              tooltip: 'View Details',
              onPressed: () {
                // TODO: Open detailed driver view modal
              },
            ),
            if (!isAppr && !isBlk)
              IconButton(
                icon: const Icon(Icons.check_circle_outline, size: 20),
                color: AppTheme.success,
                tooltip: 'Approve',
                onPressed: () {
                  FirebaseFirestore.instance.collection('drivers').doc(id).update({
                    'isApproved': true,
                    'isBlocked': false,
                  });
                },
              ),
            IconButton(
              icon: Icon(isBlk ? Icons.lock_open : Icons.block, size: 20),
              color: isBlk ? AppTheme.success : AppTheme.danger,
              tooltip: isBlk ? 'Unblock' : 'Block',
              onPressed: () {
                FirebaseFirestore.instance.collection('drivers').doc(id).update({
                  'isBlocked': !isBlk,
                  'isOnline': false,
                });
              },
            ),
          ],
        )),
      ],
    );
  }
}

class _FilterTab extends ConsumerWidget {
  final String label;
  final int count;
  final String value;
  final String groupValue;

  const _FilterTab({
    required this.label,
    required this.count,
    required this.value,
    required this.groupValue,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSelected = value == groupValue;
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;

    final bgColor = isSelected
        ? AppTheme.brandBlue
        : (isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2);
    final textColor = isSelected
        ? Colors.white
        : (isDark ? AppTheme.darkText2 : AppTheme.lightText2);
    final countBgColor = isSelected
        ? Colors.white.withValues(alpha: 0.2)
        : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder);

    return InkWell(
      onTap: () => ref.read(driverFilterProvider.notifier).state = value,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: textColor,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: countBgColor,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '$count',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
