// lib/presentation/screens/users_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/auth_provider.dart';
import 'rider_pdf_export.dart';

class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  static const int _limit = 20;

  List<DocumentSnapshot> _users = [];
  bool _isLoading = false;
  bool _hasMore = true;
  DocumentSnapshot? _lastDocument;

  String _filterStatus = 'all';
  String _searchQuery = '';

  final Set<String> _selectedUsers = {};

  int _allCount = 0;
  int _activeCount = 0;
  int _blockedCount = 0;

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchCounts();
    _fetchUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchCounts() async {
    try {
      final db = FirebaseFirestore.instance.collection('users');
      final allSnap = await db.count().get();
      final blkSnap = await db.where('isBlocked', isEqualTo: true).count().get();

      if (mounted) {
        setState(() {
          _allCount = allSnap.count ?? 0;
          _blockedCount = blkSnap.count ?? 0;
          _activeCount = _allCount - _blockedCount;
          if (_activeCount < 0) _activeCount = 0;
        });
      }
    } catch (e) {
      debugPrint('Error fetching user counts: $e');
    }
  }

  Future<void> _fetchUsers({bool loadMore = false}) async {
    if (_isLoading) return;
    if (loadMore && !_hasMore) return;

    setState(() {
      _isLoading = true;
    });

    try {
      Query q = FirebaseFirestore.instance.collection('users');

      bool needsLocalFiltering = false;

      if (_searchQuery.isNotEmpty) {
        // Multi-field search workaround (Phone or Name)
        final isPhone = int.tryParse(_searchQuery.replaceAll('+', '')) != null;
        if (isPhone) {
          q = q
              .where('phone', isGreaterThanOrEqualTo: _searchQuery)
              .where('phone', isLessThanOrEqualTo: '$_searchQuery\uf8ff');
        } else {
          // Capitalize first letter for common name searches
          String searchName = _searchQuery;
          if (searchName.isNotEmpty) {
            searchName = searchName[0].toUpperCase() + searchName.substring(1);
          }
          q = q
              .where('name', isGreaterThanOrEqualTo: searchName)
              .where('name', isLessThanOrEqualTo: '$searchName\uf8ff');
        }
        needsLocalFiltering = true; // Cannot mix range query with other equalities safely
      } else {
        q = q.orderBy('createdAt', descending: true);

        // Apply Status Filter
        if (_filterStatus == 'active') {
          q = q.where('isBlocked', isEqualTo: false);
        } else if (_filterStatus == 'blocked') {
          q = q.where('isBlocked', isEqualTo: true);
        }
      }

      q = q.limit(_limit);

      if (loadMore && _lastDocument != null) {
        q = q.startAfterDocument(_lastDocument!);
      }

      final snapshot = await q.get();
      List<DocumentSnapshot> docs = snapshot.docs;

      if (needsLocalFiltering) {
        // If we used a range query for search, filter status locally
        docs = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final isBlk = data['isBlocked'] == true || data['isBlocked'] == 'true';

          if (_filterStatus == 'active' && isBlk) return false;
          if (_filterStatus == 'blocked' && !isBlk) return false;

          return true;
        }).toList();
      }

      setState(() {
        if (loadMore) {
          _users.addAll(docs);
        } else {
          _users = docs;
        }
        _hasMore = snapshot.docs.length == _limit;
        if (snapshot.docs.isNotEmpty) {
          _lastDocument = snapshot.docs.last;
        }
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching users: $e');
      setState(() => _isLoading = false);
    }
  }

  void _onSearchChanged(String val) {
    setState(() {
      _searchQuery = val.trim();
      _users.clear();
      _lastDocument = null;
      _hasMore = true;
    });
    _fetchUsers();
  }

  void _setFilterStatus(String status) {
    setState(() {
      _filterStatus = status;
      _users.clear();
      _lastDocument = null;
      _hasMore = true;
      _selectedUsers.clear();
    });
    _fetchUsers();
  }

  void _exportPdf() async {
    if (_selectedUsers.isEmpty) return;

    final selectedDocs = _users.where((d) => _selectedUsers.contains(d.id)).toList();
    final dataList = selectedDocs.map((d) => d.data() as Map<String, dynamic>).toList();

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Generating PDF...')));
    await RiderPdfExport.generateAndPrint(dataList);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 1024;

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
              if (_selectedUsers.isNotEmpty)
                ElevatedButton.icon(
                  onPressed: _exportPdf,
                  icon: const Icon(Icons.picture_as_pdf, size: 16),
                  label: Text('Save to PDF (${_selectedUsers.length})'),
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
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  style: TextStyle(
                    color: isDark ? AppTheme.darkText : AppTheme.lightText,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search Name or Phone...',
                    hintStyle: TextStyle(
                      color: isDark ? AppTheme.darkText2 : AppTheme.lightText2,
                    ),
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _FilterTab(
                      label: 'All Riders',
                      count: _allCount,
                      value: 'all',
                      groupValue: _filterStatus,
                      onTap: () => _setFilterStatus('all'),
                    ),
                    const SizedBox(width: 8),
                    _FilterTab(
                      label: 'Active',
                      count: _activeCount,
                      value: 'active',
                      groupValue: _filterStatus,
                      onTap: () => _setFilterStatus('active'),
                    ),
                    const SizedBox(width: 8),
                    _FilterTab(
                      label: 'Blocked',
                      count: _blockedCount,
                      value: 'blocked',
                      groupValue: _filterStatus,
                      onTap: () => _setFilterStatus('blocked'),
                    ),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DataTable(
                        headingRowColor: WidgetStateProperty.all(
                          isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2,
                        ),
                        dataRowMinHeight: 64,
                        dataRowMaxHeight: 64,
                        onSelectAll: (val) {
                          setState(() {
                            if (val == true) {
                              _selectedUsers.addAll(_users.map((d) => d.id));
                            } else {
                              _selectedUsers.clear();
                            }
                          });
                        },
                        columns: const [
                          DataColumn(label: Text('Rider Profile')),
                          DataColumn(label: Text('Phone Number')),
                          DataColumn(label: Text('Status')),
                          DataColumn(label: Text('Total Rides')),
                          DataColumn(label: Text('Actions')),
                        ],
                        rows: _users.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          return _buildDataRow(context, doc.id, data, isDark);
                        }).toList(),
                      ),
                      if (_isLoading)
                        const Padding(
                          padding: EdgeInsets.all(32.0),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      if (!_isLoading && _users.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Center(
                            child: Text(
                              'No riders found.',
                              style: TextStyle(
                                color: isDark ? AppTheme.darkText2 : AppTheme.lightText2,
                              ),
                            ),
                          ),
                        ),
                      if (!_isLoading && _hasMore)
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Center(
                            child: TextButton(
                              onPressed: () => _fetchUsers(loadMore: true),
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
      ),
    );
  }

  DataRow _buildDataRow(BuildContext context, String id, Map<String, dynamic> data, bool isDark) {
    final name = data['name'] ?? 'Guest Rider';
    final phone = data['phone'] ?? 'Hidden (Phone Auth)';
    final totalRides = data['totalCompletedRides'] ?? 0;
    final isBlk = data['isBlocked'] == true || data['isBlocked'] == 'true';

    final status = isBlk ? 'Blocked' : 'Active';
    final statusColor = isBlk ? AppTheme.danger : AppTheme.success;

    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;
    final text2Color = isDark ? AppTheme.darkText2 : AppTheme.lightText2;
    
    final isSelected = _selectedUsers.contains(id);

    return DataRow(
      selected: isSelected,
      onSelectChanged: (val) {
        setState(() {
          if (val == true) {
            _selectedUsers.add(id);
          } else {
            _selectedUsers.remove(id);
          }
        });
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
                setState(() {
                   // Optimistic update locally
                   final index = _users.indexWhere((doc) => doc.id == id);
                   if (index != -1) {
                      // We don't have easy local mutation map like drivers screen, 
                      // but updating the DB will reflect on next fetch. 
                      // Let's just re-fetch the users.
                   }
                });
                _fetchCounts();
                _fetchUsers();
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
  final VoidCallback onTap;

  const _FilterTab({
    required this.label,
    required this.count,
    required this.value,
    required this.groupValue,
    required this.onTap,
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
      onTap: onTap,
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
