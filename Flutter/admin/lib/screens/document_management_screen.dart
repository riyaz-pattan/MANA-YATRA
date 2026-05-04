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
  String _filter = 'pending'; // pending | approved | blocked

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
          if (_filter == 'pending') return !isAppr && !isBlk;
          if (_filter == 'approved') return isAppr && !isBlk;
          if (_filter == 'blocked') return isBlk;
          return true;
        }).toList();

        final pendingCount = allDrivers
            .where((d) => d['isApproved'] != true && d['isBlocked'] != true)
            .length;
        final approvedCount = allDrivers
            .where((d) => d['isApproved'] == true && d['isBlocked'] != true)
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
                  fontSize: 12,
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

    String statusLabel;
    Color statusColor;
    if (isBlk) {
      statusLabel = 'Blocked';
      statusColor = AppTheme.danger;
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
                Row(
                  children: [
                    _docThumbnail('Selfie', docs['selfieUrl'], Icons.person),
                    const SizedBox(width: 10),
                    _docThumbnail(
                        'Aadhaar', docs['aadharUrl'], Icons.credit_card),
                    const SizedBox(width: 10),
                    _docThumbnail(
                        'License', docs['licenseUrl'], Icons.badge),
                  ],
                ),
              ],
            ),
          ),

          // ── Action Buttons (only for pending) ──
          if (!isAppr && !isBlk) ...[
            Container(height: 1, color: AppTheme.borderLight),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _updateDriverStatus(d['id'], false, true),
                      icon: const Icon(Icons.close, size: 16),
                      label: Text(
                        'Reject',
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

  void _updateDriverStatus(String id, bool isApproved, bool isBlocked) {
    FirebaseFirestore.instance.collection('drivers').doc(id).update({
      'isApproved': isApproved,
      'isBlocked': isBlocked,
    });
  }
}
