// lib/screens/onboarding_screen.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import '../config/theme.dart';
import '../config/constants.dart';

class OnboardingScreen extends StatefulWidget {
  final bool isResubmission;

  const OnboardingScreen({super.key, this.isResubmission = false});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _nameController = TextEditingController();
  final _vehicleNumberController = TextEditingController();
  String _vehicleType = 'auto';
  File? _selfieFile;
  File? _aadharFile;
  File? _licenseFile;
  File? _vehicleFile;
  String? _existingSelfieUrl;
  String? _existingAadharUrl;
  String? _existingLicenseUrl;
  String? _existingVehicleUrl;
  String? _rejectionReason;
  bool _submitting = false;
  String _error = '';
  double _uploadProgress = 0;
  final _picker = ImagePicker();
  bool _loadingProfile = false;

  @override
  void initState() {
    super.initState();
    if (widget.isResubmission) {
      _prefillFromExistingProfile();
    }
  }

  Future<void> _prefillFromExistingProfile() async {
    setState(() => _loadingProfile = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final doc = await FirebaseFirestore.instance
          .collection('drivers')
          .doc(uid)
          .get();
      if (doc.exists) {
        final data = doc.data()!;
        _nameController.text = data['name'] ?? '';
        _vehicleNumberController.text = data['vehicleNumber'] ?? '';
        if (data['vehicleType'] != null &&
            AppConstants.vehicleTypes.containsKey(data['vehicleType'])) {
          _vehicleType = data['vehicleType'];
        }
        final docs = data['documents'] as Map<String, dynamic>?;
        if (docs != null) {
          _existingSelfieUrl = docs['selfieUrl'];
          _existingAadharUrl = docs['aadharUrl'];
          _existingLicenseUrl = docs['licenseUrl'];
          _existingVehicleUrl = docs['vehicleUrl'];
        }
        _rejectionReason = data['rejectionReason'];
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingProfile = false);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _vehicleNumberController.dispose();
    super.dispose();
  }

  Future<File> _compressImage(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final original = img.decodeImage(bytes);
      if (original == null) return file;
      img.Image resized;
      if (original.width > 800) {
        resized = img.copyResize(original, width: 800);
      } else {
        resized = original;
      }
      final compressed = img.encodeJpg(resized, quality: 60);
      final tempDir = Directory.systemTemp;
      final tempFile = File(
        '${tempDir.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await tempFile.writeAsBytes(Uint8List.fromList(compressed));
      return tempFile;
    } catch (e) {
      return file;
    }
  }

  /// Show a dialog to choose Camera or Gallery for selfie
  Future<void> _pickSelfie() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppTheme.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.text3,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Choose Photo Source',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Take a selfie or choose from gallery',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppTheme.text3,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _sourceOption(
                        icon: Icons.camera_alt_outlined,
                        label: 'Camera',
                        onTap: () =>
                            Navigator.pop(ctx, ImageSource.camera),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _sourceOption(
                        icon: Icons.photo_library_outlined,
                        label: 'Gallery',
                        onTap: () =>
                            Navigator.pop(ctx, ImageSource.gallery),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );

    if (source == null) return;

    final picked = await _picker.pickImage(
      source: source,
      preferredCameraDevice: CameraDevice.front,
      maxWidth: 1200,
      imageQuality: 70,
    );
    if (picked != null) {
      setState(() => _selfieFile = File(picked.path));
    }
  }

  Widget _sourceOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: AppTheme.primary),
            const SizedBox(height: 8),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.text,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDocument(String type) async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      imageQuality: 70,
    );
    if (picked != null) {
      setState(() {
        if (type == 'aadhar') {
          _aadharFile = File(picked.path);
        } else {
          _licenseFile = File(picked.path);
        }
      });
    }
  }

  /// Pick the vehicle image — allows both Camera and Gallery
  Future<void> _pickVehicleImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppTheme.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: AppTheme.text3, borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(height: 20),
                Text('Vehicle Photo Source', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text('Make sure the number plate is clearly visible', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.text3)),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(child: _sourceOption(icon: Icons.camera_alt_outlined, label: 'Camera', onTap: () => Navigator.pop(ctx, ImageSource.camera))),
                    const SizedBox(width: 12),
                    Expanded(child: _sourceOption(icon: Icons.photo_library_outlined, label: 'Gallery', onTap: () => Navigator.pop(ctx, ImageSource.gallery))),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
    if (source == null) return;
    final picked = await _picker.pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 75,
    );
    if (picked != null) setState(() => _vehicleFile = File(picked.path));
  }

  Future<String?> _uploadFile(File file, String path) async {
    try {
      final compressed = await _compressImage(file);
      final ref = FirebaseStorage.instance.ref(path);
      await ref.putFile(compressed);
      return await ref.getDownloadURL();
    } catch (e) {
      return null;
    }
  }

  Future<void> _submit() async {
    if (_nameController.text.trim().isEmpty) {
      setState(() => _error = 'Please enter your name');
      return;
    }
    if (_vehicleNumberController.text.trim().isEmpty) {
      setState(() => _error = 'Please enter your vehicle number');
      return;
    }
    if (_selfieFile == null && _existingSelfieUrl == null) {
      setState(() => _error = 'Please take a selfie');
      return;
    }
    if ((_aadharFile == null && _existingAadharUrl == null) || 
        (_licenseFile == null && _existingLicenseUrl == null)) {
      setState(() => _error = 'Please upload Aadhaar Card and Driving License');
      return;
    }
    if (_vehicleFile == null && _existingVehicleUrl == null) {
      setState(() => _error = 'Please upload a vehicle photo showing the number plate');
      return;
    }
    setState(() {
      _submitting = true;
      _error = '';
      _uploadProgress = 0;
    });
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final phone = FirebaseAuth.instance.currentUser!.phoneNumber;

      setState(() => _uploadProgress = 0.1);
      final selfieUrl = _selfieFile != null 
          ? await _uploadFile(_selfieFile!, 'drivers/$uid/selfie.jpg')
          : _existingSelfieUrl;

      setState(() => _uploadProgress = 0.35);
      final aadharUrl = _aadharFile != null 
          ? await _uploadFile(_aadharFile!, 'drivers/$uid/aadhar.jpg')
          : _existingAadharUrl;

      setState(() => _uploadProgress = 0.6);
      final licenseUrl = _licenseFile != null 
          ? await _uploadFile(_licenseFile!, 'drivers/$uid/license.jpg')
          : _existingLicenseUrl;

      setState(() => _uploadProgress = 0.8);
      final vehicleUrl = _vehicleFile != null 
          ? await _uploadFile(_vehicleFile!, 'drivers/$uid/vehicle.jpg')
          : _existingVehicleUrl;

      setState(() => _uploadProgress = 0.9);

      final profileData = {
        'name': _nameController.text.trim(),
        'phone': phone,
        'vehicleType': _vehicleType,
        'vehicleNumber': _vehicleNumberController.text.trim().toUpperCase(),
        'documents': {
          'selfieUrl': selfieUrl,
          'aadharUrl': aadharUrl,
          'licenseUrl': licenseUrl,
          'vehicleUrl': vehicleUrl,
        },
        'isApproved': false,
        'isBlocked': false,
        'isRejected': false,
        'rejectionReason': null,
        'isOnline': false,
      };

      if (widget.isResubmission) {
        // Merge so we don't overwrite createdAt, subscription fields, etc.
        await FirebaseFirestore.instance
            .collection('drivers')
            .doc(uid)
            .set(profileData, SetOptions(merge: true));
      } else {
        // First time — include createdAt
        profileData['createdAt'] = FieldValue.serverTimestamp();
        await FirebaseFirestore.instance
            .collection('drivers')
            .doc(uid)
            .set(profileData);
      }

      setState(() => _uploadProgress = 1.0);

      // If resubmission, pop back (AuthGate stream will handle navigation)
      if (widget.isResubmission && mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to submit. Try again.';
        _submitting = false;
        _uploadProgress = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingProfile) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.primary),
        ),
      );
    }

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppTheme.bg, AppTheme.bg2],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Back button for resubmission
                if (widget.isResubmission) ...[
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.arrow_back, size: 20),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                const SizedBox(height: 4),
                const Text('🧑‍✈️', style: TextStyle(fontSize: 40)),
                const SizedBox(height: 12),
                Text(
                  widget.isResubmission
                      ? 'Resubmit Your Documents'
                      : 'Complete Your Profile',
                  style: GoogleFonts.inter(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.isResubmission
                      ? 'Please upload clear photos to get approved'
                      : 'Tell us about yourself and your vehicle',
                  style: GoogleFonts.inter(fontSize: 15, color: AppTheme.text2),
                ),
                const SizedBox(height: 24),

                // Rejection reasons display for resubmission
                if (widget.isResubmission && _rejectionReason != null && _rejectionReason!.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.danger.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppTheme.danger.withValues(alpha: 0.15),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.info_outline, size: 16, color: AppTheme.danger),
                            const SizedBox(width: 8),
                            Text(
                              'Reasons for Rejection',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.danger,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _rejectionReason!,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: AppTheme.text,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                ] else ...[
                  const SizedBox(height: 8),
                ],

                // Selfie
                _label('Your Photo'),
                _hintNote(
                  Icons.camera_alt_outlined,
                  'Take a clear selfie or choose from gallery. Must match your Aadhaar & Driving License photo.',
                ),
                const SizedBox(height: 12),
                Center(child: _selfieCapture()),
                const SizedBox(height: 28),

                // Name
                _label('Full Name'),
                _hintNote(
                  Icons.info_outline,
                  'Name must match exactly as on your Aadhaar & PAN card.',
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameController,
                  style: GoogleFonts.inter(fontSize: 15),
                  decoration: const InputDecoration(
                    hintText: 'e.g. Rajesh Kumar',
                  ),
                ),
                const SizedBox(height: 24),

                // Vehicle type
                _label('Vehicle Type'),
                Row(
                  children: AppConstants.vehicleTypes.entries.map((e) {
                    final selected = _vehicleType == e.key;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _vehicleType = e.key),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: selected
                                ? AppTheme.primary.withValues(alpha: 0.2)
                                : AppTheme.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: selected
                                  ? AppTheme.primary
                                  : AppTheme.border,
                              width: selected ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(
                                e.value.icon,
                                style: const TextStyle(fontSize: 32),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                e.value.label,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: selected
                                      ? AppTheme.primary
                                      : AppTheme.text2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),

                // Vehicle number
                _label('Vehicle Number'),
                TextField(
                  controller: _vehicleNumberController,
                  textCapitalization: TextCapitalization.characters,
                  style: GoogleFonts.inter(fontSize: 15),
                  decoration: const InputDecoration(
                    hintText: 'e.g. TS 09 AB 1234',
                  ),
                ),
                const SizedBox(height: 28),

                // Documents
                _label('Documents'),
                _hintNote(
                  Icons.verified_user_outlined,
                  'Name & photo on documents must match your selfie and name above.',
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _docUploader('Aadhaar Card', _aadharFile, 'aadhar'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _docUploader('Driving License', _licenseFile, 'license'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Vehicle photo
                _label('Vehicle Photo'),
                _hintNote(
                  Icons.directions_car_outlined,
                  'Photo must show the vehicle clearly with the number plate fully visible. This helps verify your vehicle details.',
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: _pickVehicleImage,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: double.infinity,
                    height: 140,
                    decoration: BoxDecoration(
                      color: (_vehicleFile != null || _existingVehicleUrl != null)
                          ? AppTheme.success.withValues(alpha: 0.08)
                          : AppTheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: (_vehicleFile != null || _existingVehicleUrl != null) ? AppTheme.success : AppTheme.border,
                        width: (_vehicleFile != null || _existingVehicleUrl != null) ? 2 : 1,
                      ),
                    ),
                    child: (_vehicleFile != null || _existingVehicleUrl != null)
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(13),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                _vehicleFile != null 
                                    ? Image.file(_vehicleFile!, fit: BoxFit.cover)
                                    : Image.network(_existingVehicleUrl!, fit: BoxFit.cover),
                                Container(
                                  color: Colors.black.withValues(alpha: 0.35),
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.check_circle, color: AppTheme.success, size: 32),
                                        const SizedBox(height: 6),
                                        Text(_vehicleFile != null ? 'Vehicle photo added' : 'Existing photo kept', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                                        const SizedBox(height: 2),
                                        Text('Tap to change', style: GoogleFonts.inter(fontSize: 10, color: Colors.white70)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.directions_car_outlined, color: AppTheme.text3, size: 36),
                              const SizedBox(height: 8),
                              Text('Tap to add vehicle photo', style: GoogleFonts.inter(color: AppTheme.text3, fontSize: 13, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Text('Camera or Gallery', style: GoogleFonts.inter(color: AppTheme.text3, fontSize: 11)),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 32),

                // Progress bar
                if (_submitting && _uploadProgress > 0) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: _uploadProgress,
                      backgroundColor: AppTheme.surface2,
                      color: AppTheme.primary,
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _uploadProgress < 0.9
                        ? 'Uploading documents…'
                        : 'Saving your profile…',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppTheme.text3,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Error
                if (_error.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppTheme.danger.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppTheme.danger.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      _error,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: AppTheme.danger,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],

                // Submit
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            widget.isResubmission
                                ? 'Resubmit for Review →'
                                : 'Submit for Review →',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () {
                      if (widget.isResubmission) {
                        Navigator.of(context).pop();
                      } else {
                        FirebaseAuth.instance.signOut();
                      }
                    },
                    child: Text(
                      widget.isResubmission ? 'Go Back' : 'Logout',
                      style: GoogleFonts.inter(color: AppTheme.text3),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppTheme.text2,
        ),
      ),
    );
  }

  Widget _hintNote(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: AppTheme.warning),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 11.5,
                color: AppTheme.warning,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _selfieCapture() {
    final bool hasImage = _selfieFile != null || _existingSelfieUrl != null;
    return GestureDetector(
      onTap: _pickSelfie,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 140,
        height: 140,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: hasImage
              ? AppTheme.success.withValues(alpha: 0.1)
              : AppTheme.surface,
          border: Border.all(
            color: hasImage ? AppTheme.success : AppTheme.border,
            width: hasImage ? 3 : 2,
          ),
          boxShadow: hasImage
              ? [
                  BoxShadow(
                    color: AppTheme.success.withValues(alpha: 0.2),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: hasImage
            ? ClipOval(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _selfieFile != null 
                        ? Image.file(_selfieFile!, fit: BoxFit.cover)
                        : Image.network(_existingSelfieUrl!, fit: BoxFit.cover),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.7),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.check_circle,
                              color: AppTheme.success,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _selfieFile != null ? 'Change' : 'Existing',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.add_a_photo_outlined,
                    color: AppTheme.text3,
                    size: 36,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add Photo',
                    style: GoogleFonts.inter(
                      color: AppTheme.text3,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _docUploader(String label, File? file, String type) {
    String? existingUrl;
    if (type == 'aadhar') existingUrl = _existingAadharUrl;
    if (type == 'license') existingUrl = _existingLicenseUrl;

    final bool hasImage = file != null || existingUrl != null;

    return GestureDetector(
      onTap: () => _pickDocument(type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 120,
        decoration: BoxDecoration(
          color: hasImage
              ? AppTheme.success.withValues(alpha: 0.1)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasImage ? AppTheme.success : AppTheme.border,
            width: hasImage ? 2 : 1,
          ),
        ),
        child: hasImage
            ? ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    file != null 
                        ? Image.file(file, fit: BoxFit.cover)
                        : Image.network(existingUrl!, fit: BoxFit.cover),
                    Container(
                      color: Colors.black.withValues(alpha: 0.4),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.check_circle,
                              color: AppTheme.success,
                              size: 28,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              label,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              file != null ? 'Tap to change' : 'Existing file',
                              style: GoogleFonts.inter(
                                fontSize: 9,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.cloud_upload_outlined,
                      color: AppTheme.text3,
                      size: 28,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: AppTheme.text3,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
