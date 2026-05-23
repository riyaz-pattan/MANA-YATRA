// lib/presentation/screens/document_management_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/auth_provider.dart';

class DocumentManagementScreen extends ConsumerStatefulWidget {
  const DocumentManagementScreen({super.key});

  @override
  ConsumerState<DocumentManagementScreen> createState() => _DocumentManagementScreenState();
}

class _DocumentManagementScreenState extends ConsumerState<DocumentManagementScreen> {
  String _filter = 'pending';
  static const List<String> _rejectionReasons = [
    'Selfie does not match Aadhaar/License photo',
    'Name does not match documents',
    'Documents are blurred or unreadable',
    'Incomplete or missing documents',
    'Vehicle number not clearly visible',
    'Aadhaar card details are invalid',
    'Driving license has expired',
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 1024;
    
    final bg = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final border = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;
    final text3Color = isDark ? AppTheme.darkText3 : AppTheme.lightText3;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('drivers').orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final allDrivers = snapshot.data!.docs.map((d) {
          final data = d.data() as Map<String, dynamic>;
          data['id'] = d.id;
          return data;
        }).toList();

        final pendingCount = allDrivers.where((d) => d['isApproved'] != true && d['isBlocked'] != true && d['isRejected'] != true).length;
        final approvedCount = allDrivers.where((d) => d['isApproved'] == true && d['isBlocked'] != true).length;
        final rejectedCount = allDrivers.where((d) => d['isRejected'] == true && d['isBlocked'] != true).length;
        final blockedCount = allDrivers.where((d) => d['isBlocked'] == true).length;

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

        return SingleChildScrollView(
          padding: EdgeInsets.all(isDesktop ? 32 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Document Review', style: GoogleFonts.inter(fontSize: isDesktop ? 24 : 20, fontWeight: FontWeight.w700, color: textColor)),
              const SizedBox(height: 8),
              Text('Review and verify driver KYC documents.', style: GoogleFonts.inter(fontSize: 14, color: text3Color)),
              const SizedBox(height: 32),

              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
                child: Row(
                  children: [
                    _filterTab('Pending', pendingCount, 'pending', isDark),
                    _filterTab('Approved', approvedCount, 'approved', isDark),
                    _filterTab('Rejected', rejectedCount, 'rejected', isDark),
                    _filterTab('Blocked', blockedCount, 'blocked', isDark),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              if (filtered.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 60),
                    child: Text('No $_filter documents', style: GoogleFonts.inter(fontSize: 16, color: text3Color)),
                  ),
                )
              else
                ...filtered.map((d) => _driverDocCard(d, isDark, bg, border, textColor, text3Color)),
            ],
          ),
        );
      },
    );
  }

  Widget _filterTab(String label, int count, String value, bool isDark) {
    final isActive = _filter == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _filter = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isActive ? (isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Text('$count', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700, color: isActive ? (isDark ? AppTheme.darkText : AppTheme.lightText) : (isDark ? AppTheme.darkText3 : AppTheme.lightText3))),
              const SizedBox(height: 4),
              Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: isActive ? FontWeight.w600 : FontWeight.w500, color: isActive ? (isDark ? AppTheme.darkText : AppTheme.lightText) : (isDark ? AppTheme.darkText3 : AppTheme.lightText3))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _driverDocCard(Map<String, dynamic> d, bool isDark, Color bg, Color border, Color textColor, Color text3Color) {
    final name = d['name'] ?? 'Unknown';
    final phone = d['phone'] ?? 'N/A';
    final docs = d['documents'] as Map<String, dynamic>? ?? {};
    final isAppr = d['isApproved'] == true;
    final isBlk = d['isBlocked'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: border)),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                CircleAvatar(backgroundColor: isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2, child: Icon(Icons.person, color: text3Color)),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 16, color: textColor)),
                      Text(phone, style: GoogleFonts.inter(color: text3Color, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(color: border, height: 1),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                _docThumbnail('Selfie', docs['selfieUrl'], Icons.person, text3Color),
                const SizedBox(width: 16),
                _docThumbnail('Aadhaar', docs['aadharUrl'], Icons.credit_card, text3Color),
                const SizedBox(width: 16),
                _docThumbnail('License', docs['licenseUrl'], Icons.badge, text3Color),
                const SizedBox(width: 16),
                _docThumbnail('Vehicle', docs['vehicleUrl'], Icons.directions_car, text3Color),
              ],
            ),
          ),
          if (!isAppr && !isBlk) ...[
            Divider(color: border, height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _showRejectionSheet(d['id'], name, isDark),
                      style: OutlinedButton.styleFrom(foregroundColor: AppTheme.danger, side: const BorderSide(color: AppTheme.danger), padding: const EdgeInsets.symmetric(vertical: 16)),
                      child: const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => FirebaseFirestore.instance.collection('drivers').doc(d['id']).update({'isApproved': true, 'isRejected': false}),
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)),
                      child: const Text('Approve Document'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _docThumbnail(String label, String? url, IconData fallback, Color text3Color) {
    final hasImage = url != null && url.isNotEmpty;
    return Expanded(
      child: GestureDetector(
        onTap: hasImage ? () => _showFullScreenImage(url, label) : null,
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Container(
                decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(8)),
                child: hasImage
                    ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(Icons.broken_image, color: text3Color)))
                    : Icon(fallback, color: text3Color),
              ),
            ),
            const SizedBox(height: 8),
            Text(label, style: GoogleFonts.inter(fontSize: 12, color: text3Color)),
          ],
        ),
      ),
    );
  }

  void _showFullScreenImage(String url, String title) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => Scaffold(backgroundColor: Colors.black, appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(title)), body: Center(child: InteractiveViewer(child: Image.network(url))))));
  }

  void _showRejectionSheet(String driverId, String driverName, bool isDark) {
    List<String> selectedReasons = [];
    final customReasonController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Reject $driverName', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? AppTheme.darkText : AppTheme.lightText)),
              const SizedBox(height: 16),
              ..._rejectionReasons.map((reason) => CheckboxListTile(
                    title: Text(reason, style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText)),
                    value: selectedReasons.contains(reason),
                    onChanged: (val) {
                      setSheetState(() {
                        if (val == true) selectedReasons.add(reason);
                        else selectedReasons.remove(reason);
                      });
                    },
                  )),
              const SizedBox(height: 16),
              TextField(
                controller: customReasonController,
                decoration: const InputDecoration(labelText: 'Other reason (optional)', border: OutlineInputBorder()),
                style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final reasonStr = selectedReasons.join(', ') + (customReasonController.text.isNotEmpty ? ' - ${customReasonController.text}' : '');
                    FirebaseFirestore.instance.collection('drivers').doc(driverId).update({'isRejected': true, 'isApproved': false, 'rejectionReason': reasonStr});
                    Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: const Text('Confirm Rejection'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
