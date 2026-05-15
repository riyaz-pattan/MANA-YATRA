// lib/screens/active_ride_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/custom_toast.dart';
import 'package:geolocator/geolocator.dart';
import '../config/theme.dart';
import '../services/google_maps_service.dart';
import '../utils/map_style.dart';
import '../utils/map_utils.dart';
import 'package:provider/provider.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../providers/driver_provider.dart';
import '../services/smart_tracker.dart';
import '../services/sync_engine.dart';
import '../models/queue_item.dart';
import 'package:uuid/uuid.dart';
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
  double _driverHeading = 0.0;
  String _driverProximity = '';
  DriverProvider? _driverProvider;

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
          final data = snap.data()!;
          final prevStatus = _ride?['status'];
          data['id'] = snap.id;
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
            _showEndDialog(data['status']);
          }
        });
  }

  void _onDriverLocationChanged() {
    if (_driverProvider?.lat != null && _driverProvider?.lng != null) {
      final newPos = LatLng(_driverProvider!.lat!, _driverProvider!.lng!);
      if (_lastDriverPos != null &&
          (newPos.latitude != _lastDriverPos!.latitude ||
              newPos.longitude != _lastDriverPos!.longitude)) {
        _driverHeading = Geolocator.bearingBetween(
          _lastDriverPos!.latitude,
          _lastDriverPos!.longitude,
          newPos.latitude,
          newPos.longitude,
        );
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
      _riderPinIcon = await MapUtils.createPersonMarker();
      _riderLabelIcon = await MapUtils.createLabelMarker('Rider is here');
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _fetchApproachRoute() async {
    if (_isFetchingApproach ||
        _approachRouteCoords.isNotEmpty ||
        _lastDriverPos == null ||
        _ride == null)
      return;
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
      if (_ride!['pickup'] != null)
        includePoint(
          (_ride!['pickup']['lat'] as num).toDouble(),
          (_ride!['pickup']['lng'] as num).toDouble(),
        );
      if (_ride!['drop'] != null)
        includePoint(
          (_ride!['drop']['lat'] as num).toDouble(),
          (_ride!['drop']['lng'] as num).toDouble(),
        );
      if (_ride!['routeCoordinates'] != null) {
        for (final c in _ride!['routeCoordinates']) {
          includePoint(
            (c['lat'] as num).toDouble(),
            (c['lng'] as num).toDouble(),
          );
        }
      }
    } else {
      if (_ride!['pickup'] != null)
        includePoint(
          (_ride!['pickup']['lat'] as num).toDouble(),
          (_ride!['pickup']['lng'] as num).toDouble(),
        );
      if (_lastDriverPos != null)
        includePoint(_lastDriverPos!.latitude, _lastDriverPos!.longitude);
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
      message: '✅ OTP Verified! Starting ride...',
    );

    try {
      final operationId = const Uuid().v4();
      final item = QueueItem(
        id: operationId,
        type: 'START_RIDE',
        payload: {'rideId': widget.rideId},
      );
      await context.read<SyncEngine>().enqueue(item);
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

    try {
      final operationId = const Uuid().v4();
      final item = QueueItem(
        id: operationId,
        type: 'COMPLETE_RIDE',
        payload: {'rideId': widget.rideId},
      );
      await context.read<SyncEngine>().enqueue(item);

      if (!mounted) return;

      // Show end dialog directly — backend already handled driver state reset
      _showEndDialog('completed');
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
      final operationId = const Uuid().v4();
      final item = QueueItem(
        id: operationId,
        type: 'CANCEL_RIDE',
        payload: {'rideId': widget.rideId},
      );
      await context.read<SyncEngine>().enqueue(item);

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

  void _showEndDialog(String status) {
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                status == 'completed' ? '✅' : '❌',
                style: const TextStyle(fontSize: 52),
              ),
              const SizedBox(height: 16),
              Text(
                status == 'completed' ? 'Ride Completed!' : 'Ride Cancelled',
                style: GoogleFonts.inter(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (status == 'completed' && _ride != null) ...[
                const SizedBox(height: 12),
                Text(
                  '₹${_ride!['finalPrice'] ?? ''}',
                  style: GoogleFonts.inter(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.success,
                  ),
                ),
                Text(
                  'Collect Cash',
                  style: GoogleFonts.inter(color: AppTheme.text3, fontSize: 14),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                        builder: (_) => const DashboardScreen(),
                      ),
                      (_) => false,
                    );
                  },
                  child: const Text('Back to Dashboard'),
                ),
              ),
            ],
          ),
        ),
      );
    });
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
                  zIndex: 1,
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
                  zIndex: 2,
                ),
              if (_ride!['drop'] != null && status == 'started')
                Marker(
                  markerId: const MarkerId('drop'),
                  position: LatLng(
                    (_ride!['drop']['lat'] as num).toDouble(),
                    (_ride!['drop']['lng'] as num).toDouble(),
                  ),
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueRed,
                  ),
                ),
            },
          ),

          // Status bar
          SafeArea(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: status == 'started'
                    ? AppTheme.success.withValues(alpha: 0.2)
                    : AppTheme.primary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: status == 'started'
                      ? AppTheme.success
                      : AppTheme.primary,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    status == 'started'
                        ? Icons.navigation
                        : Icons.check_circle,
                    color: status == 'started'
                        ? AppTheme.success
                        : AppTheme.primary,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    status == 'started'
                        ? '🚀 Ride in Progress'
                        : '🔐 Verify Rider OTP${_driverProximity.isNotEmpty ? " • $_driverProximity" : ""}',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      color: status == 'started'
                          ? AppTheme.success
                          : AppTheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom panel
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomPanel(status),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPanel(String status) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.of(context).padding.bottom + 16,
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
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppTheme.text3,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Ride info
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.bg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.circle,
                              size: 8,
                              color: AppTheme.success,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _ride!['pickup']?['short_name'] ?? '',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on,
                              size: 10,
                              color: AppTheme.danger,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _ride!['drop']?['short_name'] ?? '',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '₹${_ride!['finalPrice'] ?? _ride!['riderBid']}',
                    style: GoogleFonts.inter(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.success,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Call button
            if (_ride!['riderPhone'] != null) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final phone = _ride!['riderPhone'];
                    final uri = Uri.parse('tel:$phone');
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri);
                    }
                  },
                  icon: const Icon(Icons.phone, size: 18),
                  label: Text(
                    'Call Rider',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppTheme.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Action buttons
            if (status == 'matched') ...[
              // OTP input section
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primary.withValues(alpha: 0.12),
                      AppTheme.primary.withValues(alpha: 0.04),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppTheme.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.shield,
                          size: 18,
                          color: AppTheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Ask rider for their OTP',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Verify the rider is the correct person before starting',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppTheme.text3,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(4, (i) {
                        return Container(
                          width: 54,
                          height: 60,
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          child: TextField(
                            controller: _otpControllers[i],
                            focusNode: _otpFocusNodes[i],
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            maxLength: 1,
                            style: GoogleFonts.inter(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.primary,
                            ),
                            decoration: InputDecoration(
                              counterText: '',
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 14,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: AppTheme.border,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: AppTheme.primary,
                                  width: 2,
                                ),
                              ),
                              filled: true,
                              fillColor: AppTheme.surface,
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
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _updating ? null : _startRide,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.success,
                  ),
                  child: _updating
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          '🚀 Verify & Start Ride',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                ),
              ),
            ] else if (status == 'started') ...[
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _updating ? null : _completeRide,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.success,
                  ),
                  child: _updating
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          '✅ Complete & Collect Cash',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                ),
              ),
            ],

            const SizedBox(height: 10),
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
