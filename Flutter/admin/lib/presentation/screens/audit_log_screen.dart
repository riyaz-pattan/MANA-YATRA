// lib/presentation/screens/audit_log_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/auth_provider.dart';

class AuditLogScreen extends ConsumerWidget {
  const AuditLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final bg = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final border = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;
    final text3Color = isDark ? AppTheme.darkText3 : AppTheme.lightText3;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('audit_logs').orderBy('timestamp', descending: true).limit(50).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final logs = snapshot.data!.docs.map((d) {
          final data = d.data() as Map<String, dynamic>;
          data['id'] = d.id;
          return data;
        }).toList();

        if (logs.isEmpty) {
          return Center(child: Text('No audit logs found.', style: GoogleFonts.inter(color: text3Color)));
        }

        return ListView.separated(
          padding: const EdgeInsets.all(24),
          itemCount: logs.length,
          separatorBuilder: (_, __) => Divider(color: border, height: 1),
          itemBuilder: (context, index) {
            final log = logs[index];
            final action = log['action'] ?? 'unknown_action';
            final performedBy = log['performedBy'] ?? 'System';
            final role = log['performedByRole'] ?? '';
            final targetId = log['targetUid'] ?? log['targetId'] ?? '';
            final timestamp = log['timestamp'] as Timestamp?;
            final date = timestamp?.toDate();

            IconData icon = Icons.history;
            Color iconColor = AppTheme.brandBlue;

            if (action.contains('create') || action.contains('add')) {
              icon = Icons.add_circle_outline;
              iconColor = AppTheme.success;
            } else if (action.contains('delete') || action.contains('remove')) {
              icon = Icons.delete_outline;
              iconColor = AppTheme.danger;
            } else if (action.contains('update') || action.contains('set')) {
              icon = Icons.edit_outlined;
              iconColor = AppTheme.warning;
            }

            return Container(
              padding: const EdgeInsets.all(16),
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
                        Text(action.toUpperCase(), style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14, color: textColor)),
                        const SizedBox(height: 4),
                        Text('Performed by $performedBy ($role)', style: GoogleFonts.inter(fontSize: 13, color: text3Color)),
                        if (targetId.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('Target ID: $targetId', style: GoogleFonts.inter(fontSize: 12, color: isDark ? AppTheme.darkText2 : AppTheme.lightText2)),
                          ),
                      ],
                    ),
                  ),
                  Text(date != null ? DateFormat('MMM d, h:mm a').format(date) : '', style: GoogleFonts.inter(fontSize: 12, color: text3Color)),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
