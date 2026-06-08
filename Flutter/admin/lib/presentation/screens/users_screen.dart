// lib/presentation/screens/users_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/auth_provider.dart';
import 'rider_pdf_export.dart';

final userFilterProvider = StateProvider<String>((ref) => 'all');
final userSearchProvider = StateProvider<String>((ref) => '');
final selectedRidersProvider = StateProvider<Set<String>>((ref) => {});

class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final filter = ref.watch(userFilterProvider);
    final searchQuery = ref.watch(userSearchProvider).toLowerCase();
    final selectedRiders = ref.watch(selectedRidersProvider);
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 1024;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .orderBy('updatedAt', descending: true)
          .limit(500)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Text('Error loading users', style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText)),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final allUsers = snap.data!.docs;
        int activeCount = 0;
        int blockedCount = 0;

        for (var d in allUsers) {
          final data = d.data() as Map<String, dynamic>;
          final isBlk = data['isBlocked'] == true || data['isBlocked'] == 'true';
          if (!isBlk) activeCount++;
          if (isBlk) blockedCount++;
        }

        final filteredUsers = allUsers.where((d) {
          final data = d.data() as Map<String, dynamic>;
          final isBlk = data['isBlocked'] == true || data['isBlocked'] == 'true';

          bool matchesFilter = true;
          if (filter == 'active') matchesFilter = !isBlk;
          if (filter == 'blocked') matchesFilter = isBlk;

          bool matchesSearch = true;
          if (searchQuery.isNotEmpty) {
            final name = (data['name'] ?? '').toString().toLowerCase();
            final phone = (data['phone'] ?? '').toString().toLowerCase();
            final uid = d.id.toLowerCase();
            matchesSearch = name.contains(searchQuery) || phone.contains(searchQuery) || uid.contains(searchQuery);
          }

          return matchesFilter && matchesSearch;
        }).toList();

        return SingleChildScrollView(
          padding: EdgeInsets.all(isDesktop ? 32 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header & PDF Export ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Rider Management',
                    style: GoogleFonts.inter(
                      fontSize: isDesktop ? 24 : 20,
                      fontWeight: FontWeight.w700,
                      color: isDark ? AppTheme.darkText : AppTheme.lightText,
                    ),
                  ),
                  if (selectedRiders.isNotEmpty)
                    ElevatedButton.icon(
                      onPressed: () async {
                        final selectedData = filteredUsers
                            .where((d) => selectedRiders.contains(d.id))
                            .map((d) => d.data() as Map<String, dynamic>)
                            .toList();
                        await RiderPdfExport.generateAndPrint(selectedData);
                      },
                      icon: const Icon(Icons.picture_as_pdf, size: 16),
                      label: Text('Save to PDF (${selectedRiders.length})'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.danger,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(150, 40),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),

              // ── Search & Filter Tabs ──
              Wrap(
                spacing: 16,
                runSpacing: 16,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: isDesktop ? 300 : double.infinity,
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Search by Name, Phone, or ID...',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (val) {
                        ref.read(userSearchProvider.notifier).state = val;
                      },
                    ),
                  ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _FilterTab(label: 'All Riders', count: allUsers.length, value: 'all', groupValue: filter),
                        const SizedBox(width: 8),
                        _FilterTab(label: 'Active', count: activeCount, value: 'active', groupValue: filter),
                        const SizedBox(width: 8),
                        _FilterTab(label: 'Blocked', count: blockedCount, value: 'blocked', groupValue: filter),
                      ],
                    ),
                  ),
                ],
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
                        showCheckboxColumn: true,
                        columns: [
                          const DataColumn(label: Text('Rider Profile')),
                          const DataColumn(label: Text('Phone Number')),
                          const DataColumn(label: Text('Status')),
                          const DataColumn(label: Text('Total Rides')),
                          const DataColumn(label: Text('Actions')),
                        ],
                        rows: filteredUsers.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          return _buildDataRow(context, ref, doc.id, data, isDark, selectedRiders);
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

  DataRow _buildDataRow(BuildContext context, WidgetRef ref, String id, Map<String, dynamic> data, bool isDark, Set<String> selectedRiders) {
    final name = data['name'] ?? 'Guest Rider';
    final phone = data['phone'] ?? 'Hidden (Phone Auth)';
    final totalRides = data['totalCompletedRides'] ?? 0;
    final isBlk = data['isBlocked'] == true || data['isBlocked'] == 'true';

    final status = isBlk ? 'Blocked' : 'Active';
    final statusColor = isBlk ? AppTheme.danger : AppTheme.success;

    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;
    final text2Color = isDark ? AppTheme.darkText2 : AppTheme.lightText2;

    return DataRow(
      selected: selectedRiders.contains(id),
      onSelectChanged: (selected) {
        final current = Set<String>.from(ref.read(selectedRidersProvider));
        if (selected == true) {
          current.add(id);
        } else {
          current.remove(id);
        }
        ref.read(selectedRidersProvider.notifier).state = current;
      },
      cells: [
        // Rider Profile
        DataCell(
          InkWell(
            onTap: () => context.push('/rider/$id'),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: textColor),
                ),
                Text(
                  id,
                  style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: text2Color),
                ),
              ],
            ),
          ),
        ),
        // Phone
        DataCell(Text(
          phone,
          style: GoogleFonts.inter(fontWeight: FontWeight.w500, color: textColor),
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
        // Rides
        DataCell(Text(
          '$totalRides',
          style: GoogleFonts.inter(fontWeight: FontWeight.w500, color: textColor),
        )),
        // Actions
        DataCell(Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(isBlk ? Icons.lock_open : Icons.block, size: 20),
              color: isBlk ? AppTheme.success : AppTheme.danger,
              tooltip: isBlk ? 'Unblock' : 'Block',
              onPressed: () {
                FirebaseFirestore.instance.collection('users').doc(id).update({
                  'isBlocked': !isBlk,
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
      onTap: () => ref.read(userFilterProvider.notifier).state = value,
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
