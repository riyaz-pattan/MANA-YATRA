import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/auth_provider.dart';
import 'driver_pdf_export.dart';
import 'driver_document_modal.dart';

class DriversScreen extends ConsumerStatefulWidget {
  const DriversScreen({super.key});

  @override
  ConsumerState<DriversScreen> createState() => _DriversScreenState();
}

class _DriversScreenState extends ConsumerState<DriversScreen> {
  static const int _limit = 20;
  
  List<DocumentSnapshot> _drivers = [];
  bool _isLoading = false;
  bool _hasMore = true;
  DocumentSnapshot? _lastDocument;

  String _filterStatus = 'all';
  String _filterVehicle = 'all';
  String _searchQuery = '';
  
  final Set<String> _selectedDrivers = {};
  
  int _allCount = 0;
  int _pendingCount = 0;
  int _approvedCount = 0;
  int _blockedCount = 0;

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchCounts();
    _fetchDrivers();
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchCounts() async {
    try {
      final db = FirebaseFirestore.instance.collection('drivers');
      final allSnap = await db.count().get();
      final blkSnap = await db.where('isBlocked', isEqualTo: true).count().get();
      final apprSnap = await db.where('isApproved', isEqualTo: true).where('isBlocked', isEqualTo: false).count().get();
      
      if (mounted) {
        setState(() {
          _allCount = allSnap.count ?? 0;
          _blockedCount = blkSnap.count ?? 0;
          _approvedCount = apprSnap.count ?? 0;
          _pendingCount = _allCount - _approvedCount - _blockedCount;
          if (_pendingCount < 0) _pendingCount = 0;
        });
      }
    } catch (e) {
      debugPrint('Error fetching counts: $e');
    }
  }

  Future<void> _fetchDrivers({bool loadMore = false}) async {
    if (_isLoading) return;
    if (loadMore && !_hasMore) return;

    setState(() {
      _isLoading = true;
    });

    try {
      Query q = FirebaseFirestore.instance.collection('drivers');

      // Due to Firestore index limitations, if we have a search query,
      // we prioritize the search field and do local filtering for the rest.
      // If we don't have a search, we can use orderBy('createdAt').
      
      bool needsLocalFiltering = false;

      if (_searchQuery.isNotEmpty) {
        // Multi-field search workaround (Phone or Name)
        final isPhone = int.tryParse(_searchQuery.replaceAll('+', '')) != null;
        if (isPhone) {
          q = q.where('phone', isGreaterThanOrEqualTo: _searchQuery)
               .where('phone', isLessThanOrEqualTo: '$_searchQuery\uf8ff');
        } else {
          // Capitalize first letter for common name searches
          String searchName = _searchQuery;
          if (searchName.isNotEmpty) {
            searchName = searchName[0].toUpperCase() + searchName.substring(1);
          }
          q = q.where('name', isGreaterThanOrEqualTo: searchName)
               .where('name', isLessThanOrEqualTo: '$searchName\uf8ff');
        }
        needsLocalFiltering = true; // Cannot mix range query with other equalities safely without composite index
      } else {
        q = q.orderBy('createdAt', descending: true);
        
        // Apply Vehicle Filter
        if (_filterVehicle != 'all') {
          q = q.where('vehicleType', isEqualTo: _filterVehicle);
        }
        
        // Apply Status Filter
        if (_filterStatus == 'pending') {
          q = q.where('isApproved', isEqualTo: false).where('isBlocked', isEqualTo: false);
        } else if (_filterStatus == 'approved') {
          q = q.where('isApproved', isEqualTo: true).where('isBlocked', isEqualTo: false);
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
        // If we used a range query for search, we filter vehicle and status locally
        docs = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final vType = data['vehicleType'] ?? 'auto';
          final isAppr = data['isApproved'] == true || data['isApproved'] == 'true';
          final isBlk = data['isBlocked'] == true || data['isBlocked'] == 'true';
          
          if (_filterVehicle != 'all' && vType != _filterVehicle) return false;
          
          if (_filterStatus == 'pending' && (isAppr || isBlk)) return false;
          if (_filterStatus == 'approved' && (!isAppr || isBlk)) return false;
          if (_filterStatus == 'blocked' && !isBlk) return false;
          
          return true;
        }).toList();
      }

      setState(() {
        if (loadMore) {
          _drivers.addAll(docs);
        } else {
          _drivers = docs;
        }
        _hasMore = snapshot.docs.length == _limit;
        if (snapshot.docs.isNotEmpty) {
          _lastDocument = snapshot.docs.last;
        }
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching drivers: $e');
      setState(() => _isLoading = false);
    }
  }

  void _onSearchChanged(String val) {
    setState(() {
      _searchQuery = val.trim();
      _drivers.clear();
      _lastDocument = null;
      _hasMore = true;
    });
    _fetchDrivers();
  }

  void _setFilterStatus(String status) {
    setState(() {
      _filterStatus = status;
      _drivers.clear();
      _lastDocument = null;
      _hasMore = true;
      _selectedDrivers.clear();
    });
    _fetchDrivers();
  }

  void _setFilterVehicle(String vehicle) {
    setState(() {
      _filterVehicle = vehicle;
      _drivers.clear();
      _lastDocument = null;
      _hasMore = true;
      _selectedDrivers.clear();
    });
    _fetchDrivers();
  }

  void _exportPdf() async {
    if (_selectedDrivers.isEmpty) return;
    
    final selectedDocs = _drivers.where((d) => _selectedDrivers.contains(d.id)).toList();
    final dataList = selectedDocs.map((d) => d.data() as Map<String, dynamic>).toList();
    
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Generating PDF...')));
    await DriverPdfExport.generateAndPrint(dataList);
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
                  if (_selectedDrivers.isNotEmpty) ...[
                    Text('${_selectedDrivers.length} selected', style: TextStyle(color: isDark ? AppTheme.darkText2 : AppTheme.lightText2)),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: _exportPdf,
                      icon: const Icon(Icons.picture_as_pdf, size: 16),
                      label: const Text('Export PDF'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.brandBlue,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 40),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Controls (Search + Vehicle Filter) ──
          Wrap(
            spacing: 16,
            runSpacing: 16,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 300,
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText),
                  decoration: InputDecoration(
                    hintText: 'Search Name or Phone...',
                    hintStyle: TextStyle(color: isDark ? AppTheme.darkText2 : AppTheme.lightText2),
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _filterVehicle,
                    dropdownColor: isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2,
                    style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All Vehicles')),
                      DropdownMenuItem(value: 'auto', child: Text('Auto 🛺')),
                      DropdownMenuItem(value: 'bike', child: Text('Bike 🏍️')),
                    ],
                    onChanged: (val) {
                      if (val != null) _setFilterVehicle(val);
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Status Filter Tabs ──
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterTab(label: 'All', count: _allCount, value: 'all', groupValue: _filterStatus, onTap: () => _setFilterStatus('all')),
                const SizedBox(width: 8),
                _FilterTab(label: 'Pending Review', count: _pendingCount, value: 'pending', groupValue: _filterStatus, onTap: () => _setFilterStatus('pending')),
                const SizedBox(width: 8),
                _FilterTab(label: 'Approved', count: _approvedCount, value: 'approved', groupValue: _filterStatus, onTap: () => _setFilterStatus('approved')),
                const SizedBox(width: 8),
                _FilterTab(label: 'Blocked', count: _blockedCount, value: 'blocked', groupValue: _filterStatus, onTap: () => _setFilterStatus('blocked')),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DataTable(
                        headingRowColor: WidgetStateProperty.all(
                          isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2,
                        ),
                        dataRowMinHeight: 64,
                        dataRowMaxHeight: 64,
                        columns: [
                          DataColumn(
                            label: Checkbox(
                              value: _selectedDrivers.length == _drivers.length && _drivers.isNotEmpty,
                              onChanged: (val) {
                                setState(() {
                                  if (val == true) {
                                    _selectedDrivers.addAll(_drivers.map((d) => d.id));
                                  } else {
                                    _selectedDrivers.clear();
                                  }
                                });
                              },
                            ),
                          ),
                          const DataColumn(label: Text('Driver Info')),
                          const DataColumn(label: Text('Vehicle Type')),
                          const DataColumn(label: Text('Status')),
                          const DataColumn(label: Text('Rides / Earnings')),
                          const DataColumn(label: Text('Actions')),
                        ],
                        rows: _drivers.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          return _buildDataRow(context, doc.id, data, isDark);
                        }).toList(),
                      ),
                      if (_isLoading)
                        const Padding(
                          padding: EdgeInsets.all(32.0),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      if (!_isLoading && _drivers.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Center(
                            child: Text(
                              'No drivers found.',
                              style: TextStyle(color: isDark ? AppTheme.darkText2 : AppTheme.lightText2),
                            ),
                          ),
                        ),
                      if (!_isLoading && _hasMore)
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Center(
                            child: TextButton(
                              onPressed: () => _fetchDrivers(loadMore: true),
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
    final docs = data['documents'] as Map<String, dynamic>?;
    final selfieUrl = docs?['selfieUrl'] as String?;
    final name = data['name'] ?? 'Unknown';
    final phone = data['phone'] ?? 'No Phone';
    final vehicleType = data['vehicleType'] ?? 'auto';
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
    
    final isSelected = _selectedDrivers.contains(id);

    return DataRow(
      selected: isSelected,
      onSelectChanged: (val) {
        setState(() {
          if (val == true) _selectedDrivers.add(id);
          else _selectedDrivers.remove(id);
        });
      },
      cells: [
        DataCell(Checkbox(
          value: isSelected,
          onChanged: (val) {
            setState(() {
              if (val == true) _selectedDrivers.add(id);
              else _selectedDrivers.remove(id);
            });
          },
        )),
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
              icon: const Icon(Icons.location_on, size: 20),
              color: AppTheme.brandBlue,
              tooltip: 'Live Map Jump',
              onPressed: () {
                // To actually jump to map, you would typically pass the ID to your MapScreen or Dashboard route.
                // For now, we show a success snackbar to demonstrate the UX.
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Jumping to Driver: $name on Map')));
              },
            ),
            IconButton(
              icon: const Icon(Icons.badge, size: 20),
              color: AppTheme.info,
              tooltip: 'Document Verification',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => DriverDocumentModal(
                    driverId: id,
                    documents: docs ?? {},
                    isDark: isDark,
                  ),
                );
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
                  _fetchCounts(); // Update local counts
                },
              ),
            IconButton(
              icon: Icon(isBlk ? Icons.lock_open : Icons.pause_circle_filled, size: 20),
              color: isBlk ? AppTheme.success : AppTheme.warning,
              tooltip: isBlk ? 'Unblock' : 'Suspend 24h',
              onPressed: () {
                FirebaseFirestore.instance.collection('drivers').doc(id).update({
                  'isBlocked': !isBlk,
                  'isOnline': false,
                });
                _fetchCounts();
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
