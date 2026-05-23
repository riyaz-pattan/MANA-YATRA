// lib/presentation/screens/sos_alerts_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/auth_provider.dart';

class SOSAlertsScreen extends ConsumerWidget {
  const SOSAlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final bg = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final border = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;
    final text3Color = isDark ? AppTheme.darkText3 : AppTheme.lightText3;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('sos_alerts').orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final allAlerts = snapshot.data!.docs.map((d) {
          final data = d.data() as Map<String, dynamic>;
          data['id'] = d.id;
          return data;
        }).toList();

        if (allAlerts.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 60),
              child: Column(
                children: [
                  Icon(Icons.gpp_good_outlined, size: 64, color: AppTheme.success.withValues(alpha: 0.5)),
                  const SizedBox(height: 16),
                  Text('No active SOS alerts.', style: GoogleFonts.inter(fontSize: 16, color: text3Color)),
                ],
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(24),
          itemCount: allAlerts.length,
          separatorBuilder: (_, __) => const SizedBox(height: 16),
          itemBuilder: (context, index) {
            final t = allAlerts[index];
            final status = t['status'] ?? 'active';
            final role = t['role'] ?? 'user';
            final name = t['name'] ?? 'Unknown';
            final phone = t['phone'] ?? '';
            final location = t['location'] ?? 'Unknown Location';
            final timestamp = t['createdAt'] as Timestamp?;
            final date = timestamp?.toDate();

            final isActive = status == 'active';
            final statusColor = isActive ? AppTheme.danger : AppTheme.success;

            return Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isActive ? AppTheme.danger.withValues(alpha: 0.05) : bg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isActive ? AppTheme.danger.withValues(alpha: 0.5) : border, width: isActive ? 2 : 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), shape: BoxShape.circle),
                            child: Icon(isActive ? Icons.warning_amber_rounded : Icons.check_circle_outline, color: statusColor),
                          ),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: textColor)),
                              Text('$phone • ${role.toUpperCase()}', style: GoogleFonts.inter(fontSize: 13, color: text3Color)),
                            ],
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(8)),
                        child: Text(isActive ? 'EMERGENCY' : 'RESOLVED', style: GoogleFonts.inter(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined, size: 16, color: AppTheme.danger),
                      const SizedBox(width: 8),
                      Expanded(child: Text(location, style: GoogleFonts.inter(fontWeight: FontWeight.w500, color: textColor))),
                      const SizedBox(width: 16),
                      Text(date != null ? DateFormat('MMM d, h:mm a').format(date) : '', style: GoogleFonts.inter(fontSize: 12, color: text3Color)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (isActive) ...[
                    Divider(color: border, height: 1),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              // Call authorities or driver
                            },
                            icon: const Icon(Icons.call),
                            label: const Text('Call User'),
                            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              FirebaseFirestore.instance.collection('sos_alerts').doc(t['id']).update({'status': 'resolved'});
                            },
                            icon: const Icon(Icons.check),
                            label: const Text('Mark Resolved'),
                            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(vertical: 16)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}
