// lib/screens/matching_screen.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:geolocator/geolocator.dart';

import 'package:google_fonts/google_fonts.dart';
import '../config/theme.dart';
import '../config/constants.dart';
import 'active_ride_screen.dart';
import '../screens/main_screen.dart';
import 'package:provider/provider.dart';
import '../providers/ride_provider.dart';
import '../utils/skeleton.dart';

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
  String? _processingBidId;
  bool _cancelling = false;
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
      if (_ride != null && _ride!['createdAt'] != null) {
        final createdAt = (_ride!['createdAt'] as Timestamp).toDate();
        final elapsed = DateTime.now().difference(createdAt).inSeconds;
        setState(() => _elapsedSeconds = elapsed > 0 ? elapsed : 0);
      } else {
        setState(() => _elapsedSeconds++);
      }

      if (_elapsedSeconds >= AppConstants.rideExpiryMinutes * 60) {
        _expireRide();
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
      try {
        final data = Map<String, dynamic>.from(snap.data() as Map);
        data['id'] = snap.id;
        if (!mounted) return;
        setState(() => _ride = data);

        // If matched or started, go to active ride
        if (data['status'] == 'matched' || data['status'] == 'started') {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => ActiveRideScreen(rideId: widget.rideId),
            ),
          );
        }
        // If cancelled or expired, go back home
        if (data['status'] == 'cancelled' || data['status'] == 'expired') {
          context.read<RideProvider>().resetRide();
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => MainScreen(key: mainScreenKey)),
            (_) => false,
          );
        }
      } catch (e) {
        debugPrint('Error in MatchingScreen _listenRide: $e');
      }
    }, onError: (error) {
      debugPrint('Firestore stream error in MatchingScreen: $error');
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
        }).where((b) =>
            b['status'] != 'rejected' &&
            b['status'] != 'rejected_by_system' &&
            b['status'] != 'withdrawn').toList();
        _bids.sort((a, b) =>
            (a['price'] as num).compareTo(b['price'] as num));
      });
    });
  }

  Future<void> _acceptBid(Map<String, dynamic> bid) async {
    setState(() => _processingBidId = bid['id']);
    try {
      // Call the Cloud Function directly for immediate feedback.
      // Unlike create/cancel which tolerate async processing, acceptBid
      // is interactive — the rider needs to know RIGHT NOW if it worked.
      final callable = FirebaseFunctions.instance.httpsCallable('acceptBid');
      await callable.call<dynamic>({
        'rideId': widget.rideId,
        'bidId': bid['id'],
      });
      // Success! The _listenRide() snapshot listener will detect
      // status='matched' and navigate to ActiveRideScreen automatically.
      debugPrint('acceptBid: ✅ Cloud Function call succeeded');
    } on FirebaseFunctionsException catch (e) {
      debugPrint('acceptBid: ❌ FirebaseFunctionsException: ${e.code} — ${e.message}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message ?? 'Failed to accept bid.'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
      setState(() => _processingBidId = null);
    } catch (e) {
      debugPrint('acceptBid: ❌ Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Something went wrong. Please try again.'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
      setState(() => _processingBidId = null);
    }
  }

  Future<void> _declineBid(String bidId, String driverId) async {
    try {
      await FirebaseFirestore.instance.collection('bids').doc(bidId).update({
        'status': 'rejected',
      });
      // Notify driver instantly via RTDB (separate decline node)
      await FirebaseDatabase.instance
          .ref('ride_declines/${widget.rideId}/$driverId')
          .set(true);
    } catch (e) {
      debugPrint('Error declining bid: $e');
    }
  }

  Future<void> _cancelRide() async {
    setState(() => _cancelling = true);
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('cancelRide');
      await callable.call({'rideId': widget.rideId});
      
      if (mounted) {
        context.read<RideProvider>().resetRide();
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => MainScreen(key: mainScreenKey)),
          (_) => false,
        );
      }
    } catch (e) {
      debugPrint('Error cancelling ride: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to cancel. Check connection and try again.'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
      setState(() => _cancelling = false);
    }
  }

  Future<void> _expireRide() async {
    // We now use a Cloud Function to handle expiry atomically.
    // This ensures RTDB signals are cleaned up and state is consistent.
    try {
      await FirebaseFunctions.instance
          .httpsCallable('expireRide')
          .call({'rideId': widget.rideId});
      
      if (mounted) {
        context.read<RideProvider>().resetRide();
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => MainScreen(key: mainScreenKey)),
          (_) => false,
        );
      }
    } catch (e) {
      debugPrint('Error expiring ride: $e');
      // If the function fails (e.g. ride already matched), the listener 
      // will handle the navigation to the active ride screen.
      if (mounted) {
        context.read<RideProvider>().resetRide();
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => MainScreen(key: mainScreenKey)),
          (_) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final remaining =
        max(0, (AppConstants.rideExpiryMinutes * 60) - _elapsedSeconds);
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
                    onPressed: _cancelling ? null : _cancelRide,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                          color: _cancelling ? AppTheme.text3 : AppTheme.danger),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _cancelling
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.danger,
                            ),
                          )
                        : Text(
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
    final bidCount = _bids.length;
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
                Text(
                  bidCount == 0 ? '🔍' : '🎯',
                  style: const TextStyle(fontSize: 42),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        // Animated title — switches between searching and bids-found
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: Text(
            bidCount == 0
                ? 'Searching for drivers...'
                : '$bidCount driver${bidCount == 1 ? '' : 's'} placed a bid!',
            key: ValueKey(bidCount == 0),
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: bidCount > 0 ? AppTheme.success : AppTheme.text,
            ),
          ),
        ),
        const SizedBox(height: 6),
        // Popular route badge — shows if many bids
        if (bidCount >= 3) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.warning.withValues(alpha: 0.4)),
            ),
            child: Text(
              '🔥 Popular route! Lots of drivers available',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.warning,
              ),
            ),
          ),
          const SizedBox(height: 6),
        ],
        // Countdown timer
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
        const SizedBox(height: 6),
        // Phase indicator
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: Text(
            _elapsedSeconds < 180
                ? '📡 Searching nearby drivers...'
                : '🌐 Expanding search area...',
            key: ValueKey(_elapsedSeconds < 180),
            style: GoogleFonts.inter(
              fontSize: 12,
              color: _elapsedSeconds < 180
                  ? AppTheme.text3
                  : AppTheme.primary,
              fontWeight: _elapsedSeconds < 180
                  ? FontWeight.w400
                  : FontWeight.w600,
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
          color: AppTheme.bg,
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
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      physics: const NeverScrollableScrollPhysics(),
      children: const [
        BidCardSkeleton(),
        BidCardSkeleton(),
        BidCardSkeleton(),
      ],
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
                final bool isAcceptedPrice = bidPrice == riderBid;
                final bool isBetterOffer = bidPrice < riderBid;
                final bool isCounterOffer = bidPrice > riderBid;

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
                    color: AppTheme.bg,
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
                          color: isCounterOffer
                              ? AppTheme.warning.withValues(alpha: 0.1)
                              : AppTheme.success.withValues(alpha: 0.1),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(18),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isAcceptedPrice 
                                  ? Icons.check_circle 
                                  : (isBetterOffer ? Icons.local_offer : Icons.swap_vert),
                              size: 16,
                              color: isCounterOffer ? AppTheme.warning : AppTheme.success,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isAcceptedPrice
                                  ? 'Accepted your price'
                                  : isBetterOffer 
                                      ? 'Special Offer' 
                                      : 'Counter Offer',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: isCounterOffer ? AppTheme.warning : AppTheme.success,
                              ),
                            ),
                            const Spacer(),
                            if (isCounterOffer)
                              Text(
                                '+₹${bidPrice - riderBid}',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.warning,
                                ),
                              ),
                            if (isBetterOffer)
                              Text(
                                '-₹${riderBid - bidPrice}',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.success,
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
                            image: bid['driverImageUrl'] != null && bid['driverImageUrl'].toString().isNotEmpty
                                ? DecorationImage(
                                    image: NetworkImage(bid['driverImageUrl']),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: bid['driverImageUrl'] == null || bid['driverImageUrl'].toString().isEmpty
                              ? Center(
                                  child: Text(icon, style: const TextStyle(fontSize: 28)),
                                )
                              : null,
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
                    // Distance & ETA row — color-coded by ETA urgency
                    if (distanceLabel.isNotEmpty)
                      Builder(builder: (_) {
                        // Color-code by ETA: green < 3min, amber 3–7min, red > 7min
                        final etaMin = int.tryParse(
                              etaLabel.replaceAll(' min', '').replaceAll('<', '').trim(),
                            ) ??
                            99;
                        final etaColor = etaMin < 3
                            ? AppTheme.success
                            : etaMin <= 7
                                ? AppTheme.warning
                                : AppTheme.danger;

                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: etaColor.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(10),
                            border:
                                Border.all(color: etaColor.withValues(alpha: 0.25)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.near_me, size: 14, color: etaColor),
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
                                Icon(Icons.schedule, size: 14, color: etaColor),
                                const SizedBox(width: 4),
                                Text(
                                  'ETA $etaLabel',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: etaColor,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      }),

                    const SizedBox(height: 14),
                    // Accept/Reject buttons
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 44,
                            child: OutlinedButton(
                              onPressed: _processingBidId != null ? null : () => _declineBid(bid['id'], bid['driverId']),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppTheme.danger),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                'Decline',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  color: AppTheme.danger,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 44,
                            child: ElevatedButton(
                              onPressed:
                                  _processingBidId != null ? null : () => _acceptBid(bid),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: _processingBidId == bid['id']
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      'Accept',
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ],
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
