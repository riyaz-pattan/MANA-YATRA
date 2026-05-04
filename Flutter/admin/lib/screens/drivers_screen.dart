// lib/screens/drivers_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/theme.dart';

class DriversScreen extends StatefulWidget {
  const DriversScreen({super.key});
  @override
  State<DriversScreen> createState() => _DriversScreenState();
}

class _DriversScreenState extends State<DriversScreen> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('drivers')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: AppTheme.primary),
          );
        }

        final drivers = snap.data!.docs.map((d) {
          final data = d.data() as Map<String, dynamic>;
          data['id'] = d.id;
          return data;
        }).toList();

        final filtered = drivers.where((d) {
          final isAppr = d['isApproved'] == true || d['isApproved'] == 'true';
          final isBlk = d['isBlocked'] == true || d['isBlocked'] == 'true';
          if (_filter == 'pending') return !isAppr && !isBlk;
          if (_filter == 'approved') return isAppr && !isBlk;
          if (_filter == 'blocked') return isBlk;
          return true;
        }).toList();

        final pendingCount = drivers.where((d) {
          final isAppr = d['isApproved'] == true || d['isApproved'] == 'true';
          final isBlk = d['isBlocked'] == true || d['isBlocked'] == 'true';
          return !isAppr && !isBlk;
        }).length;

        final approvedCount = drivers.where((d) {
          final isAppr = d['isApproved'] == true || d['isApproved'] == 'true';
          final isBlk = d['isBlocked'] == true || d['isBlocked'] == 'true';
          return isAppr && !isBlk;
        }).length;

        final onlineCount = drivers
            .where((d) => d['isOnline'] == true || d['isOnline'] == 'true')
            .length;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('🧑‍✈️ Drivers',
                  style: GoogleFonts.inter(
                      fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('Manage driver approvals and access',
                  style:
                      GoogleFonts.inter(fontSize: 14, color: AppTheme.text3)),
              const SizedBox(height: 24),

              // Stats
              Row(children: [
                _statCard('Pending', pendingCount, AppTheme.warning),
                const SizedBox(width: 12),
                _statCard('Approved', approvedCount, AppTheme.success),
                const SizedBox(width: 12),
                _statCard('Online', onlineCount, AppTheme.primary),
              ]),
              const SizedBox(height: 20),

              // Filters
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: ['all', 'pending', 'approved', 'blocked']
                      .map((f) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _filterChip(
                                f,
                                f == 'all'
                                    ? 'All (${drivers.length})'
                                    : f == 'pending'
                                        ? 'Pending ($pendingCount)'
                                        : f[0].toUpperCase() +
                                            f.substring(1)),
                          ))
                      .toList(),
                ),
              ),
              const SizedBox(height: 16),

              // Driver cards
              ...filtered.map((driver) => _driverCard(driver)),

              if (filtered.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Text('No drivers found',
                        style: GoogleFonts.inter(color: AppTheme.text3)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _statCard(String label, int value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$value',
                style: GoogleFonts.inter(
                    fontSize: 28, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 4),
            Text(label,
                style: GoogleFonts.inter(fontSize: 12, color: AppTheme.text3)),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String key, String label) {
    final selected = _filter == key;
    return GestureDetector(
      onTap: () => setState(() => _filter = key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : AppTheme.surface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: selected ? Colors.white : AppTheme.text2,
            )),
      ),
    );
  }

  Widget _driverCard(Map<String, dynamic> driver) {
    final icons = {'auto': '🛺', 'bike': '🏍️'};
    final icon = icons[driver['vehicleType']] ?? '🏍️';
    final docs = driver['documents'] as Map<String, dynamic>?;
    final selfieUrl = docs?['selfieUrl'] as String?;

    final totalAssigned = driver['totalAssignedRides'] as int? ?? 0;
    final totalCancelled = driver['totalCancelledRides'] as int? ?? 0;
    double cancelRate = 0.0;
    if (totalAssigned > 0) {
      cancelRate = (totalCancelled / totalAssigned) * 100;
    }

    return GestureDetector(
      onTap: () => _showDriverDetails(driver),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            // Driver photo or vehicle icon
            if (selfieUrl != null && selfieUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.network(selfieUrl,
                    width: 48, height: 48, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Text(icon, style: const TextStyle(fontSize: 32))),
              )
            else
              Text(icon, style: const TextStyle(fontSize: 32)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(driver['name'] ?? 'N/A',
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text(driver['phone'] ?? '',
                      style: GoogleFonts.inter(
                          color: AppTheme.text3, fontSize: 12)),
                  Text(driver['vehicleNumber'] ?? '',
                      style: GoogleFonts.inter(
                          color: AppTheme.text3, fontSize: 12)),
                  if (totalAssigned > 0)
                    Text(
                      'Cancel Rate: ${cancelRate.toStringAsFixed(1)}% ($totalCancelled/$totalAssigned)',
                      style: GoogleFonts.inter(
                        color: cancelRate > 20 ? AppTheme.danger : AppTheme.text3,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _statusBadge(driver),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // View documents button
                    _actionBtn('👁', AppTheme.primary,
                        () => _showDriverDetails(driver)),
                    ..._buildActions(driver),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Document Viewer Dialog ──
  void _showDriverDetails(Map<String, dynamic> driver) {
    final docs = driver['documents'] as Map<String, dynamic>?;
    final selfieUrl = docs?['selfieUrl'] as String?;
    final aadharUrl = docs?['aadharUrl'] as String?;
    final licenseUrl = docs?['licenseUrl'] as String?;
    final icons = {'auto': '🛺', 'bike': '🏍️'};
    final vIcon = icons[driver['vehicleType']] ?? '🏍️';
    final isAppr =
        driver['isApproved'] == true || driver['isApproved'] == 'true';
    final isBlk =
        driver['isBlocked'] == true || driver['isBlocked'] == 'true';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (_, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: AppTheme.bg2,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.all(24),
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: AppTheme.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Driver info header
              Row(children: [
                if (selfieUrl != null && selfieUrl.isNotEmpty)
                  GestureDetector(
                    onTap: () => _showFullScreenImage(selfieUrl, 'Driver Photo'),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(32),
                      child: Image.network(selfieUrl,
                          width: 64, height: 64, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                                width: 64, height: 64,
                                decoration: BoxDecoration(
                                  color: AppTheme.surface,
                                  borderRadius: BorderRadius.circular(32),
                                ),
                                child: const Icon(Icons.person,
                                    color: AppTheme.text3, size: 32),
                              )),
                    ),
                  )
                else
                  Container(
                    width: 64, height: 64,
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(32),
                    ),
                    child: Center(
                        child: Text(vIcon,
                            style: const TextStyle(fontSize: 32))),
                  ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(driver['name'] ?? 'N/A',
                          style: GoogleFonts.inter(
                              fontSize: 20, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(driver['phone'] ?? '',
                          style: GoogleFonts.inter(
                              color: AppTheme.text3, fontSize: 13)),
                      Row(children: [
                        Text('$vIcon ',
                            style: const TextStyle(fontSize: 14)),
                        Text(driver['vehicleNumber'] ?? '',
                            style: GoogleFonts.inter(
                                color: AppTheme.text2,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                      ]),
                    ],
                  ),
                ),
                _statusBadge(driver),
              ]),
              const SizedBox(height: 24),

              // Section: Documents
              Text('📄 Uploaded Documents',
                  style: GoogleFonts.inter(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Tap any document to view full screen',
                  style: GoogleFonts.inter(
                      fontSize: 12, color: AppTheme.text3)),
              const SizedBox(height: 16),

              // Selfie
              _docCard('Driver Selfie', selfieUrl, Icons.person),
              const SizedBox(height: 12),
              // Aadhaar
              _docCard('Aadhaar Card', aadharUrl, Icons.credit_card),
              const SizedBox(height: 12),
              // License
              _docCard('Driving License', licenseUrl, Icons.badge),
              const SizedBox(height: 28),

              // Action buttons
              if (!isAppr && !isBlk) ...[
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await FirebaseFirestore.instance
                          .collection('drivers')
                          .doc(driver['id'])
                          .update({'isApproved': true, 'isBlocked': false});
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text('Approve Driver',
                        style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.success,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (isAppr && !isBlk)
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await FirebaseFirestore.instance
                          .collection('drivers')
                          .doc(driver['id'])
                          .update({'isApproved': false});
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.undo),
                    label: Text('Revoke Approval',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.warning,
                      side: const BorderSide(color: AppTheme.warning),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await FirebaseFirestore.instance
                        .collection('drivers')
                        .doc(driver['id'])
                        .update({'isBlocked': !isBlk, 'isOnline': false});
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  icon: Icon(isBlk ? Icons.lock_open : Icons.block),
                  label: Text(isBlk ? 'Unblock Driver' : 'Block Driver',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor:
                        isBlk ? AppTheme.success : AppTheme.danger,
                    side: BorderSide(
                        color:
                            isBlk ? AppTheme.success : AppTheme.danger),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _docCard(String label, String? url, IconData fallbackIcon) {
    final hasImage = url != null && url.isNotEmpty;
    return GestureDetector(
      onTap: hasImage ? () => _showFullScreenImage(url, label) : null,
      child: Container(
        height: 180,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
        ),
        child: hasImage
            ? ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: Stack(fit: StackFit.expand, children: [
                  Image.network(url, fit: BoxFit.cover,
                      loadingBuilder: (_, child, progress) {
                    if (progress == null) return child;
                    return Center(
                      child: CircularProgressIndicator(
                        value: progress.expectedTotalBytes != null
                            ? progress.cumulativeBytesLoaded /
                                progress.expectedTotalBytes!
                            : null,
                        color: AppTheme.primary,
                        strokeWidth: 2,
                      ),
                    );
                  }, errorBuilder: (_, __, ___) => _docPlaceholder(
                          label, fallbackIcon, isError: true)),
                  Positioned(
                    bottom: 0, left: 0, right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.8),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: Row(children: [
                        Icon(fallbackIcon,
                            color: Colors.white70, size: 16),
                        const SizedBox(width: 8),
                        Text(label,
                            style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                        const Spacer(),
                        const Icon(Icons.zoom_in,
                            color: Colors.white54, size: 18),
                      ]),
                    ),
                  ),
                ]),
              )
            : _docPlaceholder(label, fallbackIcon),
      ),
    );
  }

  Widget _docPlaceholder(String label, IconData icon,
      {bool isError = false}) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(isError ? Icons.broken_image_outlined : icon,
            color: AppTheme.text3, size: 36),
        const SizedBox(height: 8),
        Text(isError ? 'Failed to load' : 'Not uploaded',
            style: GoogleFonts.inter(
                color: AppTheme.text3,
                fontSize: 13,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        Text(label,
            style:
                GoogleFonts.inter(color: AppTheme.text3, fontSize: 11)),
      ]),
    );
  }

  // ── Full-screen image viewer ──
  void _showFullScreenImage(String url, String title) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (_, __, ___) => _FullScreenImageViewer(
            url: url, title: title),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  Widget _statusBadge(Map<String, dynamic> driver) {
    final isAppr =
        driver['isApproved'] == true || driver['isApproved'] == 'true';
    final isBlk =
        driver['isBlocked'] == true || driver['isBlocked'] == 'true';
    final isOnline =
        driver['isOnline'] == true || driver['isOnline'] == 'true';

    if (isBlk) return _badge('Blocked', AppTheme.danger);
    if (isAppr) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _badge('Approved', AppTheme.success),
          if (isOnline) ...[
            const SizedBox(height: 4),
            _badge('Online', AppTheme.primary),
          ],
        ],
      );
    }
    return _badge('Pending', AppTheme.warning);
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: GoogleFonts.inter(
              fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }

  List<Widget> _buildActions(Map<String, dynamic> driver) {
    final actions = <Widget>[];
    final isAppr =
        driver['isApproved'] == true || driver['isApproved'] == 'true';
    final isBlk =
        driver['isBlocked'] == true || driver['isBlocked'] == 'true';

    if (!isAppr && !isBlk) {
      actions.add(_actionBtn('✓', AppTheme.success, () async {
        await FirebaseFirestore.instance
            .collection('drivers')
            .doc(driver['id'])
            .update({'isApproved': true, 'isBlocked': false});
      }));
    }

    if (isAppr && !isBlk) {
      actions.add(_actionBtn('↩', AppTheme.text3, () async {
        await FirebaseFirestore.instance
            .collection('drivers')
            .doc(driver['id'])
            .update({'isApproved': false});
      }));
    }

    actions.add(_actionBtn(
      isBlk ? '🔓' : '🔒',
      isBlk ? AppTheme.success : AppTheme.danger,
      () async {
        await FirebaseFirestore.instance
            .collection('drivers')
            .doc(driver['id'])
            .update({'isBlocked': !isBlk, 'isOnline': false});
      },
    ));

    return actions;
  }

  Widget _actionBtn(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label, style: const TextStyle(fontSize: 14)),
      ),
    );
  }
}

// ── Full Screen Image Viewer ──
class _FullScreenImageViewer extends StatelessWidget {
  final String url;
  final String title;
  const _FullScreenImageViewer({required this.url, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title,
            style: GoogleFonts.inter(
                fontSize: 16, fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.network(
            url,
            fit: BoxFit.contain,
            loadingBuilder: (_, child, progress) {
              if (progress == null) return child;
              return Center(
                child: CircularProgressIndicator(
                  value: progress.expectedTotalBytes != null
                      ? progress.cumulativeBytesLoaded /
                          progress.expectedTotalBytes!
                      : null,
                  color: AppTheme.primary,
                ),
              );
            },
            errorBuilder: (_, __, ___) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.broken_image_outlined,
                    color: Colors.white54, size: 64),
                const SizedBox(height: 16),
                Text('Failed to load image',
                    style: GoogleFonts.inter(color: Colors.white54)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
