// lib/presentation/widgets/user_profile_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/auth_provider.dart';

class UserProfileDialog extends ConsumerWidget {
  final String userId;

  const UserProfileDialog({super.key, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final bg = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final border = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;
    final text3Color = isDark ? AppTheme.darkText3 : AppTheme.lightText3;

    return Dialog(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 450,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance.collection('users').doc(userId).get(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(height: 300, child: Center(child: CircularProgressIndicator()));
            }

            if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
              return SizedBox(
                height: 200,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: AppTheme.danger),
                      const SizedBox(height: 16),
                      Text('Rider details not found.', style: GoogleFonts.inter(color: textColor)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final data = snapshot.data!.data() as Map<String, dynamic>;
            final name = data['name'] ?? 'Unknown Rider';
            final phone = data['phone'] ?? 'Unknown Phone';
            final isBlk = data['isBlocked'] == true || data['isBlocked'] == 'true';
            final createdAt = (data['createdAt'] as Timestamp?)?.toDate();

            return FutureBuilder<AggregateQuerySnapshot>(
              future: FirebaseFirestore.instance.collection('rides').where('riderId', isEqualTo: userId).where('status', isEqualTo: 'completed').count().get(),
              builder: (context, rideSnap) {
                final totalRides = rideSnap.data?.count ?? data['totalCompletedRides'] ?? 0;
                
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: border))),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Rider Profile', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: textColor)),
                          IconButton(
                            icon: Icon(Icons.close, color: text3Color),
                            onPressed: () => Navigator.pop(context),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),

                    // Content
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 40,
                              backgroundColor: AppTheme.brandBlue.withValues(alpha: 0.1),
                              child: const Icon(Icons.person, size: 40, color: AppTheme.brandBlue),
                            ),
                            const SizedBox(height: 16),
                            Text(name, style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w700, color: textColor)),
                            const SizedBox(height: 4),
                            Text(phone, style: GoogleFonts.inter(fontSize: 15, color: text3Color)),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: isBlk ? AppTheme.danger.withValues(alpha: 0.1) : AppTheme.success.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isBlk ? 'BLOCKED' : 'ACTIVE',
                                style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: isBlk ? AppTheme.danger : AppTheme.success),
                              ),
                            ),
                            const SizedBox(height: 32),
                            
                            _InfoRow(icon: Icons.directions_car, label: 'Total Rides', value: '$totalRides', textColor: textColor, text3Color: text3Color),
                            if (createdAt != null) ...[
                              const Divider(height: 32),
                              _InfoRow(
                                icon: Icons.calendar_today, 
                                label: 'Joined', 
                                value: DateFormat('MMM dd, yyyy').format(createdAt), 
                                textColor: textColor, 
                                text3Color: text3Color,
                              ),
                            ],
                            const Divider(height: 32),
                            _InfoRow(icon: Icons.fingerprint, label: 'Rider ID', value: userId, textColor: textColor, text3Color: text3Color),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              }
            );
          },
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color textColor;
  final Color text3Color;

  const _InfoRow({required this.icon, required this.label, required this.value, required this.textColor, required this.text3Color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: text3Color),
        const SizedBox(width: 12),
        Text(label, style: GoogleFonts.inter(fontSize: 14, color: text3Color)),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            value, 
            textAlign: TextAlign.right, 
            overflow: TextOverflow.ellipsis, 
            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: textColor)
          ),
        ),
      ],
    );
  }
}
