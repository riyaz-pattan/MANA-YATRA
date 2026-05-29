// lib/screens/subscription_screen.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:uuid/uuid.dart';
import '../config/theme.dart';
import '../config/constants.dart';
import '../providers/driver_provider.dart';
import '../utils/custom_toast.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});
  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen>
    with TickerProviderStateMixin {
  bool _processing = false;
  int _selectedPlanIndex = 1; // Default to 7-day plan
  bool _activatingTrial = false;

  // Payment overlay state
  bool _showPaymentOverlay = false;
  String _overlayStatus = 'verifying'; // 'verifying', 'success', 'failed'
  String _overlayMessage = '';
  String _overlaySubtitle = '';

  // Animation controllers
  late AnimationController _coinController;
  late AnimationController _pulseController;
  late AnimationController _successController;
  late Animation<double> _coinBounce;
  late Animation<double> _pulseAnimation;
  late Animation<double> _successScale;

  late Razorpay _razorpay;

  List<Map<String, dynamic>> get _plans => AppConstants.subscriptionPlans;

  int get _selectedDays => _plans[_selectedPlanIndex]['days'] as int;
  int get _selectedTotal => _plans[_selectedPlanIndex]['totalPrice'] as int;

  bool get _hasFreeTrialUsed {
    final provider = context.read<DriverProvider>();
    return provider.profile?['hasFreeTrialUsed'] == true;
  }

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);

    // Coin bounce animation (continuously during verification)
    _coinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _coinBounce = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _coinController, curve: Curves.easeInOut),
    );

    // Pulse animation for the glow
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Success checkmark scale
    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _successScale = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _successController, curve: Curves.elasticOut),
    );
  }

  @override
  void dispose() {
    _razorpay.clear();
    _coinController.dispose();
    _pulseController.dispose();
    _successController.dispose();
    super.dispose();
  }

  // ── Payment Overlay ──────────────────────────────────────────

  void _showVerifyingOverlay() {
    setState(() {
      _showPaymentOverlay = true;
      _overlayStatus = 'verifying';
      _overlayMessage = 'Verifying Payment';
      _overlaySubtitle = 'Please wait while we confirm your payment...';
    });
    _coinController.repeat(reverse: true);
    _pulseController.repeat(reverse: true);
    _successController.reset();
  }

  void _showSuccessOverlay(String validUntil) {
    _coinController.stop();
    _pulseController.stop();
    setState(() {
      _overlayStatus = 'success';
      _overlayMessage = 'Payment Successful! 🎉';
      _overlaySubtitle = 'Valid until $validUntil';
    });
    _successController.forward();
  }

  void _showFailedOverlay(String reason) {
    _coinController.stop();
    _pulseController.stop();
    setState(() {
      _overlayStatus = 'failed';
      _overlayMessage = 'Payment Failed';
      _overlaySubtitle = reason;
    });
    _successController.forward();
  }

  void _dismissOverlay() {
    _coinController.stop();
    _pulseController.stop();
    _successController.reset();
    setState(() {
      _showPaymentOverlay = false;
      _processing = false;
    });
  }

  // ── Razorpay Handlers ────────────────────────────────────────

  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    // Close the bottom sheet if it's open
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }

    // Show verifying overlay immediately
    if (mounted) {
      _showVerifyingOverlay();
    }

    try {
      debugPrint('[Razorpay] Payment success, verifying...');
      final callable =
          FirebaseFunctions.instance.httpsCallable('verifyRazorpayPayment');
      final result = await callable.call({
        'razorpay_order_id': response.orderId,
        'razorpay_payment_id': response.paymentId,
        'razorpay_signature': response.signature,
        'planIndex': _selectedPlanIndex,
        'operationId': const Uuid().v4(),
      });

      if (mounted) {
        final validUntil = result.data['validUntil'] as String?;
        String formattedDate = 'Subscription activated!';
        if (validUntil != null) {
          try {
            final date = DateTime.parse(validUntil).toLocal();
            formattedDate =
                DateFormat('dd MMM yyyy, hh:mm a').format(date);
          } catch (_) {}
        }
        _showSuccessOverlay(formattedDate);
      }
    } catch (e) {
      debugPrint('[Razorpay] Verification error: $e');
      if (mounted) {
        _showFailedOverlay(
            'Payment received but verification failed.\nPlease contact support.');
      }
    }
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    // Close the bottom sheet if it's open
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }

    if (mounted) {
      setState(() => _processing = false);
      // Show a brief toast — no overlay for cancellations
      final msg = response.message ?? 'Payment was cancelled or failed.';
      // Try to parse Razorpay error for a user-friendly message
      String friendlyMsg = 'Payment was cancelled.';
      if (msg.contains('cancelled') || msg.contains('cancel')) {
        friendlyMsg = 'Payment cancelled by user.';
      } else if (msg.contains('failed')) {
        friendlyMsg = 'Payment failed. Please try again.';
      }
      CustomToast.show(
        context: context,
        message: friendlyMsg,
        isError: true,
      );
    }
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    if (mounted) {
      CustomToast.show(
        context: context,
        message: 'Redirecting to ${response.walletName}...',
      );
    }
  }

  // ── Free Trial ───────────────────────────────────────────────

  Future<void> _activateFreeTrial() async {
    setState(() => _activatingTrial = true);
    try {
      await FirebaseFunctions.instance.httpsCallable('startFreeTrial').call();

      if (mounted) {
        CustomToast.show(
          context: context,
          message: '🎉 7-day free trial activated!',
        );
      }
    } catch (e) {
      if (mounted) {
        CustomToast.show(
          context: context,
          message: 'Failed to activate trial. Try again.',
          isError: true,
        );
      }
    }
    if (mounted) setState(() => _activatingTrial = false);
  }

  // ── Razorpay Payment Flow ────────────────────────────────────

  Future<void> _initiatePayment() async {
    setState(() => _processing = true);

    try {
      debugPrint(
          '[Razorpay] Starting payment for planIndex: $_selectedPlanIndex');

      // Step 1: Create order via Cloud Function (server-side pricing)
      final callable =
          FirebaseFunctions.instance.httpsCallable('createRazorpayOrder');
      debugPrint('[Razorpay] Calling createRazorpayOrder Cloud Function...');
      final result = await callable.call({'planIndex': _selectedPlanIndex});
      debugPrint('[Razorpay] Cloud Function response: ${result.data}');

      final orderId = result.data['orderId'] as String;
      final amount = result.data['amount'] as int;
      debugPrint(
          '[Razorpay] Order created: $orderId, amount: $amount paise');

      // Step 2: Get driver info for prefill
      final provider = context.read<DriverProvider>();
      final driverName = provider.profile?['name'] ?? 'Driver';
      final driverPhone = provider.profile?['phone'] ?? '';

      // Step 3: Open Razorpay checkout
      final options = {
        'key': AppConstants.razorpayKeyId,
        'amount': amount,
        'order_id': orderId,
        'name': 'Gaman',
        'description': '$_selectedDays Day Subscription',
        'prefill': {
          'contact': driverPhone,
          'name': driverName,
        },
        'theme': {
          'color': '#6C63FF',
        },
      };

      debugPrint('[Razorpay] Opening checkout with options: $options');
      _razorpay.open(options);
    } catch (e, stackTrace) {
      debugPrint('[Razorpay] ERROR: $e');
      debugPrint('[Razorpay] ERROR type: ${e.runtimeType}');
      if (e is FirebaseFunctionsException) {
        debugPrint('[Razorpay] Function error code: ${e.code}');
        debugPrint('[Razorpay] Function error message: ${e.message}');
        debugPrint('[Razorpay] Function error details: ${e.details}');
      }
      debugPrint('[Razorpay] Stack trace: $stackTrace');
      if (mounted) {
        setState(() => _processing = false);
        String errorMessage = 'Failed to create order. Please try again.';
        if (e is FirebaseFunctionsException) {
          errorMessage = e.message ?? errorMessage;
        }
        CustomToast.show(
          context: context,
          message: errorMessage,
          isError: true,
        );
      }
    }
  }

  // ── Subscription Bottom Sheet ────────────────────────────────

  void _showSubscriptionSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheetState) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
                24,
                24,
                24,
                MediaQuery.of(ctx).viewInsets.bottom +
                    MediaQuery.of(ctx).padding.bottom +
                    20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppTheme.text3,
                      borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(height: 24),
                Text('Choose Plan',
                    style: GoogleFonts.inter(
                        fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text('Select a duration to extend your active time.',
                    style: GoogleFonts.inter(
                        fontSize: 14, color: AppTheme.text2)),
                const SizedBox(height: 24),
                ...List.generate(_plans.length, (index) {
                  final plan = _plans[index];
                  final days = plan['days'] as int;
                  final totalPrice = plan['totalPrice'] as int;
                  final perDay = plan['perDay'] as int;
                  final selected = _selectedPlanIndex == index;

                  // Calculate savings for multi-day plans
                  final baseDailyRate = _plans[0]['perDay'] as int;
                  final savings =
                      days > 1 ? (baseDailyRate * days) - totalPrice : 0;

                  return GestureDetector(
                    onTap: () {
                      setSheetState(() => _selectedPlanIndex = index);
                      setState(() {}); // Update parent state too
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppTheme.primary.withValues(alpha: 0.1)
                            : AppTheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: selected ? AppTheme.primary : AppTheme.border,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(plan['emoji'] as String,
                              style: const TextStyle(fontSize: 32)),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(plan['label'] as String,
                                        style: GoogleFonts.inter(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w700)),
                                    if (savings > 0) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: AppTheme.success
                                              .withValues(alpha: 0.15),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          'Save ₹$savings',
                                          style: GoogleFonts.inter(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: AppTheme.success,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '₹$perDay/day',
                                  style: GoogleFonts.inter(
                                      fontSize: 13, color: AppTheme.text3),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '₹$totalPrice',
                            style: GoogleFonts.inter(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: selected
                                  ? AppTheme.primary
                                  : AppTheme.text2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 8),
                // Secure payment badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock, size: 14, color: AppTheme.text3),
                    const SizedBox(width: 4),
                    Text(
                      'Secured by Razorpay',
                      style: GoogleFonts.inter(
                          fontSize: 12, color: AppTheme.text3),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _processing
                        ? null
                        : () async {
                            setSheetState(() => _processing = true);
                            await _initiatePayment();
                            // Don't reset _processing here — Razorpay handlers will do it
                          },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.success),
                    child: _processing
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white)),
                              const SizedBox(width: 12),
                              Text('Processing...',
                                  style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14)),
                            ],
                          )
                        : Text('Pay ₹$_selectedTotal',
                            style: GoogleFonts.inter(
                                fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  // ── Payment Overlay Widget ───────────────────────────────────

  Widget _buildPaymentOverlay() {
    return AnimatedOpacity(
      opacity: _showPaymentOverlay ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: Container(
        color: Colors.black.withValues(alpha: 0.85),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Animated icon area
                  SizedBox(
                    height: 180,
                    child: _overlayStatus == 'verifying'
                        ? _buildVerifyingAnimation()
                        : _overlayStatus == 'success'
                            ? _buildSuccessAnimation()
                            : _buildFailedAnimation(),
                  ),
                  const SizedBox(height: 32),
                  // Title
                  Text(
                    _overlayMessage,
                    style: GoogleFonts.inter(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  // Subtitle
                  Text(
                    _overlaySubtitle,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      color: Colors.white.withValues(alpha: 0.7),
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  // Done button (only for success/failed)
                  if (_overlayStatus != 'verifying') ...[
                    const SizedBox(height: 40),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _dismissOverlay,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _overlayStatus == 'success'
                              ? AppTheme.success
                              : AppTheme.text3,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        child: Text(
                          _overlayStatus == 'success'
                              ? 'Continue'
                              : 'Close',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVerifyingAnimation() {
    return AnimatedBuilder(
      animation: Listenable.merge([_coinController, _pulseController]),
      builder: (context, child) {
        final bounceY = sin(_coinBounce.value * pi) * -30;
        final pulse = _pulseAnimation.value;
        final rotation = _coinBounce.value * pi * 2;

        return Stack(
          alignment: Alignment.center,
          children: [
            // Pulsing glow ring
            Container(
              width: 140 * pulse,
              height: 140 * pulse,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF6C63FF).withValues(alpha: 0.3 * pulse),
                  width: 3,
                ),
              ),
            ),
            // Second ring
            Container(
              width: 110 * pulse,
              height: 110 * pulse,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF6C63FF).withValues(alpha: 0.2 * pulse),
                  width: 2,
                ),
              ),
            ),
            // Bouncing coin
            Transform.translate(
              offset: Offset(0, bounceY),
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.001)
                  ..rotateY(rotation),
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      '₹',
                      style: GoogleFonts.inter(
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSuccessAnimation() {
    return AnimatedBuilder(
      animation: _successScale,
      builder: (context, child) {
        return Transform.scale(
          scale: _successScale.value,
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF4CAF50), Color(0xFF66BB6A)],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4CAF50).withValues(alpha: 0.4),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: const Icon(
              Icons.check_rounded,
              size: 64,
              color: Colors.white,
            ),
          ),
        );
      },
    );
  }

  Widget _buildFailedAnimation() {
    return AnimatedBuilder(
      animation: _successScale,
      builder: (context, child) {
        return Transform.scale(
          scale: _successScale.value,
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFE53935), Color(0xFFEF5350)],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE53935).withValues(alpha: 0.4),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: const Icon(
              Icons.close_rounded,
              size: 64,
              color: Colors.white,
            ),
          ),
        );
      },
    );
  }

  // ── UI Builder Methods ───────────────────────────────────────

  Widget _buildFreeTrialCard() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF6C63FF),
            Color(0xFF9B59B6),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6C63FF).withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Decorative circles
          Positioned(
            top: -20,
            right: -20,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
          ),
          Positioned(
            bottom: -30,
            left: -15,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.star,
                        size: 14,
                        color: Colors.amber,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'FREE TRIAL',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                Text(
                  'Start Your 7-Day\nFree Trial',
                  style: GoogleFonts.inter(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 12),

                Text(
                  'Experience all features for free. No credit card or payment required!',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.85),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 8),

                // Benefits
                _trialBenefit('Go online & receive rides'),
                _trialBenefit('Full access for 7 days'),
                _trialBenefit('No payment needed'),
                const SizedBox(height: 20),

                // CTA Button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed:
                        _activatingTrial ? null : _activateFreeTrial,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF6C63FF),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: _activatingTrial
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Color(0xFF6C63FF),
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.rocket_launch, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Start Free Trial',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _trialBenefit(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(
            Icons.check_circle,
            size: 16,
            color: Colors.white.withValues(alpha: 0.9),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.9),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveStatus(DriverProvider provider) {
    DateTime? until;
    if (provider.profile != null &&
        provider.profile!['subscriptionActiveUntil'] != null) {
      final timestamp = provider.profile!['subscriptionActiveUntil'];
      if (timestamp is Timestamp) {
        until = timestamp.toDate();
      } else if (timestamp is DateTime) {
        until = timestamp;
      }
    }

    final bool isActive = provider.isSubscriptionActive;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: (isActive ? AppTheme.success : AppTheme.warning)
                  .withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isActive ? Icons.verified : Icons.error_outline,
              size: 48,
              color: isActive ? AppTheme.success : AppTheme.warning,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isActive ? 'Active Subscription' : 'Subscription Expired',
            style:
                GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (until != null && isActive)
            Text(
              'Valid until: ${DateFormat('dd MMM yyyy, hh:mm a').format(until)}',
              style:
                  GoogleFonts.inter(fontSize: 15, color: AppTheme.text2),
            )
          else
            Text(
              'You need an active subscription to go online and receive rides.',
              textAlign: TextAlign.center,
              style:
                  GoogleFonts.inter(fontSize: 15, color: AppTheme.text2),
            ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _showSubscriptionSheet,
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary),
              child: Text(
                isActive ? 'Extend Plan' : 'Renew Plan',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistory() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('payments')
          .where('driverId', isEqualTo: uid)
          .where('type', whereIn: ['subscription', 'free_trial'])
          .orderBy('createdAt', descending: true)
          .limit(20)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(32.0),
            child: Center(
              child: Text('No payment history yet.',
                  style: GoogleFonts.inter(color: AppTheme.text3)),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Payment History',
                style: GoogleFonts.inter(
                    fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            ...docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final date = (data['createdAt'] as Timestamp?)?.toDate() ??
                  DateTime.now();
              final amount = data['amount'] ?? 0;
              final days = data['days'] ?? 0;
              final isFreeTrial = data['type'] == 'free_trial';
              final method = data['method'] ?? 'cash';

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: (isFreeTrial
                                ? AppTheme.accent
                                : AppTheme.success)
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isFreeTrial ? Icons.star : Icons.receipt_long,
                        color: isFreeTrial
                            ? AppTheme.accent
                            : AppTheme.success,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              Text(
                                isFreeTrial
                                    ? '7 Days Free Trial'
                                    : '$days Days Plan',
                                style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w600, fontSize: 15),
                              ),
                              if (!isFreeTrial && method != 'cash')
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    _getMethodDisplay(method),
                                    style: GoogleFonts.inter(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.primary),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            DateFormat('dd MMM yyyy, hh:mm a').format(date),
                            style: GoogleFonts.inter(
                                color: AppTheme.text3, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      isFreeTrial ? 'FREE' : '₹$amount',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: isFreeTrial
                            ? AppTheme.accent
                            : AppTheme.success,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }

  String _getMethodDisplay(String method) {
    switch (method.toLowerCase()) {
      case 'upi':
        return 'UPI';
      case 'card':
        return 'Card';
      case 'netbanking':
        return 'Net Banking';
      case 'wallet':
        return 'Wallet';
      case 'free':
        return 'Free Trial';
      case 'razorpay':
      case 'online':
      default:
        return 'Online';
    }
  }

  void _logout() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.danger.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.logout_rounded,
                    color: AppTheme.danger, size: 32),
              ),
              const SizedBox(height: 20),
              Text(
                'Log Out',
                style: GoogleFonts.inter(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.text,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Are you sure you want to log out of your account?',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  color: AppTheme.text2,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.text3.withValues(alpha: 0.15),
                        foregroundColor: AppTheme.text,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await FirebaseAuth.instance.signOut();
                        if (mounted) {
                          Navigator.of(context).popUntil((route) => route.isFirst);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.danger,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        'Log Out',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DriverProvider>();

    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            leading: Navigator.canPop(context)
                ? IconButton(
                    icon: const Icon(Icons.arrow_back_ios_rounded),
                    onPressed: () => Navigator.pop(context),
                  )
                : null,
            title: Text('Subscription',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
            backgroundColor: AppTheme.bg,
            elevation: 0,
            actions: [
              IconButton(
                icon: const Icon(Icons.logout_rounded, color: AppTheme.text2),
                tooltip: 'Logout',
                onPressed: _logout,
              ),
            ],
          ),
          body: Container(
            height: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppTheme.bg, AppTheme.bg2],
              ),
            ),
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Show free trial card if not yet used and subscription is expired
                    if (!_hasFreeTrialUsed && !provider.isSubscriptionActive)
                      _buildFreeTrialCard(),
                    // Show status card only after trial has been used or sub is active
                    if (_hasFreeTrialUsed || provider.isSubscriptionActive)
                      _buildActiveStatus(provider),
                    const SizedBox(height: 32),
                    _buildHistory(),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Payment processing overlay
        if (_showPaymentOverlay)
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: _buildPaymentOverlay(),
            ),
          ),
      ],
    );
  }
}
