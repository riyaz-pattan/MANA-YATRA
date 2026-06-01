// lib/presentation/widgets/driver_profile_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/auth_provider.dart';

class DriverProfileDialog extends ConsumerWidget {
  final String driverId;

  const DriverProfileDialog({super.key, required this.driverId});

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
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        child: FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance.collection('drivers').doc(driverId).get(),
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
                      Text('Driver details not found.', style: GoogleFonts.inter(color: textColor)),
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
            final docs = data['documents'] as Map<String, dynamic>?;
            final selfieUrl = docs?['selfieUrl'] as String?;
            final name = data['name'] ?? 'Unknown Driver';
            final phone = data['phone'] ?? 'Unknown Phone';
            final vehicleType = data['vehicleType'] ?? 'auto';
            final rating = data['rating']?.toString() ?? 'N/A';
            final totalRides = data['totalAssignedRides'] ?? 0;
            final totalEarnings = data['totalEarnings'] ?? 0;

            final isAppr = data['isApproved'] == true || data['isApproved'] == 'true';
            final isBlk = data['isBlocked'] == true || data['isBlocked'] == 'true';
            final createdAt = (data['createdAt'] as Timestamp?)?.toDate();

            String status = 'PENDING';
            Color statusColor = AppTheme.warning;
            if (isBlk) {
              status = 'BLOCKED';
              statusColor = AppTheme.danger;
            } else if (isAppr) {
              status = 'APPROVED';
              statusColor = AppTheme.success;
            }

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
                      Text('Driver Profile', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: textColor)),
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
                          radius: 48,
                          backgroundColor: AppTheme.brandBlue.withValues(alpha: 0.1),
                          backgroundImage: (selfieUrl != null && selfieUrl.isNotEmpty) ? NetworkImage(selfieUrl) : null,
                          child: (selfieUrl == null || selfieUrl.isEmpty) ? const Icon(Icons.person, size: 48, color: AppTheme.brandBlue) : null,
                        ),
                        const SizedBox(height: 16),
                        Text(name, style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w700, color: textColor)),
                        const SizedBox(height: 4),
                        Text(phone, style: GoogleFonts.inter(fontSize: 15, color: text3Color)),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            status,
                            style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: statusColor),
                          ),
                        ),
                        const SizedBox(height: 32),
                        
                        _InfoRow(icon: Icons.local_taxi, label: 'Vehicle Type', value: vehicleType.toUpperCase(), textColor: textColor, text3Color: text3Color),
                        const Divider(height: 24),
                        _InfoRow(icon: Icons.star, label: 'Rating', value: rating, textColor: textColor, text3Color: text3Color),
                        const Divider(height: 24),
                        _InfoRow(icon: Icons.route, label: 'Total Rides', value: '$totalRides', textColor: textColor, text3Color: text3Color),
                        const Divider(height: 24),
                        _InfoRow(icon: Icons.account_balance_wallet, label: 'Total Earnings', value: '₹$totalEarnings', textColor: AppTheme.success, text3Color: text3Color),
                        const Divider(height: 24),
                        _InfoRow(
                          icon: Icons.calendar_today, 
                          label: 'Joined', 
                          value: createdAt != null ? DateFormat('MMM dd, yyyy').format(createdAt) : 'Unknown', 
                          textColor: textColor, 
                          text3Color: text3Color,
                        ),
                        const Divider(height: 24),
                        _InfoRow(icon: Icons.fingerprint, label: 'Driver ID', value: driverId, textColor: textColor, text3Color: text3Color),
                      ],
                    ),
                  ),
                ),
              ],
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
        const Spacer(),
        Text(value, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: textColor)),
      ],
    );
  }
}
