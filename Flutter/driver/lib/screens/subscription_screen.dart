// lib/screens/subscription_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';
import '../config/constants.dart';
import '../providers/driver_provider.dart';
import '../utils/custom_toast.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});
  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  bool _processing = false;
  int _selectedDays = 7;
  bool _activatingTrial = false;
  final _plans = [
    {'days': 1, 'label': '1 Day', 'emoji': '🌅'},
    {'days': 7, 'label': '7 Days', 'emoji': '📅'},
    {'days': 30, 'label': '30 Days', 'emoji': '🗓️'},
  ];

  bool get _hasFreeTrialUsed {
    final provider = context.read<DriverProvider>();
    return provider.profile?['hasFreeTrialUsed'] == true;
  }

  Future<void> _activateFreeTrial() async {
    setState(() => _activatingTrial = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final now = DateTime.now();
      final until = now.add(const Duration(days: 7));

      final batch = FirebaseFirestore.instance.batch();
      batch.update(
        FirebaseFirestore.instance.collection('drivers').doc(uid),
        {
          'subscriptionActiveUntil': Timestamp.fromDate(until),
          'hasFreeTrialUsed': true,
        },
      );
      batch.set(
        FirebaseFirestore.instance.collection('payments').doc(),
        {
          'driverId': uid,
          'amount': 0,
          'days': 7,
          'type': 'free_trial',
          'method': 'free',
          'createdAt': FieldValue.serverTimestamp(),
        },
      );
      await batch.commit();

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

  Future<void> _subscribe() async {
    setState(() => _processing = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final provider = context.read<DriverProvider>();
      
      // Calculate new until date
      DateTime now = DateTime.now();
      DateTime currentUntil = now;
      if (provider.profile != null && provider.profile!['subscriptionActiveUntil'] != null) {
        final timestamp = provider.profile!['subscriptionActiveUntil'];
        if (timestamp is Timestamp) {
          currentUntil = timestamp.toDate();
        } else if (timestamp is DateTime) {
          currentUntil = timestamp;
        }
      }
      
      if (currentUntil.isBefore(now)) {
        currentUntil = now;
      }
      
      final until = currentUntil.add(Duration(days: _selectedDays));
      final amount = _selectedDays * AppConstants.subscriptionDailyRate;

      final batch = FirebaseFirestore.instance.batch();
      batch.update(
        FirebaseFirestore.instance.collection('drivers').doc(uid),
        {'subscriptionActiveUntil': Timestamp.fromDate(until)},
      );
      batch.set(
        FirebaseFirestore.instance.collection('payments').doc(),
        {
          'driverId': uid,
          'amount': amount,
          'days': _selectedDays,
          'type': 'subscription',
          'method': 'cash',
          'createdAt': FieldValue.serverTimestamp(),
        },
      );
      await batch.commit();
      
      if (mounted) {
        Navigator.pop(context); // Close bottom sheet
        CustomToast.show(
          context: context,
          message: 'Subscription activated successfully!',
        );
      }
    } catch (e) {
      if (mounted) {
        CustomToast.show(
          context: context,
          message: 'Failed to activate. Try again.',
          isError: true,
        );
      }
    }
    if (mounted) setState(() => _processing = false);
  }

  void _showSubscriptionSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + MediaQuery.of(ctx).padding.bottom + 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: AppTheme.text3, borderRadius: BorderRadius.circular(2)),
                  ),
                  const SizedBox(height: 24),
                  Text('Choose Plan', style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text('Select a duration to extend your active time.', style: GoogleFonts.inter(fontSize: 14, color: AppTheme.text2)),
                  const SizedBox(height: 24),
                  ...(_plans.map((plan) {
                    final days = plan['days'] as int;
                    final total = days * AppConstants.subscriptionDailyRate;
                    final selected = _selectedDays == days;
                    return GestureDetector(
                      onTap: () => setSheetState(() => _selectedDays = days),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: selected ? AppTheme.primary.withValues(alpha: 0.1) : AppTheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: selected ? AppTheme.primary : AppTheme.border,
                            width: selected ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(plan['emoji'] as String, style: const TextStyle(fontSize: 32)),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(plan['label'] as String, style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700)),
                                  Text('₹${AppConstants.subscriptionDailyRate}/day', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.text3)),
                                ],
                              ),
                            ),
                            Text('₹$total', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w800, color: selected ? AppTheme.primary : AppTheme.text2)),
                          ],
                        ),
                      ),
                    );
                  })),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _processing ? null : () async {
                        setSheetState(() => _processing = true);
                        await _subscribe();
                        if (mounted) setSheetState(() => _processing = false);
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
                      child: _processing
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                          : Text('Pay ₹${_selectedDays * AppConstants.subscriptionDailyRate} (Cash)', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16)),
                    ),
                  ),
                ],
              ),
            );
          }
        );
      }
    );
  }

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
                    onPressed: _activatingTrial ? null : _activateFreeTrial,
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
    if (provider.profile != null && provider.profile!['subscriptionActiveUntil'] != null) {
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
              color: (isActive ? AppTheme.success : AppTheme.warning).withValues(alpha: 0.1),
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
            style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (until != null && isActive)
            Text(
              'Valid until: ${DateFormat('dd MMM yyyy, hh:mm a').format(until)}',
              style: GoogleFonts.inter(fontSize: 15, color: AppTheme.text2),
            )
          else
            Text(
              'You need an active subscription to go online and receive rides.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 15, color: AppTheme.text2),
            ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _showSubscriptionSheet,
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
              child: Text(
                isActive ? 'Extend Plan' : 'Renew Plan',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16),
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
              child: Text('No payment history yet.', style: GoogleFonts.inter(color: AppTheme.text3)),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Payment History', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            ...docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final date = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
              final amount = data['amount'] ?? 0;
              final days = data['days'] ?? 0;
              final isFreeTrial = data['type'] == 'free_trial';
              
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
                        color: (isFreeTrial ? AppTheme.accent : AppTheme.success).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isFreeTrial ? Icons.star : Icons.receipt_long,
                        color: isFreeTrial ? AppTheme.accent : AppTheme.success,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isFreeTrial ? '7 Days Free Trial' : '$days Days Plan',
                            style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
                          ),
                          const SizedBox(height: 4),
                          Text(DateFormat('dd MMM yyyy, hh:mm a').format(date), style: GoogleFonts.inter(color: AppTheme.text3, fontSize: 12)),
                        ],
                      ),
                    ),
                    Text(
                      isFreeTrial ? 'FREE' : '₹$amount',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: isFreeTrial ? AppTheme.accent : AppTheme.success,
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

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DriverProvider>();
    
    return Scaffold(
      appBar: AppBar(
        title: Text('Subscription', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        backgroundColor: AppTheme.bg,
        elevation: 0,
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
    );
  }
}
