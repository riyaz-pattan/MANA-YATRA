with open('/Users/rameez/Desktop/MANA YATRA/Flutter/rider/lib/screens/login_screen.dart', 'r') as f:
    content = f.read()

parts = content.split('  @override\n  Widget build(BuildContext context) {')
if len(parts) == 2:
    new_content = parts[0] + """  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 48),
                Center(
                  child: Text(
                    'GAMAN',
                    style: GoogleFonts.manrope(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Colors.black,
                      letterSpacing: 8,
                    ),
                  ),
                ),
                const SizedBox(height: 80),
                Text(
                  _step == 'phone' ? 'Enter your number' : 'Verify OTP',
                  style: GoogleFonts.manrope(
                    fontSize: 32,
                    fontWeight: FontWeight.w300,
                    color: Colors.black,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _step == 'phone'
                      ? "We'll send a 6-digit code to verify your account."
                      : 'Code sent to +91 ${_phoneController.text}',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    color: Colors.grey[700],
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 48),
                if (_step == 'phone') ...[
                  _buildPhoneInput(),
                  const Spacer(),
                  _buildPrimaryButton(
                    'CONTINUE',
                    _sendOtp,
                    enabled: _phoneController.text.replaceAll(RegExp(r'\D'), '').length >= 10,
                  ),
                ] else ...[
                  _buildOtpInput(),
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () {
                        setState(() {
                          _step = 'phone';
                          _otpController.clear();
                          _error = '';
                        });
                      },
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'Change number',
                        style: GoogleFonts.inter(
                          color: Colors.black,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  _buildPrimaryButton(
                    'VERIFY',
                    _verifyOtp,
                    enabled: _otpController.text.length == 6,
                  ),
                ],
                if (_error.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error,
                    style: GoogleFonts.inter(
                      color: Colors.red[800],
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Center(
                  child: Text(
                    'By continuing, you agree to our Terms & Privacy Policy',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.grey[500],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneInput() {
    return TextField(
      controller: _phoneController,
      keyboardType: TextInputType.phone,
      maxLength: 10,
      onChanged: (_) => setState(() {}),
      style: GoogleFonts.inter(fontSize: 20, color: Colors.black, fontWeight: FontWeight.w500),
      cursorColor: Colors.black,
      decoration: InputDecoration(
        prefixIcon: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Text(
            '+91',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w400,
              fontSize: 20,
              color: Colors.black,
            ),
          ),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        hintText: '00000 00000',
        hintStyle: GoogleFonts.inter(color: Colors.grey[400], fontSize: 20),
        counterText: '',
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.black, width: 1),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.black, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
      ),
      onSubmitted: (_) => _sendOtp(),
    );
  }

  Widget _buildOtpInput() {
    return Pinput(
      length: 6,
      controller: _otpController,
      autofocus: false,
      onChanged: (_) => setState(() {}),
      onCompleted: (_) => _verifyOtp(),
      separatorBuilder: (index) => const SizedBox(width: 8),
      defaultPinTheme: PinTheme(
        width: 48,
        height: 60,
        textStyle: GoogleFonts.inter(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: Colors.black,
        ),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.grey, width: 1)),
        ),
      ),
      focusedPinTheme: PinTheme(
        width: 48,
        height: 60,
        textStyle: GoogleFonts.inter(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: Colors.black,
        ),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.black, width: 2)),
        ),
      ),
      submittedPinTheme: PinTheme(
        width: 48,
        height: 60,
        textStyle: GoogleFonts.inter(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: Colors.black,
        ),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.black, width: 1)),
        ),
      ),
    );
  }

  Widget _buildPrimaryButton(
    String label,
    VoidCallback onPressed, {
    bool enabled = true,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _loading || !enabled ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          disabledBackgroundColor: Colors.grey[300],
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.grey[500],
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
          ),
          elevation: 0,
        ),
        child: _loading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2,
                ),
              ),
      ),
    );
  }
}
"""
    with open('/Users/rameez/Desktop/MANA YATRA/Flutter/rider/lib/screens/login_screen.dart', 'w') as f:
        f.write(new_content)
    print("Replacement done.")
else:
    print("Could not find build method")
