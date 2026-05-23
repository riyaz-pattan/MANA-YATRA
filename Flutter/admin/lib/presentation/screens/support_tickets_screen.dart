// lib/presentation/screens/support_tickets_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/auth_provider.dart';

class SupportTicketsScreen extends ConsumerStatefulWidget {
  const SupportTicketsScreen({super.key});

  @override
  ConsumerState<SupportTicketsScreen> createState() => _SupportTicketsScreenState();
}

class _SupportTicketsScreenState extends ConsumerState<SupportTicketsScreen> {
  String _filter = 'open'; // open | in_progress | resolved | closed

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

        final filtered = allTickets.where((d) => d['status'] == _filter).toList();

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
              const SizedBox(height: 24),

              if (filtered.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 60),
                    child: Column(
                      children: [
                        Icon(Icons.check_circle_outline, size: 64, color: AppTheme.success.withValues(alpha: 0.5)),
                        const SizedBox(height: 16),
                        Text('No $_filter tickets', style: GoogleFonts.inter(fontSize: 16, color: text3Color)),
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
                  onPressed: () => _updateTicketStatus(t['id']),
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

  void _updateTicketStatus(String id) {
    // Show dialog to update status
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update Ticket Status'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: const Text('Open'), onTap: () => _setStatus(id, 'open', ctx)),
            ListTile(title: const Text('In Progress'), onTap: () => _setStatus(id, 'in_progress', ctx)),
            ListTile(title: const Text('Resolved'), onTap: () => _setStatus(id, 'resolved', ctx)),
            ListTile(title: const Text('Closed'), onTap: () => _setStatus(id, 'closed', ctx)),
          ],
        ),
      ),
    );
  }

  void _setStatus(String id, String status, BuildContext ctx) {
    FirebaseFirestore.instance.collection('support_tickets').doc(id).update({'status': status});
    Navigator.pop(ctx);
  }
}
