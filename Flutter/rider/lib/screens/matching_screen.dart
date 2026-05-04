// lib/screens/matching_screen.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

import 'package:google_fonts/google_fonts.dart';
import '../config/theme.dart';
import '../config/constants.dart';
import 'active_ride_screen.dart';
import 'home_screen.dart';

class MatchingScreen extends StatefulWidget {
  final String rideId;
  const MatchingScreen({super.key, required this.rideId});

  @override
  State<MatchingScreen> createState() => _MatchingScreenState();
}

class _MatchingScreenState extends State<MatchingScreen>
    with TickerProviderStateMixin {
  Map<String, dynamic>? _ride;
  List<Map<String, dynamic>> _bids = [];
  bool _accepting = false;
  late AnimationController _pulseController;
  StreamSubscription? _rideListener;
  StreamSubscription? _bidListener;
  Timer? _expiryTimer;
  int _elapsedSeconds = 0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
    _listenRide();
    _listenBids();
    _startExpiryTimer();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rideListener?.cancel();
    _bidListener?.cancel();
    _expiryTimer?.cancel();
    super.dispose();
  }

  void _startExpiryTimer() {
    _expiryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() => _elapsedSeconds++);
      if (_elapsedSeconds >= AppConstants.rideExpiryMinutes * 60) {
        _cancelRide();
      }
    });
  }

  void _listenRide() {
    _rideListener = FirebaseFirestore.instance
        .collection('rides')
        .doc(widget.rideId)
        .snapshots()
        .listen((snap) {
      if (!snap.exists) return;
      final data = snap.data()!;
      data['id'] = snap.id;
      setState(() => _ride = data);

      // If matched or started, go to active ride
      if (data['status'] == 'matched' || data['status'] == 'started') {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ActiveRideScreen(rideId: widget.rideId),
          ),
        );
      }
      // If cancelled, go back home
      if (data['status'] == 'cancelled') {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    });
  }

  void _listenBids() {
    _bidListener = FirebaseFirestore.instance
        .collection('bids')
        .where('rideId', isEqualTo: widget.rideId)
        .snapshots()
        .listen((snap) {
      setState(() {
        _bids = snap.docs.map((d) {
          final data = d.data();
          data['id'] = d.id;
          return data;
        }).toList();
        _bids.sort((a, b) =>
            (a['price'] as num).compareTo(b['price'] as num));
      });
    });
  }

  Future<void> _acceptBid(Map<String, dynamic> bid) async {
    setState(() => _accepting = true);
    try {
      // Generate random 4-digit OTP
      final otp = (1000 + Random().nextInt(9000)).toString();

      final batch = FirebaseFirestore.instance.batch();
      // Update ride
      batch.update(
        FirebaseFirestore.instance.collection('rides').doc(widget.rideId),
        {
          'status': 'matched',
          'driverId': bid['driverId'],
          'driverName': bid['driverName'] ?? 'Driver',
          'driverPhone': bid['driverPhone'],
          'vehicleNumber': bid['vehicleNumber'],
          'finalPrice': bid['price'],
          'rideOtp': otp,
          'matchedAt': FieldValue.serverTimestamp(),
        },
      );
      // Update bid status
      batch.update(
        FirebaseFirestore.instance.collection('bids').doc(bid['id']),
        {'status': 'accepted'},
      );
      await batch.commit();
    } catch (e) {
      setState(() => _accepting = false);
    }
  }

  Future<void> _cancelRide() async {
    await FirebaseFirestore.instance
        .collection('rides')
        .doc(widget.rideId)
        .update({'status': 'cancelled'});
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final remaining =
        (AppConstants.rideExpiryMinutes * 60) - _elapsedSeconds;
    final minutes = (remaining ~/ 60).toString().padLeft(2, '0');
    final seconds = (remaining % 60).toString().padLeft(2, '0');

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppTheme.bg, AppTheme.bg2],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 20),
              // Searching animation
              _buildSearchingHeader(minutes, seconds),
              const SizedBox(height: 32),

              // Ride info card
              if (_ride != null) _buildRideInfoCard(),
              const SizedBox(height: 20),

              // Bids list
              Expanded(
                child: _bids.isEmpty
                    ? _buildWaitingForBids()
                    : _buildBidsList(),
              ),

              // Cancel button
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    onPressed: _cancelRide,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppTheme.danger),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Cancel Ride',
                      style: GoogleFonts.inter(
                        color: AppTheme.danger,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchingHeader(String minutes, String seconds) {
    return Column(
      children: [
        AnimatedBuilder(
          animation: _pulseController,
          builder: (_, __) {
            final scale = 1.0 + _pulseController.value * 0.15;
            final opacity = 1.0 - _pulseController.value * 0.5;
            return Stack(
              alignment: Alignment.center,
              children: [
                Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTheme.primary.withValues(alpha: opacity),
                        width: 2,
                      ),
                    ),
                  ),
                ),
                const Text('🔍', style: TextStyle(fontSize: 42)),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Text(
          _bids.isEmpty ? 'Searching for drivers...' : 'Drivers found!',
          style: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.warning.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            'Expires in $minutes:$seconds',
            style: GoogleFonts.inter(
              color: AppTheme.warning,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRideInfoCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.circle,
                          size: 8, color: AppTheme.success),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _ride!['pickup']?['short_name'] ?? 'Pickup',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.location_on,
                          size: 10, color: AppTheme.danger),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _ride!['drop']?['short_name'] ?? 'Drop',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              children: [
                Text(
                  '₹${_ride!['riderBid']}',
                  style: GoogleFonts.inter(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.success,
                  ),
                ),
                Text(
                  '${_ride!['distanceKm']} km',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppTheme.text3,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaitingForBids() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(
            color: AppTheme.primary,
            strokeWidth: 2,
          ),
          const SizedBox(height: 16),
          Text(
            'Waiting for drivers to bid...',
            style: GoogleFonts.inter(
              color: AppTheme.text3,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBidsList() {
    final pickupLat = (_ride?['pickup']?['lat'] as num?)?.toDouble();
    final pickupLng = (_ride?['pickup']?['lng'] as num?)?.toDouble();
    final riderBid = (_ride?['riderBid'] as num?)?.toInt() ?? 0;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: _bids.length,
      itemBuilder: (_, i) {
        final bid = _bids[i];
        final bidPrice = (bid['price'] as num).toInt();
        final vType = bid['vehicleType'] ?? 'auto';
        final icon = AppConstants.vehicleTypes[vType]?.icon ?? '🚗';

        // Determine bid type label
        final bool isAcceptedPrice = bidPrice <= riderBid;

        // Calculate distance from driver to pickup
        String distanceLabel = '';
        String etaLabel = '';
        if (pickupLat != null && pickupLng != null &&
            bid['driverLat'] != null && bid['driverLng'] != null) {
          final distMeters = Geolocator.distanceBetween(
            (bid['driverLat'] as num).toDouble(),
            (bid['driverLng'] as num).toDouble(),
            pickupLat,
            pickupLng,
          );
          distanceLabel = distMeters < 1000
              ? '${distMeters.toInt()}m away'
              : '${(distMeters / 1000).toStringAsFixed(1)} km away';
          final etaMin = ((distMeters / 1000) / 25 * 60).ceil();
          etaLabel = etaMin < 1 ? '<1 min' : '$etaMin min';
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              // Status label bar
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isAcceptedPrice
                      ? AppTheme.success.withValues(alpha: 0.1)
                      : AppTheme.warning.withValues(alpha: 0.1),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isAcceptedPrice ? Icons.check_circle : Icons.swap_vert,
                      size: 16,
                      color: isAcceptedPrice ? AppTheme.success : AppTheme.warning,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isAcceptedPrice
                          ? 'Accepted your price'
                          : 'Counter Offer',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isAcceptedPrice ? AppTheme.success : AppTheme.warning,
                      ),
                    ),
                    const Spacer(),
                    if (!isAcceptedPrice)
                      Text(
                        '+₹${bidPrice - riderBid}',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.warning,
                        ),
                      ),
                  ],
                ),
              ),

              // Driver detail card
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Driver info row
                    Row(
                      children: [
                        // Driver avatar
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: AppTheme.bg2,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Center(
                            child: Text(icon, style: const TextStyle(fontSize: 28)),
                          ),
                        ),
                        const SizedBox(width: 14),
                        // Driver details
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                bid['driverName'] ?? 'Driver',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                bid['vehicleNumber'] ?? '',
                                style: GoogleFonts.inter(
                                  color: AppTheme.text2,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Price
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '₹$bidPrice',
                              style: GoogleFonts.inter(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: isAcceptedPrice
                                    ? AppTheme.success
                                    : AppTheme.warning,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Distance & ETA row
                    if (distanceLabel.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.bg2,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.near_me,
                                size: 14, color: AppTheme.primary),
                            const SizedBox(width: 8),
                            Text(
                              distanceLabel,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.text,
                              ),
                            ),
                            if (etaLabel.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Container(
                                width: 4,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: AppTheme.text3,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.schedule,
                                  size: 14, color: AppTheme.warning),
                              const SizedBox(width: 4),
                              Text(
                                'ETA $etaLabel',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.text,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                    const SizedBox(height: 14),
                    // Accept button
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton(
                        onPressed:
                            _accepting ? null : () => _acceptBid(bid),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Accept Ride',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
