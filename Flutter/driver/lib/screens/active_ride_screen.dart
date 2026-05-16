// lib/screens/active_ride_screen.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:confetti/confetti.dart';
import '../utils/custom_toast.dart';
import 'package:geolocator/geolocator.dart';
import '../config/theme.dart';
import '../services/google_maps_service.dart';
import '../utils/map_style.dart';
import '../utils/map_utils.dart';

import 'package:cloud_functions/cloud_functions.dart';
import '../providers/driver_provider.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'dashboard_screen.dart';
import '../widgets/swipe_action.dart';

class ActiveRideScreen extends StatefulWidget {
  final String rideId;
  const ActiveRideScreen({super.key, required this.rideId});
  @override
  State<ActiveRideScreen> createState() => _ActiveRideScreenState();
}

class _ActiveRideScreenState extends State<ActiveRideScreen> {
  GoogleMapController? _mapController;
  Map<String, dynamic>? _ride;
  StreamSubscription? _rideListener;
  bool _updating = false;
  bool _cameraFitted = false;
  BitmapDescriptor? _riderPinIcon;
  BitmapDescriptor? _riderLabelIcon;
  List<LatLng> _approachRouteCoords = [];
  bool _isFetchingApproach = false;
  LatLng? _lastDriverPos;
  String _driverProximity = '';
  DriverProvider? _driverProvider;
  ConfettiController? _confettiController;

  // OTP verification
  final List<TextEditingController> _otpControllers = List.generate(
    4,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _otpFocusNodes = List.generate(4, (_) => FocusNode());

  @override
  void initState() {
    super.initState();
    _listenRide();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _driverProvider = context.read<DriverProvider>();
      _driverProvider?.addListener(_onDriverLocationChanged);
      _loadCustomIcons();
    });
  }

  @override
  void dispose() {
    _rideListener?.cancel();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final n in _otpFocusNodes) {
      n.dispose();
    }
    _driverProvider?.removeListener(_onDriverLocationChanged);
    super.dispose();
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
            final prevStatus = _ride?['status'];
            data['id'] = snap.id;
            if (!mounted) return;
            setState(() => _ride = data);

            if (prevStatus == 'matched' && data['status'] == 'started') {
              _cameraFitted = false;
            }

            // Fit camera to route bounds once
            if (!_cameraFitted && _mapController != null) {
              _fitCameraToCurrentRoute();
            }

            // Fetch approach route if matched
            if (data['status'] == 'matched' && _lastDriverPos != null) {
              _fetchApproachRoute();
            }

            if (data['status'] == 'completed' || data['status'] == 'cancelled') {
              // The build method now handles returning the full screen End UI
            }
          } catch (e) {
            debugPrint('Error in _listenRide: $e');
          }
        }, onError: (error) {
          debugPrint('Firestore stream error: $error');
        });
  }

  void _onDriverLocationChanged() {
    if (_driverProvider?.lat != null && _driverProvider?.lng != null) {
      final newPos = LatLng(_driverProvider!.lat!, _driverProvider!.lng!);
      if (_lastDriverPos != null &&
          (newPos.latitude != _lastDriverPos!.latitude ||
              newPos.longitude != _lastDriverPos!.longitude)) {
      }

      String proximity = '';
      if (_ride != null && _ride!['pickup'] != null) {
        final pLat = (_ride!['pickup']['lat'] as num).toDouble();
        final pLng = (_ride!['pickup']['lng'] as num).toDouble();
        final dist = Geolocator.distanceBetween(
          newPos.latitude,
          newPos.longitude,
          pLat,
          pLng,
        );
        if (dist < 100) {
          proximity = 'Arriving soon';
        } else if (dist < 1000) {
          proximity = '${dist.round()}m away';
        } else {
          proximity = '${(dist / 1000).toStringAsFixed(1)}km away';
        }
      }

      setState(() {
        _lastDriverPos = newPos;
        _driverProximity = proximity;
      });

      if (_ride?['status'] == 'matched') {
        _fetchApproachRoute();
        if (!_cameraFitted) {
          _mapController?.animateCamera(CameraUpdate.newLatLng(newPos));
        }
      }
    }
  }

  Future<void> _loadCustomIcons() async {
    try {
      // Use stickman marker so driver can visually identify where rider is standing
      _riderPinIcon = await MapUtils.createStickmanMarker();
      _riderLabelIcon = await MapUtils.createLabelMarker('Rider is here');
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _fetchApproachRoute() async {
    if (_isFetchingApproach ||
        _approachRouteCoords.isNotEmpty ||
        _lastDriverPos == null ||
        _ride == null) {
      return;
    }
    final pickup = _ride!['pickup'];
    if (pickup == null) return;

    setState(() => _isFetchingApproach = true);
    final route = await GoogleMapsService.getRoute(
      _lastDriverPos!.latitude,
      _lastDriverPos!.longitude,
      (pickup['lat'] as num).toDouble(),
      (pickup['lng'] as num).toDouble(),
    );

    if (route != null && mounted) {
      setState(() {
        _approachRouteCoords = route.coordinates;
        _cameraFitted = false; // force refit
        _fitCameraToCurrentRoute();
      });
    }
  }

  void _fitCameraToCurrentRoute() {
    if (_ride == null || _mapController == null) return;

    final status = _ride!['status'] ?? 'matched';
    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;

    void includePoint(double lat, double lng) {
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
      if (lng < minLng) minLng = lng;
      if (lng > maxLng) maxLng = lng;
    }

    if (status == 'started') {
      if (_ride!['pickup'] != null) {
        includePoint(
          (_ride!['pickup']['lat'] as num).toDouble(),
          (_ride!['pickup']['lng'] as num).toDouble(),
        );
      }
      if (_ride!['drop'] != null) {
        includePoint(
          (_ride!['drop']['lat'] as num).toDouble(),
          (_ride!['drop']['lng'] as num).toDouble(),
        );
      }
      if (_ride!['routeCoordinates'] != null) {
        for (final c in _ride!['routeCoordinates']) {
          includePoint(
            (c['lat'] as num).toDouble(),
            (c['lng'] as num).toDouble(),
          );
        }
      }
    } else {
      if (_ride!['pickup'] != null) {
        includePoint(
          (_ride!['pickup']['lat'] as num).toDouble(),
          (_ride!['pickup']['lng'] as num).toDouble(),
        );
      }
      if (_lastDriverPos != null) {
        includePoint(_lastDriverPos!.latitude, _lastDriverPos!.longitude);
      }
      for (final c in _approachRouteCoords) {
        includePoint(c.latitude, c.longitude);
      }
    }

    if (minLat > maxLat) return; // no valid points

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
    _cameraFitted = true;
  }

  Future<void> _startRide() async {
    // Verify OTP first
    final enteredOtp = _otpControllers.map((c) => c.text).join();
    final expectedOtp = _ride?['rideOtp'] ?? '';

    if (enteredOtp.length != 4) {
      CustomToast.show(
        context: context,
        message: '⚠️ Please enter the complete 4-digit OTP',
        isError: true,
      );
      return;
    }

    if (enteredOtp != expectedOtp) {
      CustomToast.show(
        context: context,
        message: '❌ Wrong OTP! Please verify the rider.',
        isError: true,
      );
      // Clear OTP fields
      for (final c in _otpControllers) {
        c.clear();
      }
      if (_otpFocusNodes.isNotEmpty) {
        _otpFocusNodes[0].requestFocus();
      }
      return;
    }

    // OTP matched!
    setState(() => _updating = true);

    CustomToast.show(
      context: context,
      message: '⏳ Verifying OTP with server...',
    );

    try {
      final callable = FirebaseFunctions.instance.httpsCallable('startRide');
      await callable.call({'rideId': widget.rideId});
      
      if (mounted) {
        CustomToast.show(
          context: context,
          message: '✅ OTP Verified! Ride started.',
        );
      }
    } catch (e) {
      debugPrint('Error starting ride: $e');
      if (mounted) {
        CustomToast.show(
          context: context,
          message: '❌ Failed to start ride. Please try again.',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _updating = false);
      }
    }
  }

  Future<void> _completeRide() async {
    setState(() => _updating = true);
    
    CustomToast.show(
      context: context,
      message: '⏳ Completing ride...',
    );

    try {
      final callable = FirebaseFunctions.instance.httpsCallable('completeRide');
      await callable.call({'rideId': widget.rideId});

      // Stop the foreground tracking service as the ride is now over
      try {
        await FlutterForegroundTask.stopService();
      } catch (e) {
        debugPrint('Error stopping foreground task: $e');
      }

      // The Firestore stream will update _ride status to 'completed',
      // and the build() method will then render _buildEndScreen automatically.
    } catch (e) {
      debugPrint('Error completing ride: $e');
      if (mounted) {
        CustomToast.show(
          context: context,
          message: '❌ Failed to complete ride. Check connection.',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _updating = false);
      }
    }
  }

  Future<void> _cancelRide() async {
    if (_updating) return;
    setState(() => _updating = true);

    try {
      final callable = FirebaseFunctions.instance.httpsCallable('cancelRide');
      await callable.call({'rideId': widget.rideId});

      // Stop the foreground tracking service as the ride is cancelled
      try {
        await FlutterForegroundTask.stopService();
      } catch (e) {
        debugPrint('Error stopping foreground task: $e');
      }

      // ✅ Only reset local state on successful write
      if (!mounted) return;
      context.read<DriverProvider>().setActiveRide(null);
    } catch (e) {
      debugPrint('Error cancelling ride: $e');
      if (mounted) {
        CustomToast.show(
          context: context,
          message: '❌ Failed to cancel ride. Please try again.',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _updating = false);
      }
    }
  }

  Widget _buildEndScreen(String status) {
    final isCompleted = status == 'completed';

    _confettiController ??= ConfettiController(duration: const Duration(seconds: 4));
    if (isCompleted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _confettiController?.play();
      });
    }

    // Try to parse ride stats from Firestore
    final finalPrice = _ride?['finalPrice'] ?? _ride?['riderBid'] ?? 0;
    final distanceKm = _ride?['distanceKm'];
    final durationMin = _ride?['durationMin'];

    return Container(
      color: AppTheme.surface,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          if (isCompleted)
            Align(
              alignment: Alignment.topCenter,
              child: ConfettiWidget(
                confettiController: _confettiController!,
                blastDirection: pi / 2,
                blastDirectionality: BlastDirectionality.explosive,
                emissionFrequency: 0.06,
                numberOfParticles: 20,
                maxBlastForce: 30,
                minBlastForce: 10,
                gravity: 0.3,
                shouldLoop: false,
                colors: const [
                  Color(0xFF10B981),
                  Color(0xFFF59E0B),
                  Color(0xFF3B82F6),
                  Color(0xFFEF4444),
                  Color(0xFF8B5CF6),
                  Color(0xFFF97316),
                ],
              ),
            ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  // Icon
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: (isCompleted ? AppTheme.success : AppTheme.danger)
                          .withValues(alpha: 0.12),
                    ),
                    child: Icon(
                      isCompleted ? Icons.check_circle_rounded : Icons.cancel_rounded,
                      color: isCompleted ? AppTheme.success : AppTheme.danger,
                      size: 86,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    isCompleted ? 'Ride Completed! 🎉' : 'Ride Cancelled',
                    style: GoogleFonts.inter(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isCompleted
                        ? 'Great job! Collect cash from the rider.'
                        : 'The ride was cancelled.',
                    style: GoogleFonts.inter(fontSize: 14, color: AppTheme.text2),
                    textAlign: TextAlign.center,
                  ),

                  if (isCompleted) ...[
                    const SizedBox(height: 28),
                    // Fare card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppTheme.bg2,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Column(
                        children: [
                          Text(
                            '₹$finalPrice',
                            style: GoogleFonts.inter(
                              fontSize: 52,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.success,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Total Fare — 100% goes to you',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: AppTheme.text2,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Divider(),
                          const SizedBox(height: 12),
                          // Stats row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _statChip(
                                Icons.route_rounded,
                                distanceKm != null
                                    ? '${(distanceKm as num).toStringAsFixed(1)} km'
                                    : '—',
                                'Distance',
                              ),
                              _statChip(
                                Icons.timer_rounded,
                                durationMin != null
                                    ? '$durationMin min'
                                    : '—',
                                'Duration',
                              ),
                              _statChip(
                                Icons.percent_rounded,
                                '0%',
                                'Commission',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Zero commission banner
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          const Text('🎯', style: TextStyle(fontSize: 20)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Ashwa takes ZERO commission. Every rupee goes to you!',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.success,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        _confettiController?.stop();
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(
                            builder: (_) => const DashboardScreen(),
                          ),
                          (_) => false,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        backgroundColor: AppTheme.primary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      child: Text(
                        'Back to Dashboard',
                        style: GoogleFonts.inter(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statChip(IconData icon, String value, String label) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 22, color: AppTheme.primary),
        ),
        const SizedBox(height: 6),
        Text(value,
            style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: AppTheme.text)),
        Text(label,
            style: GoogleFonts.inter(fontSize: 11, color: AppTheme.text3)),
      ],
    );
  }

  void _openNavigation() async {
    if (_ride == null) return;
    final status = _ride!['status'];
    double? lat;
    double? lng;

    if (status == 'matched' && _ride!['pickup'] != null) {
      lat = (_ride!['pickup']['lat'] as num).toDouble();
      lng = (_ride!['pickup']['lng'] as num).toDouble();
    } else if (status == 'started' && _ride!['drop'] != null) {
      lat = (_ride!['drop']['lat'] as num).toDouble();
      lng = (_ride!['drop']['lng'] as num).toDouble();
    }

    if (lat != null && lng != null) {
      final url = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        if (mounted) {
          CustomToast.show(
            context: context,
            message: 'Could not open Google Maps',
            isError: true,
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ride == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      );
    }

    final provider = context.watch<DriverProvider>();
    final status = _ride!['status'] ?? 'matched';
    final isEndState = status == 'completed' || status == 'cancelled';

    final routeCoords = <LatLng>[];
    if (status == 'matched') {
      routeCoords.addAll(_approachRouteCoords);
    } else if (status == 'started') {
      if (_ride!['routeCoordinates'] != null) {
        for (final c in _ride!['routeCoordinates']) {
          routeCoords.add(
            LatLng((c['lat'] as num).toDouble(), (c['lng'] as num).toDouble()),
          );
        }
      }
    }

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            // Push Google Maps UI elements (compass, my-location) below the top bar and above bottom sheet
            padding: EdgeInsets.only(
              top: 90,
              bottom: status == 'matched' ? 320 : 380,
            ),
            style: lightMapStyle,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            initialCameraPosition: CameraPosition(
              target: provider.lat != null
                  ? LatLng(provider.lat!, provider.lng!)
                  : (routeCoords.isNotEmpty
                        ? routeCoords.first
                        : const LatLng(17.385, 78.487)),
              zoom: 14,
            ),
            onMapCreated: (controller) {
              _mapController = controller;
              // Fit camera to route when map is ready
              if (_ride != null && !_cameraFitted) {
                Future.delayed(const Duration(milliseconds: 500), () {
                  if (mounted) _fitCameraToCurrentRoute();
                });
              }
            },
            polylines: routeCoords.isNotEmpty
                ? {
                    Polyline(
                      polylineId: const PolylineId('route'),
                      points: routeCoords,
                      color: AppTheme.primary,
                      width: 5,
                    ),
                  }
                : {},
            markers: {
              if (_ride!['pickup'] != null && status == 'matched')
                Marker(
                  markerId: const MarkerId('pickup'),
                  position: LatLng(
                    (_ride!['pickup']['lat'] as num).toDouble(),
                    (_ride!['pickup']['lng'] as num).toDouble(),
                  ),
                  icon: _riderPinIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
                  anchor: const Offset(0.5, 0.5),
                  zIndexInt: 1,
                ),
              if (_ride!['pickup'] != null && status == 'matched' && _riderLabelIcon != null)
                Marker(
                  markerId: const MarkerId('rider_label'),
                  position: LatLng(
                    (_ride!['pickup']['lat'] as num).toDouble(),
                    (_ride!['pickup']['lng'] as num).toDouble(),
                  ),
                  icon: _riderLabelIcon!,
                  anchor: const Offset(0.5, 1.8),
                  zIndexInt: 2,
                ),
              if (_ride!['drop'] != null && status == 'started')
                Marker(
                  markerId: const MarkerId('drop'),
                  position: LatLng(
                    (_ride!['drop']['lat'] as num).toDouble(),
                    (_ride!['drop']['lng'] as num).toDouble(),
                  ),
                  // Use the standard red pin so it points precisely at the location
                  icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                ),
            },
          ),

          // Top bar: status chip + navigate button in same row, hidden when ride ends
          if (!isEndState)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: status == 'started'
                              ? AppTheme.success.withValues(alpha: 0.15)
                              : AppTheme.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: status == 'started' ? AppTheme.success : AppTheme.primary,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              status == 'started' ? Icons.navigation : Icons.check_circle,
                              color: status == 'started' ? AppTheme.success : AppTheme.primary,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                status == 'started'
                                    ? '🚀 Ride in Progress'
                                    : '🔐 Verify Rider OTP${_driverProximity.isNotEmpty ? " • $_driverProximity" : ""}',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w700,
                                  color: status == 'started' ? AppTheme.success : AppTheme.primary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Navigate FAB — same row as status chip
                    FloatingActionButton.small(
                      heroTag: 'nav_fab',
                      onPressed: _openNavigation,
                      backgroundColor: AppTheme.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 4,
                      child: const Icon(Icons.navigation, color: Colors.white, size: 20),
                    ),
                  ],
                ),
              ),
            ),

          // Bottom panel — hidden when ride ends (end screen covers everything)
          if (!isEndState)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildBottomPanel(status),
            ),

          // Success / Cancellation Overlay
          if (isEndState) Positioned.fill(child: _buildEndScreen(status)),
        ],
      ),
    );
  }

  Widget _buildBottomPanel(String status) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: const Border(top: BorderSide(color: AppTheme.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 40,
            offset: const Offset(0, -10),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: AppTheme.text3,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // ── Compact ride info row ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.circle, size: 7, color: AppTheme.success),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _ride!['pickup']?['short_name'] ?? '',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.location_on, size: 9, color: AppTheme.danger),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _ride!['drop']?['short_name'] ?? '',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
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
                  Text(
                    '₹${_ride!['finalPrice'] ?? _ride!['riderBid']}',
                    style: GoogleFonts.inter(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.success,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // ── Status-specific sections ──
            if (status == 'matched') ...[
              // ── OTP input first ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primary.withValues(alpha: 0.10),
                      AppTheme.primary.withValues(alpha: 0.03),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.shield, size: 14, color: AppTheme.primary),
                        const SizedBox(width: 5),
                        Text(
                          'Enter Rider OTP',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(4, (i) {
                        return Container(
                          width: 50,
                          height: 58,
                          margin: const EdgeInsets.symmetric(horizontal: 5),
                          child: TextField(
                            controller: _otpControllers[i],
                            focusNode: _otpFocusNodes[i],
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            maxLength: 1,
                            style: GoogleFonts.inter(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.primary,
                            ),
                            decoration: InputDecoration(
                              counterText: '',
                              contentPadding: const EdgeInsets.symmetric(vertical: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: AppTheme.border),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: AppTheme.primary, width: 2),
                              ),
                              filled: true,
                              fillColor: AppTheme.bg,
                            ),
                            onChanged: (val) {
                              if (val.isNotEmpty && i < 3) {
                                _otpFocusNodes[i + 1].requestFocus();
                              } else if (val.isEmpty && i > 0) {
                                _otpFocusNodes[i - 1].requestFocus();
                              }
                            },
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // ── Call + Verify buttons below OTP ──
              Row(
                children: [
                  if (_ride!['riderPhone'] != null)
                    Expanded(
                      flex: 1,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final phone = _ride!['riderPhone'];
                          final uri = Uri.parse('tel:$phone');
                          if (await canLaunchUrl(uri)) await launchUrl(uri);
                        },
                        icon: const Icon(Icons.phone, size: 16),
                        label: Text('Call', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: const BorderSide(color: AppTheme.border),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  if (_ride!['riderPhone'] != null) const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _updating ? null : _startRide,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.success,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: _updating
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                          : Text('🚀 Verify & Start',
                              style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                  ),
                ],
              ),
            ] else if (status == 'started') ...[
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _updating ? null : _completeRide,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.success,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _updating
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                      : Text(
                          '✅ Complete & Collect Cash',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                ),
              ),
            ],

            const SizedBox(height: 8),
            SwipeAction(
              text: 'Swipe to Cancel',
              onSwipe: () {
                if (!_updating) _cancelRide();
              },
              baseColor: AppTheme.danger,
              activeColor: AppTheme.danger,
            ),
          ],
        ),
      ),
    );
  }
}
