import sys

with open('/Users/rameez/Desktop/MANA YATRA/Flutter/driver/lib/screens/onboarding_screen.dart', 'r') as f:
    lines = f.readlines()

start_idx = -1
for i, line in enumerate(lines):
    if line.strip().startswith('Widget build(BuildContext context)'):
        start_idx = i
        break

if start_idx != -1:
    new_content = """  @override
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
                      color: AppTheme.surface,
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
                    : 'Join MANA YATRA as a partner. Let\\'s get you set up.',
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
                          color: selected ? AppTheme.primary : AppTheme.surface,
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
                      color: AppTheme.surface,
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
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: TextField(
                        controller: _referralCodeController,
                        textCapitalization: TextCapitalization.characters,
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
            color: AppTheme.surface,
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
          color: hasFile ? AppTheme.success.withValues(alpha: 0.05) : AppTheme.surface,
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
"""

    lines = lines[:start_idx-1]
    with open('/Users/rameez/Desktop/MANA YATRA/Flutter/driver/lib/screens/onboarding_screen.dart', 'w') as f:
        f.writelines(lines)
        f.write(new_content)
