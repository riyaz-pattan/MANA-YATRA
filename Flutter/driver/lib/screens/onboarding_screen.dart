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
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

class OnboardingScreen extends StatefulWidget {
  final bool isResubmission;

  const OnboardingScreen({super.key, this.isResubmission = false});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _nameController = TextEditingController();
  final _vehicleNumberController = TextEditingController();
  final _upiIdController = TextEditingController();
  String? _vehicleType;
  bool _showReferralField = false;
  final _referralCodeController = TextEditingController();
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
    _checkPendingReferralCode();
  }

  Future<void> _checkPendingReferralCode() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('pending_referral_code');
    if (code != null && code.isNotEmpty && mounted) {
      setState(() {
        if (code.toUpperCase().startsWith('G-')) {
          _referralCodeController.text = code.substring(2);
        } else {
          _referralCodeController.text = code;
        }
        _showReferralField = true;
      });
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
        _upiIdController.text = data['upiId'] ?? '';
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
    _upiIdController.dispose();
    _referralCodeController.dispose();
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
      useSafeArea: true,
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
          color: AppTheme.bg,
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
      useSafeArea: true,
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
      debugPrint('📤 [UPLOAD] Starting upload: $path (size: ${file.lengthSync()} bytes)');
      final compressed = await _compressImage(file);
      debugPrint('📤 [UPLOAD] Compressed: ${compressed.lengthSync()} bytes');
      final ref = FirebaseStorage.instance.ref(path);
      await ref.putFile(compressed);
      final url = await ref.getDownloadURL();
      debugPrint('📤 [UPLOAD] SUCCESS: $path → $url');
      return url;
    } catch (e) {
      debugPrint('📤 [UPLOAD] FAILED: $path → $e');
      rethrow; // Let _submit() catch it and show error to user
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
    if (_vehicleType == null) {
      setState(() => _error = 'Please select a vehicle type');
      return;
    }
    
    final upiId = _upiIdController.text.trim();
    if (upiId.isEmpty) {
      setState(() => _error = 'Please enter your UPI ID');
      return;
    }
    final upiRegex = RegExp(r'^[a-zA-Z0-9.\-_]{2,256}@[a-zA-Z]{2,64}$');
    if (!upiRegex.hasMatch(upiId)) {
      setState(() => _error = 'Please enter a valid UPI ID (e.g. 9876543210@ybl)');
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
        'upiId': upiId,
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

      // 1. Read referral code BEFORE Firestore write (before widget potentially disposes)
      final enteredReferralCode = _referralCodeController.text.trim().toUpperCase();

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

      if (mounted) {
        setState(() => _uploadProgress = 1.0);
      }

      // 2. Register referral code using the local variable
      if (!widget.isResubmission && enteredReferralCode.isNotEmpty) {
        try {
          String referralCode = enteredReferralCode;
          if (!referralCode.startsWith('G-')) {
            referralCode = 'G-$referralCode';
          }
          debugPrint('🔗 [REFERRAL] Calling registerReferral with code: $referralCode');
          final result = await FirebaseFunctions.instance
              .httpsCallable('registerReferral')
              .call({'referralCode': referralCode});
          debugPrint('🔗 [REFERRAL] registerReferral result: ${result.data}');
          
          // Clear any pending code from deep links
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('pending_referral_code');
        } catch (e) {
          debugPrint('🔗 [REFERRAL] ERROR registering referral: $e');
        }
      }

      // If resubmission, pop back (AuthGate stream will handle navigation)
      if (widget.isResubmission && mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      debugPrint('❌ [ONBOARDING] _submit error: $e');
      if (!mounted) return;
      setState(() {
        _error = e.toString().contains('permission')
            ? 'Storage permission denied. Please try again.'
            : 'Failed to submit: ${e.toString().length > 100 ? e.toString().substring(0, 100) : e}';
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
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Back button for resubmission
              if (widget.isResubmission) ...[
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      color: AppTheme.bg,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_back, size: 22, color: AppTheme.text),
                  ),
                ),
                const SizedBox(height: 24),
              ],

              Text(
                widget.isResubmission ? 'Resubmit Documents' : 'Driver Registration',
                style: GoogleFonts.outfit(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.text,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.isResubmission
                    ? 'Please review the feedback and upload correct documents.'
                    : 'Join MANA YATRA as a partner. Let\'s get you set up.',
                style: GoogleFonts.inter(fontSize: 15, color: AppTheme.text2, height: 1.4),
              ),
              const SizedBox(height: 32),

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
              ],

              _sectionTitle('Personal Details'),
              _buildTextField(
                label: 'Full Name',
                hint: 'As per Aadhaar/PAN',
                controller: _nameController,
                icon: Icons.person_outline,
                formatters: [UpperCaseTextFormatter()],
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 24),
              _buildTextField(
                label: 'Payment UPI ID',
                hint: 'e.g. 9876543210@ybl',
                controller: _upiIdController,
                keyboardType: TextInputType.emailAddress,
                icon: Icons.account_balance_wallet_outlined,
              ),

              const SizedBox(height: 40),
              _sectionTitle('Vehicle Information'),
              _label('Select Vehicle Type'),
              const SizedBox(height: 12),
              Row(
                children: AppConstants.vehicleTypes.entries.map((e) {
                  final selected = _vehicleType == e.key;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _vehicleType = e.key),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        decoration: BoxDecoration(
                          color: selected ? AppTheme.primary : AppTheme.bg,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: selected ? [
                            BoxShadow(color: AppTheme.primary.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))
                          ] : [],
                        ),
                        child: Column(
                          children: [
                            Text(e.value.icon, style: const TextStyle(fontSize: 36)),
                            const SizedBox(height: 10),
                            Text(
                              e.value.label,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                                color: selected ? Colors.white : AppTheme.text2,
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
              _buildTextField(
                label: 'Vehicle Number',
                hint: 'e.g. TS 09 AB 1234',
                controller: _vehicleNumberController,
                icon: Icons.directions_car_outlined,
                formatters: [UpperCaseTextFormatter()],
                textCapitalization: TextCapitalization.characters,
              ),

              const SizedBox(height: 40),
              _sectionTitle('Verification Documents'),
              _hintNote('Please ensure all photos are clear and readable.'),
              const SizedBox(height: 16),
              
              _photoUploader(
                label: 'Driver Profile Photo',
                file: _selfieFile,
                existingUrl: _existingSelfieUrl,
                onTap: () {
                  if (_selfieFile != null || _existingSelfieUrl != null) {
                    _showImagePreview(_selfieFile, _existingSelfieUrl);
                  } else {
                    _pickSelfie();
                  }
                },
                onLongPress: _pickSelfie,
                icon: Icons.face,
              ),
              const SizedBox(height: 16),
              
              _photoUploader(
                label: 'Aadhaar Card',
                file: _aadharFile,
                existingUrl: _existingAadharUrl,
                onTap: () {
                  if (_aadharFile != null || _existingAadharUrl != null) {
                    _showImagePreview(_aadharFile, _existingAadharUrl);
                  } else {
                    _pickDocument('aadhar');
                  }
                },
                onLongPress: () => _pickDocument('aadhar'),
                icon: Icons.badge_outlined,
              ),
              const SizedBox(height: 16),
              
              _photoUploader(
                label: 'Driving License',
                file: _licenseFile,
                existingUrl: _existingLicenseUrl,
                onTap: () {
                  if (_licenseFile != null || _existingLicenseUrl != null) {
                    _showImagePreview(_licenseFile, _existingLicenseUrl);
                  } else {
                    _pickDocument('license');
                  }
                },
                onLongPress: () => _pickDocument('license'),
                icon: Icons.fact_check_outlined,
              ),
              const SizedBox(height: 16),
              
              _photoUploader(
                label: 'Vehicle Photo (with Number Plate)',
                file: _vehicleFile,
                existingUrl: _existingVehicleUrl,
                onTap: () {
                  if (_vehicleFile != null || _existingVehicleUrl != null) {
                    _showImagePreview(_vehicleFile, _existingVehicleUrl);
                  } else {
                    _pickVehicleImage();
                  }
                },
                onLongPress: _pickVehicleImage,
                icon: Icons.directions_car_outlined,
              ),

              // Referral Code
              if (!widget.isResubmission) ...[
                const SizedBox(height: 40),
                GestureDetector(
                  onTap: () => setState(() => _showReferralField = !_showReferralField),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    decoration: BoxDecoration(
                      color: AppTheme.bg,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _showReferralField ? Icons.card_giftcard : Icons.card_giftcard_outlined,
                          size: 22,
                          color: _showReferralField ? AppTheme.accent : AppTheme.text3,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Have a referral code?',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: _showReferralField ? AppTheme.accent : AppTheme.text2,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          _showReferralField ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                          size: 22,
                          color: AppTheme.text3,
                        ),
                      ],
                    ),
                  ),
                ),
                AnimatedCrossFade(
                  firstChild: const SizedBox.shrink(),
                  secondChild: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.bg,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: TextField(
                        controller: _referralCodeController,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [UpperCaseTextFormatter()],
                        maxLength: 6,
                        onChanged: (val) {
                          final upper = val.toUpperCase();
                          if (upper.startsWith('G-')) {
                            _referralCodeController.text = upper.substring(2);
                            _referralCodeController.selection = TextSelection.collapsed(offset: _referralCodeController.text.length);
                          } else if (upper.startsWith('G') && upper.length > 1) {
                            _referralCodeController.text = upper.substring(1);
                            _referralCodeController.selection = TextSelection.collapsed(offset: _referralCodeController.text.length);
                          }
                          setState(() {});
                        },
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 2,
                        ),
                        decoration: InputDecoration(
                          prefixIcon: Padding(
                            padding: const EdgeInsets.only(left: 16, right: 4),
                            child: Text(
                              'G-',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: AppTheme.text,
                              ),
                            ),
                          ),
                          prefixIconConstraints: const BoxConstraints(minWidth: 0),
                          suffixIcon: _referralCodeController.text.trim().length == 6
                              ? const Icon(Icons.check_circle, color: AppTheme.success, size: 20)
                              : null,
                          hintText: 'XXXXXX',
                          hintStyle: GoogleFonts.inter(
                            color: AppTheme.text3,
                            letterSpacing: 2,
                          ),
                          counterText: '',
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                        ),
                      ),
                    ),
                  ),
                  crossFadeState: _showReferralField ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 250),
                ),
              ],

              const SizedBox(height: 48),

              // Progress bar
              if (_submitting && _uploadProgress > 0) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _uploadProgress,
                    backgroundColor: AppTheme.bg2,
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
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: AppTheme.danger.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.danger.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    _error,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: AppTheme.danger,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],

              // Submit
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 24,
                          height: 24,
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
                    style: GoogleFonts.inter(color: AppTheme.text3, fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Text(
        title,
        style: GoogleFonts.outfit(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: AppTheme.text,
        ),
      ),
    );
  }

  Widget _label(String text) {
    return Text(
      text,
      style: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppTheme.text2,
      ),
    );
  }

  Widget _hintNote(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 16, color: AppTheme.text3),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppTheme.text3,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required IconData icon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? formatters,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.bg,
            borderRadius: BorderRadius.circular(16),
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            inputFormatters: formatters,
            textCapitalization: textCapitalization,
            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w500, color: AppTheme.text),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.inter(color: AppTheme.text3, fontSize: 15),
              prefixIcon: Icon(icon, color: AppTheme.text3),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            ),
          ),
        ),
      ],
    );
  }

  void _showImagePreview(File? file, String? url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: file != null
              ? Image.file(file, fit: BoxFit.contain)
              : Image.network(url!, fit: BoxFit.contain),
        ),
      ),
    );
  }

  Widget _photoUploader({
    required String label,
    required File? file,
    required String? existingUrl,
    required VoidCallback onTap,
    required VoidCallback onLongPress,
    required IconData icon,
  }) {
    final bool hasFile = file != null || existingUrl != null;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: hasFile ? AppTheme.success.withValues(alpha: 0.05) : AppTheme.bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasFile ? AppTheme.success.withValues(alpha: 0.3) : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: hasFile ? AppTheme.success : AppTheme.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                hasFile ? Icons.check : icon,
                color: hasFile ? Colors.white : AppTheme.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasFile ? 'Tap to preview • Long press to change' : 'Tap to upload document',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: hasFile ? AppTheme.success : AppTheme.text3,
                    ),
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
