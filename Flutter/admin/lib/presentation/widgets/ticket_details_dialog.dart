// lib/presentation/widgets/ticket_details_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/auth_provider.dart';
import 'user_profile_dialog.dart';
import 'driver_profile_dialog.dart';

class TicketDetailsDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> ticketData;

  const TicketDetailsDialog({super.key, required this.ticketData});

  @override
  ConsumerState<TicketDetailsDialog> createState() => _TicketDetailsDialogState();
}

class _TicketDetailsDialogState extends ConsumerState<TicketDetailsDialog> {
  bool _isUpdating = false;

  void _updateStatus(String newStatus) async {
    setState(() {
      _isUpdating = true;
    });
    try {
      await FirebaseFirestore.instance
          .collection('support_tickets')
          .doc(widget.ticketData['id'])
          .update({'status': newStatus});
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ticket status updated to ${newStatus.toUpperCase()}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating status: $e'), backgroundColor: AppTheme.danger),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUpdating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final bg = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final border = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;
    final text3Color = isDark ? AppTheme.darkText3 : AppTheme.lightText3;

    final t = widget.ticketData;
    final category = t['category'] ?? 'General';
    final subject = t['subject'] ?? 'No Subject';
    final description = t['description'] ?? 'No Description provided.';
    final priority = t['priority'] ?? 'low';
    final role = t['role'] ?? 'user';
    final name = t['name'] ?? 'Unknown User';
    final currentStatus = t['status'] ?? 'open';
    final timestamp = t['createdAt'] as Timestamp?;
    final date = timestamp?.toDate();
    final rideId = t['rideId'] as String?;

    Color priorityColor;
    switch (priority) {
      case 'high': priorityColor = AppTheme.danger; break;
      case 'medium': priorityColor = AppTheme.warning; break;
      default: priorityColor = AppTheme.success;
    }

    return Dialog(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 800,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: border)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Ticket Details', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700, color: textColor)),
                  IconButton(
                    icon: Icon(Icons.close, color: text3Color),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Info Row
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
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: currentStatus == 'resolved' || currentStatus == 'closed' 
                                          ? AppTheme.success.withValues(alpha: 0.1) 
                                          : (currentStatus == 'in_progress' ? AppTheme.warning.withValues(alpha: 0.1) : AppTheme.info.withValues(alpha: 0.1)),
                                      borderRadius: BorderRadius.circular(6)
                                    ),
                                    child: Text('STATUS: ${currentStatus.toUpperCase()}', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: textColor)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Text(subject, style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w800, color: textColor)),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(role == 'driver' ? Icons.local_taxi : Icons.person, size: 16, color: text3Color),
                                  const SizedBox(width: 8),
                                  InkWell(
                                    onTap: () {
                                      if (t['uid'] != null && t['uid'].toString().isNotEmpty) {
                                        showDialog(
                                          context: context,
                                          builder: (ctx) => role == 'driver' 
                                            ? DriverProfileDialog(driverId: t['uid']) 
                                            : UserProfileDialog(userId: t['uid']),
                                        );
                                      }
                                    },
                                    borderRadius: BorderRadius.circular(4),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 2.0, vertical: 2.0),
                                      child: Text(
                                        name, 
                                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.brandBlue, decoration: TextDecoration.underline, decorationColor: AppTheme.brandBlue),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Icon(Icons.calendar_today, size: 14, color: text3Color),
                                  const SizedBox(width: 6),
                                  Text(date != null ? DateFormat('MMM dd, yyyy • HH:mm').format(date) : '', style: GoogleFonts.inter(fontSize: 13, color: text3Color)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // Description
                    Text('Description', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: textColor)),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(color: isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2, borderRadius: BorderRadius.circular(12)),
                      child: Text(description, style: GoogleFonts.inter(fontSize: 15, color: isDark ? AppTheme.darkText : AppTheme.lightText, height: 1.6)),
                    ),

                    // Ride Details Section
                    if (rideId != null && rideId.isNotEmpty) ...[
                      const SizedBox(height: 32),
                      Text('Linked Ride Details', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: textColor)),
                      const SizedBox(height: 8),
                      FutureBuilder<DocumentSnapshot>(
                        future: FirebaseFirestore.instance.collection('rides').doc(rideId).get(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(border: Border.all(color: border), borderRadius: BorderRadius.circular(12)),
                              child: const Center(child: CircularProgressIndicator()),
                            );
                          }
                          if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
                            return Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(border: Border.all(color: border), borderRadius: BorderRadius.circular(12)),
                              child: Row(
                                children: [
                                  const Icon(Icons.error_outline, color: AppTheme.danger),
                                  const SizedBox(width: 8),
                                  Text('Could not load ride data or ride deleted. (ID: $rideId)', style: GoogleFonts.inter(color: AppTheme.danger)),
                                ],
                              ),
                            );
                          }

                          final rideData = snapshot.data!.data() as Map<String, dynamic>;
                          final pickup = rideData['pickup']?['short_name'] ?? 'Unknown';
                          final drop = rideData['drop']?['short_name'] ?? 'Unknown';
                          final rideStatus = rideData['status'] ?? 'unknown';
                          final fare = rideData['finalPrice']?.toString() ?? rideData['riderBid']?.toString() ?? '-';
                          final rideDate = (rideData['createdAt'] as Timestamp?)?.toDate();
                          final rideDriverId = rideData['driverId'] as String?;
                          final rideDriverName = rideData['driverName'] as String?;

                          return Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.brandBlue.withValues(alpha: 0.3)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Ride ID: ${rideId.substring(0, 8).toUpperCase()}', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600, color: textColor)),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(color: AppTheme.brandBlue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                                      child: Text(rideStatus.toUpperCase(), style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.brandBlue)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    const Icon(Icons.circle, size: 10, color: AppTheme.success),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text('Pickup: $pickup', overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 14, color: textColor))),
                                  ],
                                ),
                                Container(
                                  margin: const EdgeInsets.only(left: 4, top: 4, bottom: 4),
                                  height: 16,
                                  width: 2,
                                  color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                                ),
                                Row(
                                  children: [
                                    const Icon(Icons.location_on, size: 12, color: AppTheme.danger),
                                    const SizedBox(width: 6),
                                    Expanded(child: Text('Dropoff: $drop', overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 14, color: textColor))),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Fare: ₹$fare', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.success)),
                                    if (rideDate != null)
                                      Text(DateFormat('MMM dd, yyyy • HH:mm').format(rideDate), style: GoogleFonts.inter(fontSize: 12, color: text3Color)),
                                  ],
                                ),
                                if (rideDriverId != null) ...[
                                  const SizedBox(height: 16),
                                  const Divider(),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(Icons.local_taxi, size: 16, color: AppTheme.brandBlue),
                                      const SizedBox(width: 8),
                                      Text('Driver: ', style: GoogleFonts.inter(fontSize: 14, color: text3Color)),
                                      InkWell(
                                        onTap: () {
                                          showDialog(
                                            context: context,
                                            builder: (ctx) => DriverProfileDialog(driverId: rideDriverId),
                                          );
                                        },
                                        borderRadius: BorderRadius.circular(4),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 2.0, vertical: 2.0),
                                          child: Text(
                                            rideDriverName ?? 'View Driver Profile', 
                                            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.brandBlue, decoration: TextDecoration.underline, decorationColor: AppTheme.brandBlue),
                                          ),
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
                    ],
                  ],
                ),
              ),
            ),

            // Footer Actions
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: border)),
                color: isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2,
                borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
              ),
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 16,
                children: [
                  Text('Update Ticket Status:', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: textColor)),
                  if (_isUpdating)
                    const CircularProgressIndicator()
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.end,
                      children: [
                        _StatusButton(label: 'Open', color: AppTheme.info, isActive: currentStatus == 'open', onTap: () => _updateStatus('open')),
                        _StatusButton(label: 'In Progress', color: AppTheme.warning, isActive: currentStatus == 'in_progress', onTap: () => _updateStatus('in_progress')),
                        _StatusButton(label: 'Resolved', color: AppTheme.success, isActive: currentStatus == 'resolved', onTap: () => _updateStatus('resolved')),
                        _StatusButton(label: 'Closed', color: AppTheme.danger, isActive: currentStatus == 'closed', onTap: () => _updateStatus('closed')),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool isActive;
  final VoidCallback onTap;

  const _StatusButton({required this.label, required this.color, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: isActive ? color : color.withValues(alpha: 0.1),
        foregroundColor: isActive ? Colors.white : color,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(label),
    );
  }
}
