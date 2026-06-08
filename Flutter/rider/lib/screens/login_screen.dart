// lib/screens/login_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pinput/pinput.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  String _step = 'phone'; // 'phone' | 'otp'
  bool _loading = false;
  String _error = '';
  String? _verificationId;
  int? _resendToken;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
    _checkIfKickedOut();
  }

  Future<void> _checkIfKickedOut() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('kicked_out') == true) {
      if (mounted) {
        setState(() {
          _error = 'Session expired: Logged in from another device.';
        });
      }
      await prefs.remove('kicked_out');
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final phone = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    if (phone.length < 10) {
      setState(() => _error = 'Enter a valid 10-digit phone number');
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });

    debugPrint('Sending OTP to +91$phone');
    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: '+91$phone',
        verificationCompleted: (PhoneAuthCredential credential) async {
          debugPrint(
            'FirebaseAuth: verificationCompleted! Auto-retrieval successful. smsCode: ${credential.smsCode}',
          );
          if (credential.smsCode != null && mounted) {
            _otpController.text = credential.smsCode!;
          }
          try {
            await FirebaseAuth.instance.signInWithCredential(credential);
            debugPrint(
              'FirebaseAuth: Successfully signed in via auto-retrieval.',
            );
          } catch (e) {
            debugPrint(
              'FirebaseAuth: Error signing in after auto-retrieval: $e',
            );
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          debugPrint(
            'FirebaseAuth: verificationFailed! Error: ${e.code} - ${e.message}',
          );
          if (!mounted) return;
          setState(() {
            _error = e.message ?? 'Failed to send OTP. Try again.';
            _loading = false;
          });
        },
        codeSent: (String verificationId, int? resendToken) {
          debugPrint('FirebaseAuth: codeSent! verificationId: $verificationId');
          if (!mounted) return;
          setState(() {
            _verificationId = verificationId;
            _resendToken = resendToken;
            _step = 'otp';
            _loading = false;
          });
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          debugPrint(
            'FirebaseAuth: codeAutoRetrievalTimeout! id: $verificationId',
          );
          _verificationId = verificationId;
        },
        forceResendingToken: _resendToken,
        timeout: const Duration(seconds: 60),
      );
    } catch (e) {
      debugPrint('FirebaseAuth: Exception in verifyPhoneNumber: $e');
      if (!mounted) return;
      setState(() {
        _error = 'Failed to send OTP. Try again.';
        _loading = false;
      });
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _otpController.text;
    if (otp.length != 6) {
      setState(() => _error = 'Enter the 6-digit OTP');
      return;
    }
    // Guard against duplicate calls (from onCompleted + button tap)
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: otp,
      );
      // Sign in — AuthGate in main.dart will detect the auth state change
      // and navigate to MainScreen or ProfileSetupScreen automatically.
      await FirebaseAuth.instance.signInWithCredential(credential);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Invalid OTP. Please try again.';
        _loading = false;
      });
    }
  }

  // Navigation handled by auth state listener in main.dart

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F0E1A), Color(0xFF1A1929)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: FadeTransition(
                opacity: _fadeAnim,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withValues(alpha: 0.3),
                            blurRadius: 40,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: const Text('🛺', style: TextStyle(fontSize: 52)),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Gaman',
                      style: GoogleFonts.inter(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Zero commission rides, fair prices',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        color: AppTheme.text2,
                      ),
                    ),
                    const SizedBox(height: 48),

                    // Card
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxWidth: 360),
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: AppTheme.bg,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppTheme.border),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 64,
                            offset: const Offset(0, 24),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _step == 'phone'
                                ? 'Enter your number'
                                : 'Verify OTP',
                            style: GoogleFonts.inter(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _step == 'phone'
                                ? "We'll send a 6-digit OTP via SMS"
                                : 'OTP sent to +91 ${_phoneController.text}',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: AppTheme.text2,
                            ),
                          ),
                          const SizedBox(height: 28),
                          if (_step == 'phone') ...[
                            _buildPhoneInput(),
                            const SizedBox(height: 16),
                            _buildPrimaryButton(
                              'Send OTP →',
                              _sendOtp,
                              enabled:
                                  _phoneController.text
                                      .replaceAll(RegExp(r'\D'), '')
                                      .length >=
                                  10,
                            ),
                          ] else ...[
                            _buildOtpInput(),
                            const SizedBox(height: 16),
                            _buildPrimaryButton(
                              'Verify & Continue →',
                              _verifyOtp,
                              enabled: _otpController.text.length == 6,
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: TextButton(
                                onPressed: () {
                                  setState(() {
                                    _step = 'phone';
                                    _otpController.clear();
                                    _error = '';
                                  });
                                },
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: const BorderSide(
                                      color: AppTheme.border,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  '← Change number',
                                  style: GoogleFonts.inter(
                                    color: AppTheme.text2,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                          if (_error.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
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
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'By continuing, you agree to our Terms & Privacy Policy',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppTheme.text3,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
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
      style: GoogleFonts.inter(fontSize: 16),
      decoration: InputDecoration(
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 16, right: 8),
          child: Text(
            '+91',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: AppTheme.text2,
            ),
          ),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0),
        hintText: '9876543210',
        counterText: '',
      ),
      onSubmitted: (_) => _sendOtp(),
    );
  }

  Widget _buildOtpInput() {
    return Pinput(
      length: 6,
      controller: _otpController,
      autofocus: true,
      onChanged: (_) => setState(() {}),
      onCompleted: (_) => _verifyOtp(),
      defaultPinTheme: PinTheme(
        width: 44,
        height: 52,
        textStyle: GoogleFonts.inter(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: AppTheme.text,
        ),
        decoration: BoxDecoration(
          color: AppTheme.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
      ),
      focusedPinTheme: PinTheme(
        width: 44,
        height: 52,
        textStyle: GoogleFonts.inter(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: AppTheme.text,
        ),
        decoration: BoxDecoration(
          color: AppTheme.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.primary, width: 2),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withValues(alpha: 0.2),
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
      submittedPinTheme: PinTheme(
        width: 44,
        height: 52,
        textStyle: GoogleFonts.inter(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: AppTheme.text,
        ),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.primary),
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
      height: 54,
      child: ElevatedButton(
        onPressed: _loading || !enabled ? null : onPressed,
        child: _loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Text(label),
      ),
    );
  }
}
