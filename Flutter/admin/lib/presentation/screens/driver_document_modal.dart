import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/theme/app_theme.dart';

class DriverDocumentModal extends StatelessWidget {
  final String driverId;
  final Map<String, dynamic> documents;
  final bool isDark;

  const DriverDocumentModal({
    super.key,
    required this.driverId,
    required this.documents,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;
    final text2Color = isDark ? AppTheme.darkText2 : AppTheme.lightText2;
    final surfaceColor = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;

    return Dialog(
      backgroundColor: surfaceColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Verify Documents',
                  style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700, color: textColor),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: text2Color),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  _buildDocViewer(context, 'Selfie', documents['selfieUrl'] as String?, textColor, text2Color),
                  _buildDocViewer(context, 'Driving License', documents['licenseUrl'] as String?, textColor, text2Color),
                  _buildDocViewer(context, 'RC Book', documents['rcBookUrl'] as String?, textColor, text2Color),
                  _buildDocViewer(context, 'Vehicle Photo', documents['vehicleUrl'] as String?, textColor, text2Color),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () async {
                    await FirebaseFirestore.instance.collection('drivers').doc(driverId).update({
                      'isApproved': true,
                      'isBlocked': false,
                    });
                    if (context.mounted) Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.success,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Approve Driver'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocViewer(BuildContext context, String title, String? url, Color textColor, Color text2Color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: textColor)),
          const SizedBox(height: 8),
          if (url != null && url.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                url,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  height: 200,
                  color: Colors.grey.withValues(alpha: 0.1),
                  child: Center(child: Text('Error loading image', style: TextStyle(color: text2Color))),
                ),
              ),
            )
          else
            Container(
              height: 100,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
              ),
              child: Center(
                child: Text('No Document Provided', style: TextStyle(color: text2Color)),
              ),
            ),
        ],
      ),
    );
  }
}
