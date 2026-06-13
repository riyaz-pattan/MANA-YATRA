import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_map/flutter_map.dart' as fmap;
import 'package:latlong2/latlong.dart' as latlong2;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/providers/auth_provider.dart';

class AdCampaignScreen extends ConsumerStatefulWidget {
  const AdCampaignScreen({super.key});
  @override
  ConsumerState<AdCampaignScreen> createState() => _AdCampaignScreenState();
}

class _AdCampaignScreenState extends ConsumerState<AdCampaignScreen> {
  final _titleController = TextEditingController();
  final _actionUrlController = TextEditingController();
  Uint8List? _imageBytes;
  bool _isActive = true;
  bool _isPublishing = false;
  double _targetLat = 17.3850;
  double _targetLng = 78.4867;
  double _radiusKm = 5.0;

  @override
  void dispose() {
    _titleController.dispose();
    _actionUrlController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.pickFiles(type: FileType.image, withData: true);
    if (result != null && result.files.isNotEmpty) {
      setState(() => _imageBytes = result.files.first.bytes);
    }
  }

  Future<void> _publishCampaign() async {
    if (_titleController.text.trim().isEmpty || _imageBytes == null) {
      _showSnackBar('Please enter title and select an image', isError: true);
      return;
    }
    setState(() => _isPublishing = true);
    try {
      final storageRef = FirebaseStorage.instance.ref('promotions/campaign_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await storageRef.putData(_imageBytes!, SettableMetadata(contentType: 'image/jpeg'));
      final imageUrl = await storageRef.getDownloadURL();

      final payload = {
        'isActive': _isActive,
        'imageUrl': imageUrl,
        'title': _titleController.text.trim(),
        'actionUrl': _actionUrlController.text.trim(),
        'targetLat': _targetLat,
        'targetLng': _targetLng,
        'radiusKm': _radiusKm,
        'createdAt': FieldValue.serverTimestamp(),
      };

      if (_isActive) {
        final activeDocs = await FirebaseFirestore.instance.collection('ad_campaigns').where('isActive', isEqualTo: true).get();
        final batch = FirebaseFirestore.instance.batch();
        for (var doc in activeDocs.docs) {
          batch.update(doc.reference, {'isActive': false});
        }
        await batch.commit();
      }

      await FirebaseFirestore.instance.collection('ad_campaigns').add(payload);

      if (mounted) {
        _showSnackBar('Campaign Published!');
        setState(() {
          _titleController.clear();
          _actionUrlController.clear();
          _imageBytes = null;
        });
      }
    } catch (e) {
      if (mounted) _showSnackBar('Failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
  }

  void _toggleCampaignStatus(String id, bool currentStatus) async {
    try {
      final bool newStatus = !currentStatus;
      if (newStatus) {
        final activeDocs = await FirebaseFirestore.instance.collection('ad_campaigns').where('isActive', isEqualTo: true).get();
        final batch = FirebaseFirestore.instance.batch();
        for (var doc in activeDocs.docs) {
          batch.update(doc.reference, {'isActive': false});
        }
        batch.update(FirebaseFirestore.instance.collection('ad_campaigns').doc(id), {'isActive': true});
        await batch.commit();
      } else {
        await FirebaseFirestore.instance.collection('ad_campaigns').doc(id).update({'isActive': false});
      }
    } catch (e) {
      debugPrint('Error toggling status: $e');
    }
  }

  void _deleteCampaign(String id) async {
    try {
      await FirebaseFirestore.instance.collection('ad_campaigns').doc(id).delete();
      if (mounted) _showSnackBar('Campaign Deleted!');
    } catch (e) {
      debugPrint('Error deleting campaign: $e');
    }
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.inter(color: Colors.white)),
      backgroundColor: isError ? AppTheme.danger : AppTheme.success,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 1024;
    final bg = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final border = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;
    final text3Color = isDark ? AppTheme.darkText3 : AppTheme.lightText3;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isDesktop ? 32 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Dynamic Advertisements', style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w700, color: textColor)),
          Text('Manage and publish dynamic ad campaigns.', style: GoogleFonts.inter(color: text3Color)),
          const SizedBox(height: 32),
          if (isDesktop)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: _buildListSection(bg, border, textColor, text3Color)),
                const SizedBox(width: 32),
                Expanded(flex: 2, child: _buildCreateSection(bg, border, textColor, text3Color, isDark)),
              ],
            )
          else
            Column(
              children: [
                _buildCreateSection(bg, border, textColor, text3Color, isDark),
                const SizedBox(height: 32),
                _buildListSection(bg, border, textColor, text3Color),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildListSection(Color bg, Color border, Color textColor, Color text3Color) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Campaign History', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 16, color: textColor)),
          const SizedBox(height: 16),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('ad_campaigns').orderBy('createdAt', descending: true).snapshots(),
            builder: (ctx, snap) {
              if (snap.hasError) return Text('Error loading campaigns.', style: GoogleFonts.inter(color: AppTheme.danger));
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final docs = snap.data!.docs;
              if (docs.isEmpty) return Text('No campaigns found.', style: GoogleFonts.inter(color: text3Color));

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (ctx, i) {
                  final data = docs[i].data() as Map<String, dynamic>;
                  final id = docs[i].id;
                  final isActive = data['isActive'] ?? false;
                  final date = data['createdAt'] != null ? DateFormat.yMMMd().format((data['createdAt'] as Timestamp).toDate()) : 'Unknown';

                  return ListTile(
                    leading: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), image: DecorationImage(image: NetworkImage(data['imageUrl'] ?? ''), fit: BoxFit.cover)),
                    ),
                    title: Text(data['title'] ?? 'No Title', style: GoogleFonts.inter(color: textColor, fontWeight: FontWeight.w600)),
                    subtitle: Text('Created: $date', style: GoogleFonts.inter(color: text3Color, fontSize: 12)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(isActive ? 'Active' : 'Off', style: GoogleFonts.inter(color: isActive ? AppTheme.success : text3Color, fontWeight: FontWeight.w600)),
                        Switch(value: isActive, onChanged: (_) => _toggleCampaignStatus(id, isActive), activeColor: AppTheme.brandBlue),
                        IconButton(icon: const Icon(Icons.delete_outline, color: AppTheme.danger), onPressed: () => _deleteCampaign(id)),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCreateSection(Color bg, Color border, Color textColor, Color text3Color, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Create New', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 16, color: textColor)),
              Switch(value: _isActive, onChanged: (v) => setState(() => _isActive = v), activeColor: AppTheme.brandBlue),
            ],
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: _pickImage,
            child: Container(
              height: 120,
              width: double.infinity,
              decoration: BoxDecoration(border: Border.all(color: border), borderRadius: BorderRadius.circular(12), color: isDark ? Colors.white10 : Colors.black12),
              child: _imageBytes != null
                  ? ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(_imageBytes!, fit: BoxFit.cover))
                  : Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.upload, color: text3Color), Text('Upload Banner', style: GoogleFonts.inter(color: text3Color))]),
            ),
          ),
          const SizedBox(height: 16),
          TextField(controller: _titleController, style: GoogleFonts.inter(color: textColor), decoration: InputDecoration(hintText: 'Campaign Title', hintStyle: GoogleFonts.inter(color: text3Color), filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 16),
          TextField(controller: _actionUrlController, style: GoogleFonts.inter(color: textColor), decoration: InputDecoration(hintText: 'Action Link (Optional)', hintStyle: GoogleFonts.inter(color: text3Color), filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 16),
          Text('Radius: ${_radiusKm.toInt()} km', style: GoogleFonts.inter(color: textColor)),
          Slider(value: _radiusKm, min: 1, max: 100, divisions: 99, activeColor: AppTheme.brandBlue, onChanged: (v) => setState(() => _radiusKm = v)),
          const SizedBox(height: 8),
          Container(height: 200, decoration: BoxDecoration(border: Border.all(color: border)), child: kIsWeb ? _buildWebMap() : _buildMobileMap()),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _isPublishing ? null : _publishCampaign,
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.brandBlue),
              child: _isPublishing ? const CircularProgressIndicator(color: Colors.white) : Text('Publish', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebMap() => fmap.FlutterMap(
        options: fmap.MapOptions(initialCenter: latlong2.LatLng(_targetLat, _targetLng), initialZoom: 11, onTap: (_, p) => setState(() { _targetLat = p.latitude; _targetLng = p.longitude; })),
        children: [
          fmap.TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.gaman.admin'),
          fmap.CircleLayer(circles: [fmap.CircleMarker(point: latlong2.LatLng(_targetLat, _targetLng), color: AppTheme.brandBlue.withValues(alpha:0.2), borderColor: AppTheme.brandBlue, useRadiusInMeter: true, radius: _radiusKm * 1000)]),
        ],
      );

  Widget _buildMobileMap() => gmap.GoogleMap(
        initialCameraPosition: gmap.CameraPosition(target: gmap.LatLng(_targetLat, _targetLng), zoom: 11),
        onTap: (p) => setState(() { _targetLat = p.latitude; _targetLng = p.longitude; }),
        circles: { gmap.Circle(circleId: const gmap.CircleId('t'), center: gmap.LatLng(_targetLat, _targetLng), radius: _radiusKm * 1000, fillColor: AppTheme.brandBlue.withValues(alpha:0.2), strokeColor: AppTheme.brandBlue, strokeWidth: 2) },
      );
}
