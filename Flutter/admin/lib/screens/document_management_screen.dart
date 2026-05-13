// lib/screens/document_management_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/theme.dart';

class DocumentManagementScreen extends StatefulWidget {
  const DocumentManagementScreen({super.key});

  @override
  State<DocumentManagementScreen> createState() =>
      _DocumentManagementScreenState();
}

class _DocumentManagementScreenState extends State<DocumentManagementScreen> {
  String _filter = 'pending'; // pending | approved | rejected | blocked

  // Pre-filled rejection reasons
  static const List<String> _rejectionReasons = [
    'Selfie does not match Aadhaar/License photo',
    'Name does not match documents',
    'Documents are blurred or unreadable',
    'Incomplete or missing documents',
    'Vehicle number not clearly visible in vehicle photo',
    'Vehicle photo is missing or unclear',
    'Aadhaar card details are invalid',
    'Driving license has expired',
  ];

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('drivers')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: AppTheme.primary),
          );
        }

        final allDrivers = snapshot.data!.docs.map((d) {
          final data = d.data() as Map<String, dynamic>;
          data['id'] = d.id;
          return data;
        }).toList();

        // Apply filter
        final filtered = allDrivers.where((d) {
          final isAppr = d['isApproved'] == true;
          final isBlk = d['isBlocked'] == true;
          final isRej = d['isRejected'] == true;
          if (_filter == 'pending') return !isAppr && !isBlk && !isRej;
          if (_filter == 'approved') return isAppr && !isBlk;
          if (_filter == 'rejected') return isRej && !isBlk;
          if (_filter == 'blocked') return isBlk;
          return true;
        }).toList();

        final pendingCount = allDrivers
            .where((d) =>
                d['isApproved'] != true &&
                d['isBlocked'] != true &&
                d['isRejected'] != true)
            .length;
        final approvedCount = allDrivers
            .where((d) => d['isApproved'] == true && d['isBlocked'] != true)
            .length;
        final rejectedCount = allDrivers
            .where((d) => d['isRejected'] == true && d['isBlocked'] != true)
            .length;
        final blockedCount =
            allDrivers.where((d) => d['isBlocked'] == true).length;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Document Review',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Review and verify driver documents for approval.',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppTheme.text3,
                ),
              ),
              const SizedBox(height: 20),

              // ── Filter Tabs ──
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    _filterTab('Pending', pendingCount, 'pending'),
                    _filterTab('Approved', approvedCount, 'approved'),
                    _filterTab('Rejected', rejectedCount, 'rejected'),
                    _filterTab('Blocked', blockedCount, 'blocked'),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ── Driver Cards ──
              if (filtered.isEmpty)
                _emptyState()
              else
                ...filtered.map((d) => _driverDocCard(d)),
            ],
          ),
        );
      },
    );
  }

  Widget _filterTab(String label, int count, String value) {
    final isActive = _filter == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _filter = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? AppTheme.bg : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Column(
            children: [
              Text(
                '$count',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isActive ? AppTheme.text : AppTheme.text3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  color: isActive ? AppTheme.text : AppTheme.text3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          children: [
            Icon(
              Icons.description_outlined,
              size: 48,
              color: AppTheme.text3.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              'No $_filter documents',
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppTheme.text3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'There are no drivers in this category.',
              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.text3),
            ),
          ],
        ),
      ),
    );
  }

  Widget _driverDocCard(Map<String, dynamic> d) {
    final name = d['name'] ?? 'Unknown';
    final phone = d['phone'] ?? 'N/A';
    final docs = d['documents'] as Map<String, dynamic>? ?? {};
    final selfieUrl = docs['selfieUrl'] as String?;
    final isAppr = d['isApproved'] == true;
    final isBlk = d['isBlocked'] == true;
    final isRej = d['isRejected'] == true;
    final rejectionReason = d['rejectionReason'] as String?;

    String statusLabel;
    Color statusColor;
    if (isBlk) {
      statusLabel = 'Blocked';
      statusColor = AppTheme.danger;
    } else if (isRej) {
      statusLabel = 'Rejected';
      statusColor = const Color(0xFFDC2626);
    } else if (isAppr) {
      statusLabel = 'Approved';
      statusColor = AppTheme.success;
    } else {
      statusLabel = 'Pending';
      statusColor = AppTheme.warning;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppTheme.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          // ── Header Row ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                // Photo
                ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: (selfieUrl != null && selfieUrl.isNotEmpty)
                      ? Image.network(
                          selfieUrl,
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _avatarFallback(name),
                        )
                      : _avatarFallback(name),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: AppTheme.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        phone,
                        style: GoogleFonts.inter(
                          color: AppTheme.text3,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                // Status badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    statusLabel,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Container(height: 1, color: AppTheme.borderLight),

          // ── Documents Row ──
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Documents',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.text2,
                  ),
                ),
                const SizedBox(height: 10),
                // Row 1: Selfie, Aadhaar, License
                Row(
                  children: [
                    _docThumbnail('Selfie', docs['selfieUrl'], Icons.person),
                    const SizedBox(width: 10),
                    _docThumbnail('Aadhaar', docs['aadharUrl'], Icons.credit_card),
                    const SizedBox(width: 10),
                    _docThumbnail('License', docs['licenseUrl'], Icons.badge),
                  ],
                ),
                // Row 2: Vehicle photo (if present)
                if (docs['vehicleUrl'] != null && (docs['vehicleUrl'] as String).isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _docThumbnail('Vehicle', docs['vehicleUrl'], Icons.directions_car),
                      const SizedBox(width: 10),
                      const Expanded(child: SizedBox()),
                      const Expanded(child: SizedBox()),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // ── Show rejection reason for rejected drivers ──
          if (isRej && rejectionReason != null && rejectionReason.isNotEmpty) ...[
            Container(height: 1, color: AppTheme.borderLight),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.danger.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppTheme.danger.withValues(alpha: 0.15),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: AppTheme.danger.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Rejection Reason',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.danger,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            rejectionReason,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppTheme.text2,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // ── Action Buttons (pending OR rejected — allow re-evaluation) ──
          if (!isAppr && !isBlk) ...[
            Container(height: 1, color: AppTheme.borderLight),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showRejectionSheet(d['id'], name),
                      icon: const Icon(Icons.close, size: 16),
                      label: Text(
                        isRej ? 'Re-Reject' : 'Reject',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.danger,
                        side: const BorderSide(color: AppTheme.danger),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          _updateDriverStatus(d['id'], true, false),
                      icon: const Icon(Icons.check, size: 16),
                      label: Text(
                        'Approve',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.success,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── Actions for approved ──
          if (isAppr && !isBlk) ...[
            Container(height: 1, color: AppTheme.borderLight),
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () =>
                      _updateDriverStatus(d['id'], false, true),
                  icon: const Icon(Icons.block, size: 16),
                  label: Text(
                    'Block Driver',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.danger,
                    side: const BorderSide(color: AppTheme.danger),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
          ],

          // ── Actions for blocked ──
          if (isBlk) ...[
            Container(height: 1, color: AppTheme.borderLight),
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () =>
                      _updateDriverStatus(d['id'], false, false),
                  icon: const Icon(Icons.lock_open, size: 16),
                  label: Text(
                    'Unblock Driver',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.success,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _avatarFallback(String name) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.text2,
          ),
        ),
      ),
    );
  }

  Widget _docThumbnail(String label, String? url, IconData fallback) {
    final hasImage = url != null && url.isNotEmpty;
    return Expanded(
      child: GestureDetector(
        onTap: hasImage ? () => _showFullScreenImage(url, label) : null,
        child: Column(
          children: [
            Container(
              height: 72,
              decoration: BoxDecoration(
                color: AppTheme.bg2,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border),
              ),
              child: hasImage
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: Image.network(
                        url,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        errorBuilder: (_, __, ___) => Center(
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: AppTheme.text3,
                            size: 22,
                          ),
                        ),
                      ),
                    )
                  : Center(
                      child:
                          Icon(fallback, color: AppTheme.text3, size: 24),
                    ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: AppTheme.text2,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFullScreenImage(String url, String title) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(title,
                style: GoogleFonts.inter(
                    fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white54,
                  size: 64,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Rejection Bottom Sheet ──
  void _showRejectionSheet(String driverId, String driverName) {
    List<String> selectedReasons = [];
    final customReasonController = TextEditingController();
    bool submitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                24,
                24,
                MediaQuery.of(ctx).viewInsets.bottom +
                    MediaQuery.of(ctx).padding.bottom +
                    20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppTheme.text3,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Title
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.danger.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.cancel_outlined,
                          color: AppTheme.danger,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Reject Application',
                              style: GoogleFonts.inter(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              driverName,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: AppTheme.text3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Section label
                  Text(
                    'Select reasons (Multiple allowed)',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.text2,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Pre-filled reason chips
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _rejectionReasons.map((reason) {
                      final isSelected = selectedReasons.contains(reason);
                      return GestureDetector(
                        onTap: () {
                          setSheetState(() {
                            if (isSelected) {
                              selectedReasons.remove(reason);
                            } else {
                              selectedReasons.add(reason);
                            }
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppTheme.danger.withValues(alpha: 0.1)
                                : AppTheme.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected
                                  ? AppTheme.danger
                                  : AppTheme.border,
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isSelected
                                    ? Icons.check_circle
                                    : Icons.circle_outlined,
                                size: 16,
                                color: isSelected
                                    ? AppTheme.danger
                                    : AppTheme.text3,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  reason,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    color: isSelected
                                        ? AppTheme.danger
                                        : AppTheme.text2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 18),

                  // Custom reason
                  Text(
                    'Additional Comments',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.text2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: customReasonController,
                    maxLines: 3,
                    style: GoogleFonts.inter(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Type any specific details...',
                      hintStyle: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppTheme.text3,
                      ),
                      filled: true,
                      fillColor: AppTheme.bg2,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppTheme.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppTheme.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: AppTheme.danger,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Submit button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: submitting
                          ? null
                          : () async {
                              // Combine selected reasons + custom text
                              List<String> allReasons = List.from(selectedReasons);
                              if (customReasonController.text.trim().isNotEmpty) {
                                allReasons.add(customReasonController.text.trim());
                              }

                              if (allReasons.isEmpty) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Please select at least one reason',
                                      style: GoogleFonts.inter(),
                                    ),
                                    backgroundColor: AppTheme.danger,
                                  ),
                                );
                                return;
                              }

                              // Format reason string: join with newlines for clean list display
                              final combinedReason = allReasons.length == 1 
                                  ? allReasons.first 
                                  : allReasons.map((r) => '• $r').join('\n');

                              setSheetState(() => submitting = true);

                              await FirebaseFirestore.instance
                                  .collection('drivers')
                                  .doc(driverId)
                                  .update({
                                'isApproved': false,
                                'isBlocked': false,
                                'isRejected': true,
                                'rejectionReason': combinedReason,
                                'rejectedAt': FieldValue.serverTimestamp(),
                              });

                              if (ctx.mounted) Navigator.pop(ctx);
                            },
                      icon: submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.cancel_outlined, size: 18),
                      label: Text(
                        submitting ? 'Rejecting...' : 'Reject Application',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.danger,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _updateDriverStatus(String id, bool isApproved, bool isBlocked) {
    FirebaseFirestore.instance.collection('drivers').doc(id).update({
      'isApproved': isApproved,
      'isBlocked': isBlocked,
      'isRejected': false,
      'rejectionReason': null,
    });
  }
}
