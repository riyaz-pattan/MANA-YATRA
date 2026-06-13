// lib/presentation/screens/sos_alerts_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/auth_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/sos_live_map.dart';

class SOSAlertsScreen extends ConsumerStatefulWidget {
  const SOSAlertsScreen({super.key});

  @override
  ConsumerState<SOSAlertsScreen> createState() => _SOSAlertsScreenState();
}

class _SOSAlertsScreenState extends ConsumerState<SOSAlertsScreen> {
  bool _showResolved = false;

  void _resolveAlert(String id, String note, BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
    try {
      final db = FirebaseFirestore.instance;
      final batch = db.batch();

      batch.update(db.collection('sos_alerts').doc(id), {
        'status': 'resolved',
        'resolutionNote': note,
        'resolvedBy': uid,
        'resolvedAt': FieldValue.serverTimestamp(),
      });

      batch.set(db.collection('audit_logs').doc(), {
        'action': 'resolved_sos',
        'targetId': id,
        'performedBy': uid,
        'note': note,
        'timestamp': FieldValue.serverTimestamp(),
      });

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Alert marked as resolved.'), backgroundColor: AppTheme.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error resolving alert: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  void _showResolutionDialog(BuildContext context, String id) {
    final noteController = TextEditingController();
    final isDark = ref.read(themeModeProvider) == ThemeMode.dark;
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
        title: Text('Resolve Alert', style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText)),
        content: TextField(
          controller: noteController,
          maxLines: 3,
          style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText),
          decoration: const InputDecoration(
            hintText: 'Enter a resolution note (mandatory)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success, foregroundColor: Colors.white),
            onPressed: () {
              if (noteController.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              _resolveAlert(id, noteController.text.trim(), context);
            },
            child: const Text('Resolve'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final bg = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final border = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;
    final text3Color = isDark ? AppTheme.darkText3 : AppTheme.lightText3;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('sos_alerts').orderBy('createdAt', descending: true).limit(100).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        var filteredAlerts = snapshot.data!.docs.map((d) {
          final data = d.data() as Map<String, dynamic>;
          data['id'] = d.id;
          return data;
        }).toList();

        if (!_showResolved) {
          filteredAlerts = filteredAlerts.where((a) => a['status'] != 'resolved').toList();
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('Show Resolved', style: GoogleFonts.inter(fontSize: 14, color: textColor)),
                  const SizedBox(width: 8),
                  Switch(
                    value: _showResolved,
                    onChanged: (val) => setState(() => _showResolved = val),
                    activeColor: AppTheme.brandBlue,
                  ),
                ],
              ),
            ),
            if (filteredAlerts.isEmpty)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 60),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.gpp_good_outlined, size: 64, color: AppTheme.success.withValues(alpha: 0.5)),
                        const SizedBox(height: 16),
                        Text('No active SOS alerts.', style: GoogleFonts.inter(fontSize: 16, color: text3Color)),
                      ],
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(24),
                  itemCount: filteredAlerts.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final t = filteredAlerts[index];
            final status = t['status'] ?? 'active';
            final role = t['role'] ?? 'user';
            final name = t['name'] ?? 'Unknown';
            final phone = t['phone'] ?? '';
            final location = t['location'] ?? 'Unknown Location';
            final lat = t['lat'];
            final lng = t['lng'];
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
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), shape: BoxShape.circle),
                              child: Icon(isActive ? Icons.warning_amber_rounded : Icons.check_circle_outline, color: statusColor),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name, style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: textColor), overflow: TextOverflow.ellipsis),
                                  Text('$phone • ${role.toUpperCase()}', style: GoogleFonts.inter(fontSize: 13, color: text3Color), overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                          ],
                        ),
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
                  if (lat != null && lng != null && lat is double && lng is double) ...[
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        height: 180,
                        width: double.infinity,
                        child: SOSLiveMap(lat: lat, lng: lng, isDark: isDark),
                      ),
                    ),
                  ],
                  if (t['resolutionNote'] != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: AppTheme.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline, size: 16, color: AppTheme.success),
                          const SizedBox(width: 8),
                          Expanded(child: Text('Resolution Note: ${t['resolutionNote']}', style: TextStyle(color: textColor, fontSize: 13))),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (isActive) ...[
                    Divider(color: border, height: 1),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              if (phone.isNotEmpty) {
                                final uri = Uri.parse('tel:$phone');
                                if (await canLaunchUrl(uri)) {
                                  await launchUrl(uri);
                                }
                              }
                            },
                            icon: const Icon(Icons.call),
                            label: const Text('Call User'),
                            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _showResolutionDialog(context, t['id']),
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
        ),
      ),
    ],
  );
      },
    );
  }
}
