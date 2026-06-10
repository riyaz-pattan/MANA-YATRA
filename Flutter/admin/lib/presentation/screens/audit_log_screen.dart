import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/auth_provider.dart';
import 'audit_log_pdf_export.dart';

class AuditLogScreen extends ConsumerStatefulWidget {
  const AuditLogScreen({super.key});

  @override
  ConsumerState<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends ConsumerState<AuditLogScreen> {
  final TextEditingController _searchController = TextEditingController();
  
  String _filterAction = 'All Actions';
  DateTime? _startDate;
  DateTime? _endDate;
  
  List<Map<String, dynamic>> _logs = [];
  DocumentSnapshot? _lastDocument;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String _indexError = '';

  final ScrollController _scrollController = ScrollController();

  final List<String> _actionOptions = [
    'All Actions',
    'approved_driver',
    'rejected_driver',
    'blocked_driver',
    'unblocked_driver',
    'blocked_rider',
    'unblocked_rider',
    'updated_ticket_status',
    'resolved_sos',
    'toggled_feature_flag',
    'updated_pricing_config'
  ];

  @override
  void initState() {
    super.initState();
    _fetchInitialLogs();
    
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
        _fetchMoreLogs();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Query _buildQuery() {
    Query q = FirebaseFirestore.instance.collection('audit_logs');
    
    if (_filterAction != 'All Actions') {
      q = q.where('action', isEqualTo: _filterAction);
    }
    
    // Note: If using multiple where/orderBy clauses, Firebase requires composite indexes.
    if (_startDate != null && _endDate != null) {
      q = q.where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(_startDate!));
      q = q.where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(_endDate!.add(const Duration(days: 1))));
    }
    
    q = q.orderBy('timestamp', descending: true).limit(20);
    return q;
  }

  Future<void> _fetchInitialLogs() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _indexError = '';
    });

    try {
      final snap = await _buildQuery().get();
      if (mounted) {
        setState(() {
          _logs = snap.docs.map((d) {
            final data = d.data() as Map<String, dynamic>;
            data['id'] = d.id;
            return data;
          }).toList();
          _lastDocument = snap.docs.isNotEmpty ? snap.docs.last : null;
          _hasMore = snap.docs.length == 20;
          _isLoading = false;
        });
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _indexError = e.message ?? 'Unknown Firebase Error';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _indexError = e.toString();
        });
      }
    }
  }

  Future<void> _fetchMoreLogs() async {
    if (_isLoadingMore || !_hasMore || _isLoading || _lastDocument == null) return;
    setState(() {
      _isLoadingMore = true;
    });

    try {
      final snap = await _buildQuery().startAfterDocument(_lastDocument!).get();
      if (mounted) {
        setState(() {
          final newLogs = snap.docs.map((d) {
            final data = d.data() as Map<String, dynamic>;
            data['id'] = d.id;
            return data;
          }).toList();
          _logs.addAll(newLogs);
          _lastDocument = snap.docs.isNotEmpty ? snap.docs.last : _lastDocument;
          _hasMore = snap.docs.length == 20;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  void _onFilterChanged() {
    _fetchInitialLogs();
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final initialDateRange = _startDate != null && _endDate != null
        ? DateTimeRange(start: _startDate!, end: _endDate!)
        : DateTimeRange(start: DateTime.now().subtract(const Duration(days: 7)), end: DateTime.now());

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: initialDateRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.brandBlue,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _onFilterChanged();
    }
  }

  void _clearDateRange() {
    setState(() {
      _startDate = null;
      _endDate = null;
    });
    _onFilterChanged();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 1024;
    
    final bg = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final border = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;
    final text3Color = isDark ? AppTheme.darkText3 : AppTheme.lightText3;

    return SingleChildScrollView(
      controller: _scrollController,
      padding: EdgeInsets.all(isDesktop ? 32 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 16,
            children: [
              Text('Security Audit Logs', style: GoogleFonts.inter(fontSize: isDesktop ? 24 : 20, fontWeight: FontWeight.w700, color: textColor)),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.refresh, color: AppTheme.brandBlue),
                    onPressed: _fetchInitialLogs,
                    tooltip: 'Refresh Logs',
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _logs.isEmpty ? null : () => AuditLogPdfExport.generateAndPrint(_logs),
                    icon: const Icon(Icons.picture_as_pdf, size: 16),
                    label: const Text('Export PDF'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.brandTeal,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 48),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Filters Row
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
            child: Wrap(
              spacing: 16,
              runSpacing: 16,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Action Filter Dropdown
                Container(
                  width: 220,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(color: isDark ? AppTheme.darkBg : AppTheme.lightBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: border)),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _filterAction,
                      isExpanded: true,
                      dropdownColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
                      icon: Icon(Icons.arrow_drop_down, color: textColor),
                      items: _actionOptions.map((String item) {
                        return DropdownMenuItem<String>(
                          value: item,
                          child: Text(item, style: GoogleFonts.inter(color: textColor, fontSize: 13, fontWeight: FontWeight.w500)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _filterAction = val);
                          _onFilterChanged();
                        }
                      },
                    ),
                  ),
                ),
                
                // Date Range Picker
                InkWell(
                  onTap: () => _selectDateRange(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(color: isDark ? AppTheme.darkBg : AppTheme.lightBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: border)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.calendar_today, size: 16, color: textColor),
                        const SizedBox(width: 8),
                        Text(
                          _startDate != null && _endDate != null
                              ? '${DateFormat('MMM d').format(_startDate!)} - ${DateFormat('MMM d').format(_endDate!)}'
                              : 'Select Date Range',
                          style: GoogleFonts.inter(color: textColor, fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                        if (_startDate != null) ...[
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: _clearDateRange,
                            child: const Icon(Icons.close, size: 16, color: AppTheme.danger),
                          ),
                        ]
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          if (_indexError.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(color: AppTheme.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.danger)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: AppTheme.danger),
                      const SizedBox(width: 8),
                      Text('Database Index Required', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: AppTheme.danger)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SelectableText(_indexError, style: GoogleFonts.inter(fontSize: 13, color: textColor)),
                ],
              ),
            ),

          if (_isLoading)
            const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 60), child: CircularProgressIndicator()))
          else if (_logs.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 60),
                child: Text('No audit logs found.', style: GoogleFonts.inter(fontSize: 16, color: text3Color)),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _logs.length + (_hasMore ? 1 : 0),
              separatorBuilder: (_, __) => Divider(color: border, height: 1),
              itemBuilder: (context, index) {
                if (index == _logs.length) {
                  return const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final log = _logs[index];
                return _buildLogCard(log, bg, border, textColor, text3Color, isDark);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildLogCard(Map<String, dynamic> log, Color bg, Color border, Color textColor, Color text3Color, bool isDark) {
    final action = log['action'] ?? 'unknown_action';
    final performedBy = log['performedBy'] ?? 'System';
    final role = log['performedByRole'] ?? '';
    final targetId = log['targetUid'] ?? log['targetId'] ?? '';
    final details = log['details'] ?? '';
    final timestamp = log['timestamp'] as Timestamp?;
    final date = timestamp?.toDate();

    IconData icon = Icons.history;
    Color iconColor = AppTheme.brandBlue;

    switch (action) {
      case 'approved_driver':
        icon = Icons.verified_user;
        iconColor = AppTheme.success;
        break;
      case 'rejected_driver':
        icon = Icons.person_remove;
        iconColor = AppTheme.danger;
        break;
      case 'blocked_driver':
        icon = Icons.person_off;
        iconColor = AppTheme.danger;
        break;
      case 'unblocked_driver':
        icon = Icons.how_to_reg;
        iconColor = AppTheme.success;
        break;
      case 'updated_driver_profile':
        icon = Icons.manage_accounts;
        iconColor = AppTheme.brandBlue;
        break;
      case 'blocked_rider':
        icon = Icons.no_accounts;
        iconColor = AppTheme.danger;
        break;
      case 'unblocked_rider':
        icon = Icons.how_to_reg;
        iconColor = AppTheme.success;
        break;
      case 'resolved_sos':
        icon = Icons.health_and_safety;
        iconColor = AppTheme.brandTeal;
        break;
      case 'updated_ticket_status':
        icon = Icons.support_agent;
        iconColor = AppTheme.warning;
        break;
      case 'toggled_feature_flag':
        icon = Icons.toggle_on;
        iconColor = AppTheme.brandBlue;
        break;
      case 'updated_pricing_config':
        icon = Icons.price_change;
        iconColor = AppTheme.brandTeal;
        break;
      default:
        icon = Icons.history;
        iconColor = AppTheme.brandBlue;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(icon, color: iconColor),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(action.toString().toUpperCase(), style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14, color: textColor)),
                const SizedBox(height: 4),
                Text('Performed by $performedBy ($role)', style: GoogleFonts.inter(fontSize: 13, color: text3Color)),
                if (targetId.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Target ID: $targetId', style: GoogleFonts.inter(fontSize: 12, color: isDark ? AppTheme.darkText2 : AppTheme.lightText2)),
                  ),
                if (details.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Details: $details', style: GoogleFonts.inter(fontSize: 12, fontStyle: FontStyle.italic, color: text3Color)),
                  ),
              ],
            ),
          ),
          Text(date != null ? DateFormat('MMM d, h:mm a').format(date) : '', style: GoogleFonts.inter(fontSize: 12, color: text3Color)),
        ],
      ),
    );
  }
}
