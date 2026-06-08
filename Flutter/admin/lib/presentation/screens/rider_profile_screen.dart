import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/auth_provider.dart';
import 'package:timeago/timeago.dart' as timeago;

class RiderProfileScreen extends ConsumerStatefulWidget {
  final String riderId;

  const RiderProfileScreen({super.key, required this.riderId});

  @override
  ConsumerState<RiderProfileScreen> createState() => _RiderProfileScreenState();
}

class _RiderProfileScreenState extends ConsumerState<RiderProfileScreen> {
  Future<void> _updateStatus({required bool isBlocked}) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(widget.riderId).update({
        'isBlocked': isBlocked,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isBlocked ? 'Rider suspended' : 'Rider unblocked'),
            backgroundColor: isBlocked ? AppTheme.warning : AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final bg = isDark ? AppTheme.darkBg : AppTheme.lightBg;
    final surface = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final surface2 = isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2;
    final text1 = isDark ? AppTheme.darkText : AppTheme.lightText;
    final text2 = isDark ? AppTheme.darkText2 : AppTheme.lightText2;
    final border = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: text1),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Rider Profile',
          style: GoogleFonts.inter(
            color: text1,
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(widget.riderId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.brandBlue));
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: AppTheme.danger)));
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return Center(child: Text('Rider not found', style: TextStyle(color: text2)));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final name = data['name'] ?? 'Guest Rider';
          final phone = data['phone'] ?? 'No Phone';
          final photoUrl = data['photoUrl'];
          
          final isBlocked = data['isBlocked'] == true || data['isBlocked'] == 'true';
          final statusColor = isBlocked ? AppTheme.danger : AppTheme.success;
          final statusText = isBlocked ? 'Blocked' : 'Active';
          final totalRides = data['totalCompletedRides'] ?? 0;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Profile Section
                Center(
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 60,
                        backgroundColor: surface2,
                        backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                        child: photoUrl == null
                            ? Icon(Icons.person, size: 60, color: text2)
                            : null,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        name,
                        style: GoogleFonts.inter(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: text1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        phone,
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          color: text2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'ID: ${widget.riderId}',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: text2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Summary Section
                Row(
                  children: [
                    Expanded(
                      child: _buildSummaryCard(
                        'Total Rides',
                        totalRides.toString(),
                        Icons.directions_car,
                        AppTheme.brandBlue,
                        surface,
                        border,
                        text1,
                        text2,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildSummaryCard(
                        'Status',
                        statusText,
                        isBlocked ? Icons.block : Icons.check_circle,
                        statusColor,
                        surface,
                        border,
                        text1,
                        text2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                const SizedBox(height: 32),

                // Admin Actions
                Row(
                  children: [
                    if (!isBlocked)
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _updateStatus(isBlocked: true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.warning,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.pause_circle_outline),
                          label: Text(
                            'Suspend Rider',
                            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    if (isBlocked)
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _updateStatus(isBlocked: false),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.success,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.check_circle_outline),
                          label: Text(
                            'Unblock Rider',
                            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, Color color, Color surface, Color border, Color text1, Color text2) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 16),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: text1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: text2,
            ),
          ),
        ],
      ),
    );
  }

}
