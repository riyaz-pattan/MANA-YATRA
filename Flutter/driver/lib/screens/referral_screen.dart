// lib/screens/referral_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';

class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key});

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen>
    with SingleTickerProviderStateMixin {
  String? _referralCode;
  bool _loadingCode = true;
  String? _errorMessage;

  // Referral Data State
  int _referralCount = 0;
  List<DocumentSnapshot> _referredDrivers = [];
  bool _loadingReferrals = true;

  late AnimationController _giftBounceController;
  late Animation<double> _giftBounceAnimation;

  @override
  void initState() {
    super.initState();
    _giftBounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _giftBounceAnimation = Tween<double>(begin: 0, end: -8).animate(
      CurvedAnimation(parent: _giftBounceController, curve: Curves.easeInOut),
    );
    _loadReferralCode();
    _loadReferrals();
  }

  @override
  void dispose() {
    _giftBounceController.dispose();
    super.dispose();
  }

  Future<void> _loadReferrals() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    if (mounted) {
      setState(() => _loadingReferrals = true);
    }

    try {
      // 1. Fetch total rewarded count
      final countSnapshot = await FirebaseFirestore.instance
          .collection('referrals')
          .where('referrerDriverId', isEqualTo: uid)
          .where('status', isEqualTo: 'rewarded')
          .get();

      // 2. Fetch list of referred drivers (limit to 20 for UI)
      final driversSnapshot = await FirebaseFirestore.instance
          .collection('referrals')
          .where('referrerDriverId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(20)
          .get();

      if (mounted) {
        setState(() {
          _referralCount = countSnapshot.docs.length;
          _referredDrivers = driversSnapshot.docs;
          _loadingReferrals = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading referrals: $e');
      if (mounted) {
        setState(() => _loadingReferrals = false);
      }
    }
  }

  Future<void> _loadReferralCode() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      // Check if driver already has a referral code
      final driverDoc = await FirebaseFirestore.instance
          .collection('drivers')
          .doc(uid)
          .get();

      final existingCode = driverDoc.data()?['referralCode'] as String?;
      if (existingCode != null && existingCode.isNotEmpty) {
        if (mounted) {
          setState(() {
            _referralCode = existingCode;
            _loadingCode = false;
          });
        }
        return;
      }

      // Generate a new code via Cloud Function
      final result = await FirebaseFunctions.instance
          .httpsCallable('generateReferralCode')
          .call();
      final code = result.data['code'] as String;

      if (mounted) {
        setState(() {
          _referralCode = code;
          _loadingCode = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Could not load referral code. Please try again.';
          _loadingCode = false;
        });
      }
    }
  }

  String get _referralLink =>
      'https://mana-yatra.web.app/refer?code=$_referralCode';

  String get _shareText =>
      'Join Gaman Driver and earn with every ride! Use my referral code: $_referralCode\nDownload: $_referralLink';

  Future<void> _copyCode() async {
    if (_referralCode == null) return;
    await Clipboard.setData(ClipboardData(text: _referralCode!));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text('Code copied!',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            ],
          ),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _shareCode() async {
    if (_referralCode == null) return;
    await Share.share(_shareText);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Text('Refer & Earn',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        backgroundColor: AppTheme.bg,
        elevation: 0,
        scrolledUnderElevation: 0.5,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadReferrals();
        },
        color: AppTheme.primary,
        backgroundColor: Colors.white,
        child: StreamBuilder<DatabaseEvent>(
          stream: FirebaseDatabase.instance.ref('config/feature_flags/enable_referrals').onValue,
          builder: (context, snapshot) {
            final isEnabled = snapshot.data?.snapshot.value != false; // true by default

            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isEnabled) ...[
                    _buildPausedBanner(),
                    const SizedBox(height: 24),
                  ],
                  _buildStatsHeaderCard(),
                  if (isEnabled) ...[
                    const SizedBox(height: 24),
                    _buildReferralCodeSection(),
                    const SizedBox(height: 24),
                    _buildQrSection(),
                  ],
                  const SizedBox(height: 28),
                  _buildReferredDriversSection(),
                  if (isEnabled) ...[
                    const SizedBox(height: 28),
                    _buildHowItWorksSection(),
                  ],
                ],
              ),
            );
          }
        ),
      ),
    );
  }

  // ─── Paused Banner ───────────────────────────────────────────────
  Widget _buildPausedBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Column(
        children: [
          const Icon(Icons.pause_circle_filled, color: AppTheme.warning, size: 36),
          const SizedBox(height: 12),
          Text(
            'Program Paused',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.warning,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Our Refer & Earn program is currently taking a short break. Check back later for new rewards!\n\nYou can still view your past earnings below.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AppTheme.text,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Stats Header Card ───────────────────────────────────────────
  Widget _buildStatsHeaderCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F0E1A), Color(0xFF1A1929)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F0E1A).withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Subtle decorative circles
          Positioned(
            top: -20,
            right: -20,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.accent.withValues(alpha: 0.08),
              ),
            ),
          ),
          Positioned(
            bottom: -30,
            left: -10,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.success.withValues(alpha: 0.06),
              ),
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your Referrals',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.6),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$_referralCount',
                        style: GoogleFonts.inter(
                          fontSize: 40,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Successful referrals',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.success.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.stars_rounded,
                                color: AppTheme.success, size: 14),
                            const SizedBox(width: 6),
                            Text(
                              '7 days free per referral',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.success,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                AnimatedBuilder(
                  animation: _giftBounceAnimation,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(0, _giftBounceAnimation.value),
                      child: child,
                    );
                  },
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Text('🎁', style: TextStyle(fontSize: 36)),
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

  // ─── Referral Code Section ───────────────────────────────────────
  Widget _buildReferralCodeSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Column(
        children: [
          Text(
            'Your Referral Code',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.text2,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          if (_loadingCode)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppTheme.primary,
                ),
              ),
            )
          else if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  Text(
                    _errorMessage!,
                    style: GoogleFonts.inter(
                        fontSize: 13, color: AppTheme.danger),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _errorMessage = null;
                        _loadingCode = true;
                      });
                      _loadReferralCode();
                    },
                    icon:
                        const Icon(Icons.refresh, size: 16, color: AppTheme.primary),
                    label: Text('Retry',
                        style: GoogleFonts.inter(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            )
          else ...[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              decoration: BoxDecoration(
                color: AppTheme.bg2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppTheme.primary.withValues(alpha: 0.1), width: 1.5),
              ),
              child: Text(
                _referralCode ?? '',
                style: GoogleFonts.robotoMono(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.text,
                  letterSpacing: 4,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    icon: Icons.copy_rounded,
                    label: 'Copy',
                    onTap: _copyCode,
                    isPrimary: false,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionButton(
                    icon: Icons.share_rounded,
                    label: 'Share',
                    onTap: _shareCode,
                    isPrimary: true,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ─── QR Code Section ─────────────────────────────────────────────
  Widget _buildQrSection() {
    if (_referralCode == null || _loadingCode) return const SizedBox.shrink();

    return Center(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border, width: 1),
        ),
        child: Column(
          children: [
            Text(
              'Scan to Refer',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.text2,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: QrImageView(
                data: _referralLink,
                version: QrVersions.auto,
                size: 160,
                eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Color(0xFF0F0E1A)),
                dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Color(0xFF0F0E1A)),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _referralLink,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: AppTheme.text3,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Referred Drivers Section ────────────────────────────────────
  Widget _buildReferredDriversSection() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Referred Drivers',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.text,
              ),
            ),
            if (_loadingReferrals)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
          ],
        ),
        const SizedBox(height: 12),
        if (!_loadingReferrals && _referredDrivers.isEmpty)
          _buildEmptyState()
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _referredDrivers.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final data = _referredDrivers[index].data() as Map<String, dynamic>;
              return _buildReferralItem(data);
            },
          ),
      ],
    );
  }

  Widget _buildReferralItem(Map<String, dynamic> data) {
    final name = (data['referredDriverName'] as String?) ?? 'New Driver';
    final status = (data['status'] as String?) ?? 'pending';
    final createdAt = data['createdAt'] as Timestamp?;
    final dateStr = createdAt != null
        ? DateFormat('dd MMM yyyy').format(createdAt.toDate())
        : '';

    final isPending = status == 'pending';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isPending
                  ? AppTheme.warning.withValues(alpha: 0.1)
                  : AppTheme.success.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(
                isPending ? Icons.hourglass_top : Icons.check_circle,
                color: isPending ? AppTheme.warning : AppTheme.success,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.text,
                  ),
                ),
                const SizedBox(height: 2),
                if (!isPending)
                  Text(
                    '+7 days earned!',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.success,
                    ),
                  ),
                if (dateStr.isNotEmpty)
                  Text(
                    dateStr,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppTheme.text3,
                    ),
                  ),
              ],
            ),
          ),
          // Status chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isPending
                  ? AppTheme.warning.withValues(alpha: 0.1)
                  : AppTheme.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              isPending ? 'Registered' : 'Approved ✓',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isPending ? AppTheme.warning : AppTheme.success,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      decoration: BoxDecoration(
        color: AppTheme.bg2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppTheme.bg,
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text('👥', style: TextStyle(fontSize: 28)),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No referrals yet',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Share your referral code with other drivers\nand earn 7 free days for each signup!',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppTheme.text3,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // ─── How It Works Section ────────────────────────────────────────
  Widget _buildHowItWorksSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How It Works',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppTheme.text,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border, width: 1),
          ),
          child: Column(
            children: [
              _buildStep(1, '📤', 'Share your code',
                  'Send your referral code to a friend', false),
              _buildStepConnector(),
              _buildStep(2, '📱', 'Friend signs up',
                  'They register with your code', false),
              _buildStepConnector(),
              _buildStep(3, '✅', 'Admin approves',
                  'Application is verified', false),
              _buildStepConnector(),
              _buildStep(4, '🎁', 'You earn 7 days!',
                  'Free subscription added automatically', true),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStep(
      int number, String emoji, String title, String subtitle, bool isLast) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isLast
                    ? AppTheme.success.withValues(alpha: 0.1)
                    : AppTheme.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isLast
                      ? AppTheme.success.withValues(alpha: 0.3)
                      : AppTheme.primary.withValues(alpha: 0.15),
                  width: 1.5,
                ),
              ),
              child: Center(
                child: Text(
                  '$number',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isLast ? AppTheme.success : AppTheme.text,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(emoji, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 6),
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.text,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppTheme.text3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStepConnector() {
    return Padding(
      padding: const EdgeInsets.only(left: 19),
      child: Container(
        width: 2,
        height: 24,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppTheme.border,
              AppTheme.border.withValues(alpha: 0.4),
            ],
          ),
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }
}

// ─── Action Button Widget ──────────────────────────────────────────
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isPrimary;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.isPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isPrimary ? AppTheme.primary : AppTheme.bg2,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: isPrimary
                ? null
                : Border.all(color: AppTheme.border, width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isPrimary ? Colors.white : AppTheme.text,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isPrimary ? Colors.white : AppTheme.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
