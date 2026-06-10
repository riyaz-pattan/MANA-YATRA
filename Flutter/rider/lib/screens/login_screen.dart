// lib/screens/login_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pinput/pinput.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_auth/smart_auth.dart';

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
    SmartAuth.instance.removeUserConsentApiListener();
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
    
    // START LISTENING IMMEDIATELY BEFORE TRIGGERING FIREBASE
    // If we wait for the OTP screen to build, the SMS might arrive too early!
    _listenForSmsConsent();

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: '+91$phone',
        timeout: Duration.zero, // Disables native Firebase SMS auto-retrieval to prevent crashes
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

  Future<void> _listenForSmsConsent() async {
    try {
      final res = await SmartAuth.instance.getSmsWithUserConsentApi();
      if (res.hasData && mounted) {
        final code = res.requireData.code;
        if (code != null && code.length == 6) {
          setState(() {
            _otpController.text = code;
          });
          
          // Wait up to 2 seconds if _verificationId is still null (SMS arrived extremely fast)
          for (int i = 0; i < 10; i++) {
            if (_verificationId != null) break;
            await Future.delayed(const Duration(milliseconds: 200));
          }

          if (_verificationId != null) {
            _verifyOtp();
          }
        }
      } else if (res.isCanceled) {
        debugPrint('SmartAuth: User denied SMS consent.');
      }
    } catch (e) {
      debugPrint('SmartAuth: Consent API failed or was interrupted: $e');
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
      backgroundColor: Colors.white,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: CustomScrollView(
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                  child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 32),
                // App Logo
                Center(
                  child: Image.asset(
                    'assets/images/logo/foreground.png',
                    width: 130,
                    height: 130,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  _step == 'phone' ? 'Welcome to\nGaman.' : 'Verify your\nnumber.',
                  style: GoogleFonts.manrope(
                    fontSize: 42,
                    fontWeight: FontWeight.w200,
                    color: Colors.black,
                    height: 1.1,
                    letterSpacing: -1.5,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _step == 'phone'
                      ? "Enter your mobile number to begin your premium journey."
                      : "We've sent a 6-digit security code to\n+91 ${_phoneController.text}.",
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    color: Colors.grey[600],
                    height: 1.6,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 64),
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
      ],
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
