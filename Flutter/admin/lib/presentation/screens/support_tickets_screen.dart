// lib/presentation/screens/support_tickets_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/auth_provider.dart';
import '../widgets/ticket_details_dialog.dart';
import '../../core/services/audit_log_service.dart';

class SupportTicketsScreen extends ConsumerStatefulWidget {
  const SupportTicketsScreen({super.key});

  @override
  ConsumerState<SupportTicketsScreen> createState() => _SupportTicketsScreenState();
}

class _SupportTicketsScreenState extends ConsumerState<SupportTicketsScreen> {
  String _filter = 'open'; // open | in_progress | resolved | closed
  String _roleFilter = 'All Roles';
  String _categoryFilter = 'All Categories';

  final List<String> _roleOptions = ['All Roles', 'Rider', 'Driver'];
  final List<String> _categoryOptions = [
    'All Categories',
    'Payment Issue',
    'Payout Issue',
    'Driver Behavior',
    'Rider Behavior',
    'Lost Item',
    'Navigation Issue',
    'App Bug',
    'Other'
  ];

  // Pagination & Counts State
  List<Map<String, dynamic>> _tickets = [];
  DocumentSnapshot? _lastDocument;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String _indexError = '';
  
  int _openCount = 0;
  int _inProgressCount = 0;
  int _resolvedCount = 0;
  int _closedCount = 0;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchCounts();
    _fetchInitialTickets();
    
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
        _fetchMoreTickets();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchCounts() async {
    try {
      final futures = await Future.wait([
        FirebaseFirestore.instance.collection('support_tickets').where('status', isEqualTo: 'open').count().get(),
        FirebaseFirestore.instance.collection('support_tickets').where('status', isEqualTo: 'in_progress').count().get(),
        FirebaseFirestore.instance.collection('support_tickets').where('status', isEqualTo: 'resolved').count().get(),
        FirebaseFirestore.instance.collection('support_tickets').where('status', isEqualTo: 'closed').count().get(),
      ]);
      if (mounted) {
        setState(() {
          _openCount = futures[0].count ?? 0;
          _inProgressCount = futures[1].count ?? 0;
          _resolvedCount = futures[2].count ?? 0;
          _closedCount = futures[3].count ?? 0;
        });
      }
    } catch (e) {
      debugPrint('Error fetching counts: $e');
    }
  }

  Query _buildQuery() {
    Query q = FirebaseFirestore.instance.collection('support_tickets');
    
    q = q.where('status', isEqualTo: _filter);

    if (_roleFilter != 'All Roles') {
      q = q.where('role', isEqualTo: _roleFilter.toLowerCase());
    }
    if (_categoryFilter != 'All Categories') {
      q = q.where('category', isEqualTo: _categoryFilter);
    }
    
    q = q.orderBy('createdAt', descending: true).limit(20);
    return q;
  }

  Future<void> _fetchInitialTickets() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _indexError = '';
    });

    try {
      final snap = await _buildQuery().get();
      if (mounted) {
        setState(() {
          _tickets = snap.docs.map((d) {
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

  Future<void> _fetchMoreTickets() async {
    if (_isLoadingMore || !_hasMore || _isLoading || _lastDocument == null) return;
    setState(() {
      _isLoadingMore = true;
    });

    try {
      final snap = await _buildQuery().startAfterDocument(_lastDocument!).get();
      if (mounted) {
        setState(() {
          final newTickets = snap.docs.map((d) {
            final data = d.data() as Map<String, dynamic>;
            data['id'] = d.id;
            return data;
          }).toList();
          _tickets.addAll(newTickets);
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
    _fetchInitialTickets();
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Support Tickets', style: GoogleFonts.inter(fontSize: isDesktop ? 24 : 20, fontWeight: FontWeight.w700, color: textColor)),
                    const SizedBox(height: 8),
                    Text('Manage user and driver complaints, disputes, and inquiries.', style: GoogleFonts.inter(fontSize: 14, color: text3Color)),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.refresh, color: AppTheme.brandBlue),
                onPressed: () {
                  _fetchCounts();
                  _fetchInitialTickets();
                },
                tooltip: 'Refresh Tickets',
              ),
            ],
          ),
          const SizedBox(height: 32),

          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
            child: Row(
              children: [
                _filterTab('Open', _openCount, 'open', isDark),
                _filterTab('In Progress', _inProgressCount, 'in_progress', isDark),
                _filterTab('Resolved', _resolvedCount, 'resolved', isDark),
                _filterTab('Closed', _closedCount, 'closed', isDark),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildDropdown(_roleOptions, _roleFilter, (val) {
                  setState(() => _roleFilter = val!);
                  _onFilterChanged();
                }, bg, border, textColor),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildDropdown(_categoryOptions, _categoryFilter, (val) {
                  setState(() => _categoryFilter = val!);
                  _onFilterChanged();
                }, bg, border, textColor),
              ),
            ],
          ),
          const SizedBox(height: 24),

          if (_indexError.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
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
            )
          else if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_tickets.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 60),
                child: Column(
                  children: [
                    Icon(Icons.check_circle_outline, size: 64, color: AppTheme.success.withValues(alpha: 0.5)),
                    const SizedBox(height: 16),
                    Text('No tickets matching filters', style: GoogleFonts.inter(fontSize: 16, color: text3Color)),
                  ],
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _tickets.length + (_hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _tickets.length) {
                  return const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return _ticketCard(_tickets[index], isDark, bg, border, textColor, text3Color);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildDropdown(List<String> items, String value, ValueChanged<String?> onChanged, Color bg, Color border, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: border)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: bg,
          icon: Icon(Icons.arrow_drop_down, color: textColor),
          items: items.map((String item) {
            return DropdownMenuItem<String>(
              value: item,
              child: Text(item, style: GoogleFonts.inter(color: textColor, fontSize: 14, fontWeight: FontWeight.w500)),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _filterTab(String label, int count, String value, bool isDark) {
    final isActive = _filter == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _filter = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isActive ? (isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Text('$count', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700, color: isActive ? (isDark ? AppTheme.darkText : AppTheme.lightText) : (isDark ? AppTheme.darkText3 : AppTheme.lightText3))),
              const SizedBox(height: 4),
              Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: isActive ? FontWeight.w600 : FontWeight.w500, color: isActive ? (isDark ? AppTheme.darkText : AppTheme.lightText) : (isDark ? AppTheme.darkText3 : AppTheme.lightText3))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ticketCard(Map<String, dynamic> t, bool isDark, Color bg, Color border, Color textColor, Color text3Color) {
    final category = t['category'] ?? 'General';
    final subject = t['subject'] ?? 'No Subject';
    final description = t['description'] ?? '';
    final priority = t['priority'] ?? 'low';
    final role = t['role'] ?? 'user';
    final name = t['name'] ?? 'Unknown User';
    final timestamp = t['createdAt'] as Timestamp?;
    final date = timestamp?.toDate();

    Color priorityColor;
    switch (priority) {
      case 'high': priorityColor = AppTheme.danger; break;
      case 'medium': priorityColor = AppTheme.warning; break;
      default: priorityColor = AppTheme.success;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: border)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: (isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2), borderRadius: BorderRadius.circular(6)),
                            child: Text(role.toUpperCase(), style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: role == 'driver' ? AppTheme.brandBlue : AppTheme.success)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: (isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2), borderRadius: BorderRadius.circular(6)),
                            child: Text(category, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: textColor)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: priorityColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.circle, size: 8, color: priorityColor),
                                const SizedBox(width: 6),
                                Text('${priority.toUpperCase()} PRIORITY', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: priorityColor)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(subject, style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: textColor)),
                      if (t['rideId'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: InkWell(
                            onTap: () => _showTicketDetails(t),
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 2.0),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.directions_car, size: 14, color: AppTheme.brandBlue),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      'Linked Ride: ${t['rideId']}', 
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(fontSize: 12, color: AppTheme.brandBlue, fontWeight: FontWeight.w600, decoration: TextDecoration.underline, decorationColor: AppTheme.brandBlue)
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Text(date != null ? DateFormat.yMMMd().format(date) : '', style: GoogleFonts.inter(fontSize: 12, color: text3Color)),
              ],
            ),
            const SizedBox(height: 12),
            Text(description, maxLines: 2, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 14, color: isDark ? AppTheme.darkText2 : AppTheme.lightText2, height: 1.5)),
            const SizedBox(height: 24),
            Divider(color: border, height: 1),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(role == 'driver' ? Icons.local_taxi : Icons.person, size: 16, color: text3Color),
                    const SizedBox(width: 8),
                    Text(name, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: textColor)),
                  ],
                ),
                ElevatedButton(
                  onPressed: () => _showTicketDetails(t),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.brandBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  child: const Text('View & Update'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showTicketDetails(Map<String, dynamic> ticketData) {
    showDialog(
      context: context,
      builder: (ctx) => TicketDetailsDialog(ticketData: ticketData),
    );
  }
}
