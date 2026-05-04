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
  const OnboardingScreen({super.key});
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
  bool _submitting = false;
  String _error = '';
  double _uploadProgress = 0;
  final _picker = ImagePicker();

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

  Future<void> _pickSelfie() async {
    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      maxWidth: 1200,
      imageQuality: 70,
    );
    if (picked != null) {
      setState(() => _selfieFile = File(picked.path));
    }
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
    if (_selfieFile == null) {
      setState(() => _error = 'Please take a selfie');
      return;
    }
    if (_aadharFile == null || _licenseFile == null) {
      setState(() => _error = 'Please upload both documents');
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
      final selfieUrl = await _uploadFile(
        _selfieFile!,
        'drivers/$uid/selfie.jpg',
      );
      setState(() => _uploadProgress = 0.4);
      final aadharUrl = await _uploadFile(
        _aadharFile!,
        'drivers/$uid/aadhar.jpg',
      );
      setState(() => _uploadProgress = 0.7);
      final licenseUrl = await _uploadFile(
        _licenseFile!,
        'drivers/$uid/license.jpg',
      );
      setState(() => _uploadProgress = 0.9);

      await FirebaseFirestore.instance.collection('drivers').doc(uid).set({
        'name': _nameController.text.trim(),
        'phone': phone,
        'vehicleType': _vehicleType,
        'vehicleNumber': _vehicleNumberController.text.trim().toUpperCase(),
        'documents': {
          'selfieUrl': selfieUrl,
          'aadharUrl': aadharUrl,
          'licenseUrl': licenseUrl,
        },
        'isApproved': false,
        'isBlocked': false,
        'isOnline': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      setState(() => _uploadProgress = 1.0);
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
                const SizedBox(height: 20),
                const Text('🧑‍✈️', style: TextStyle(fontSize: 40)),
                const SizedBox(height: 12),
                Text(
                  'Complete Your Profile',
                  style: GoogleFonts.inter(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tell us about yourself and your vehicle',
                  style: GoogleFonts.inter(fontSize: 15, color: AppTheme.text2),
                ),
                const SizedBox(height: 32),

                // Selfie
                _label('Your Photo'),
                _hintNote(
                  Icons.camera_alt_outlined,
                  'Take a clear selfie. Must match your Aadhaar & Driving License photo.',
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
                      child: _docUploader(
                        'Aadhaar Card',
                        _aadharFile,
                        'aadhar',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _docUploader(
                        'Driving License',
                        _licenseFile,
                        'license',
                      ),
                    ),
                  ],
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
                            'Submit for Review →',
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
                    onPressed: () => FirebaseAuth.instance.signOut(),
                    child: Text(
                      'Logout',
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
    return GestureDetector(
      onTap: _pickSelfie,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 140,
        height: 140,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _selfieFile != null
              ? AppTheme.success.withValues(alpha: 0.1)
              : AppTheme.surface,
          border: Border.all(
            color: _selfieFile != null ? AppTheme.success : AppTheme.border,
            width: _selfieFile != null ? 3 : 2,
          ),
          boxShadow: _selfieFile != null
              ? [
                  BoxShadow(
                    color: AppTheme.success.withValues(alpha: 0.2),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: _selfieFile != null
            ? ClipOval(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(_selfieFile!, fit: BoxFit.cover),
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
                              'Retake',
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
                    Icons.camera_alt_outlined,
                    color: AppTheme.text3,
                    size: 36,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Take Selfie',
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
    return GestureDetector(
      onTap: () => _pickDocument(type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 120,
        decoration: BoxDecoration(
          color: file != null
              ? AppTheme.success.withValues(alpha: 0.1)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: file != null ? AppTheme.success : AppTheme.border,
            width: file != null ? 2 : 1,
          ),
        ),
        child: file != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(file, fit: BoxFit.cover),
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
                              'Tap to change',
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
