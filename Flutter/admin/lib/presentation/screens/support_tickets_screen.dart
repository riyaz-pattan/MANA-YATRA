// lib/presentation/screens/support_tickets_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/auth_provider.dart';
import '../widgets/ticket_details_dialog.dart';

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

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 1024;
    
    final bg = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final border = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;
    final text3Color = isDark ? AppTheme.darkText3 : AppTheme.lightText3;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('support_tickets').orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final allTickets = snapshot.data!.docs.map((d) {
          final data = d.data() as Map<String, dynamic>;
          data['id'] = d.id;
          return data;
        }).toList();

        final openCount = allTickets.where((d) => d['status'] == 'open').length;
        final inProgressCount = allTickets.where((d) => d['status'] == 'in_progress').length;
        final resolvedCount = allTickets.where((d) => d['status'] == 'resolved').length;
        final closedCount = allTickets.where((d) => d['status'] == 'closed').length;

        final filtered = allTickets.where((d) {
          if (d['status'] != _filter) return false;
          if (_roleFilter != 'All Roles') {
            final r = (d['role'] ?? 'rider').toString().toLowerCase();
            if (r != _roleFilter.toLowerCase()) return false;
          }
          if (_categoryFilter != 'All Categories') {
            final c = (d['category'] ?? 'General').toString();
            if (c != _categoryFilter) return false;
          }
          return true;
        }).toList();

        return SingleChildScrollView(
          padding: EdgeInsets.all(isDesktop ? 32 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Support Tickets', style: GoogleFonts.inter(fontSize: isDesktop ? 24 : 20, fontWeight: FontWeight.w700, color: textColor)),
              const SizedBox(height: 8),
              Text('Manage user and driver complaints, disputes, and inquiries.', style: GoogleFonts.inter(fontSize: 14, color: text3Color)),
              const SizedBox(height: 32),

              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
                child: Row(
                  children: [
                    _filterTab('Open', openCount, 'open', isDark),
                    _filterTab('In Progress', inProgressCount, 'in_progress', isDark),
                    _filterTab('Resolved', resolvedCount, 'resolved', isDark),
                    _filterTab('Closed', closedCount, 'closed', isDark),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildDropdown(_roleOptions, _roleFilter, (val) => setState(() => _roleFilter = val!), bg, border, textColor),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildDropdown(_categoryOptions, _categoryFilter, (val) => setState(() => _categoryFilter = val!), bg, border, textColor),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              if (filtered.isEmpty)
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
                ...filtered.map((t) => _ticketCard(t, isDark, bg, border, textColor, text3Color)),
            ],
          ),
        );
      },
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
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: (isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2), borderRadius: BorderRadius.circular(6)),
                            child: Text(role.toUpperCase(), style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: role == 'driver' ? AppTheme.brandBlue : AppTheme.success)),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: (isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2), borderRadius: BorderRadius.circular(6)),
                            child: Text(category, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: textColor)),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: priorityColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                            child: Row(
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
                                  Text('Linked Ride: ${t['rideId']}', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.brandBlue, fontWeight: FontWeight.w600, decoration: TextDecoration.underline, decorationColor: AppTheme.brandBlue)),
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
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.brandBlue, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
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
