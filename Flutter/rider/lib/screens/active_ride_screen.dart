// lib/screens/active_ride_screen.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:confetti/confetti.dart';
import '../config/theme.dart';
import '../config/constants.dart';
import '../providers/ride_provider.dart';
import '../services/google_maps_service.dart';
import '../utils/map_style.dart';
import '../utils/map_utils.dart';
import '../utils/marker_utils.dart';
import 'main_screen.dart';
import '../utils/custom_toast.dart';
import '../widgets/swipe_action.dart';
import '../utils/skeleton.dart';

class ActiveRideScreen extends StatefulWidget {
  final String rideId;
  const ActiveRideScreen({super.key, required this.rideId});

  @override
  State<ActiveRideScreen> createState() => _ActiveRideScreenState();
}

class _ActiveRideScreenState extends State<ActiveRideScreen> {
  GoogleMapController? _mapController;
  Map<String, dynamic>? _ride;
  LatLng? _driverPos;
  StreamSubscription? _rideListener;
  StreamSubscription? _locationListener;
  bool _cameraFitted = false;
  BitmapDescriptor? _vehicleIcon;
  BitmapDescriptor? _driverLabelIcon;
  BitmapDescriptor? _dropDot;
  List<LatLng> _approachRouteCoords = [];
  bool _isFetchingApproach = false;
  double _driverHeading = 0.0;
  String _driverProximity = '';
  bool _updating = false;
  bool _isDriverSignalStale = false;
  ConfettiController? _confettiController;

  @override
  void initState() {
    super.initState();
    _listenRide();
  }

  @override
  void dispose() {
    _rideListener?.cancel();
    _locationListener?.cancel();
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
        data['id'] = snap.id;
        if (!mounted) return;
        setState(() => _ride = data);

        // Fit camera to route once
        if (!_cameraFitted && _mapController != null) {
          _fitCameraToCurrentRoute();
        }

        // Load custom vehicle icon
        if (_vehicleIcon == null) {
          _loadIcon(data['vehicleType'] ?? 'auto');
        }

        // Start listening to driver location when ride has a driver
        if (data['driverId'] != null && _locationListener == null) {
          _listenDriverLocation(data['driverId']);
        }
        
        // Fetch approach route if matched
        if (data['status'] == 'matched' && _driverPos != null) {
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

  Future<void> _loadIcon(String type) async {
    final path = 'assets/images/map_icons/$type.png';
    try {
      _vehicleIcon = await MapUtils.getBytesFromAsset(path, 100);
      _driverLabelIcon = await MapUtils.createLabelMarker('Driver is here');
      _dropDot = await MarkerGenerator.createDotMarker(color: AppTheme.danger);
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _fetchApproachRoute() async {
    if (_isFetchingApproach || _approachRouteCoords.isNotEmpty || _driverPos == null || _ride == null) return;
    final pickup = _ride!['pickup'];
    if (pickup == null) return;

    setState(() => _isFetchingApproach = true);
    final route = await GoogleMapsService.getRoute(
      _driverPos!.latitude,
      _driverPos!.longitude,
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
       if (_ride!['pickup'] != null) includePoint((_ride!['pickup']['lat'] as num).toDouble(), (_ride!['pickup']['lng'] as num).toDouble());
       if (_ride!['drop'] != null) includePoint((_ride!['drop']['lat'] as num).toDouble(), (_ride!['drop']['lng'] as num).toDouble());
       if (_ride!['routeCoordinates'] != null) {
          for (final c in _ride!['routeCoordinates']) {
             includePoint((c['lat'] as num).toDouble(), (c['lng'] as num).toDouble());
          }
       }
    } else {
       if (_ride!['pickup'] != null) includePoint((_ride!['pickup']['lat'] as num).toDouble(), (_ride!['pickup']['lng'] as num).toDouble());
       if (_driverPos != null) includePoint(_driverPos!.latitude, _driverPos!.longitude);
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


  void _listenDriverLocation(String driverId) {
    final ref =
        FirebaseDatabase.instance.ref('liveLocations/$driverId');
    _locationListener = ref.onValue.listen((event) {
      if (event.snapshot.value != null) {
        try {
          final data = Map<String, dynamic>.from(
              event.snapshot.value as Map);
          final lat = (data['lat'] as num).toDouble();
          final lng = (data['lng'] as num).toDouble();
          final newPos = LatLng(lat, lng);
          
          if (_driverPos != null && (newPos.latitude != _driverPos!.latitude || newPos.longitude != _driverPos!.longitude)) {
             _driverHeading = Geolocator.bearingBetween(
                _driverPos!.latitude, _driverPos!.longitude,
                newPos.latitude, newPos.longitude,
             );
          }
          
          // Calculate proximity
          String proximity = '';
          if (_ride != null && _ride!['pickup'] != null) {
             final pLat = (_ride!['pickup']['lat'] as num).toDouble();
             final pLng = (_ride!['pickup']['lng'] as num).toDouble();
             final dist = Geolocator.distanceBetween(lat, lng, pLat, pLng);
             if (dist < 100) {
               proximity = 'Arriving soon';
             } else if (dist < 1000) {
               proximity = '${dist.round()}m away';
             } else {
               proximity = '${(dist/1000).toStringAsFixed(1)}km away';
             }
          }
          
          // Check stale signal (if updated > 30s ago)
          bool isStale = false;
          if (data['updatedAt'] != null) {
            final updatedAt = data['updatedAt'] as int;
            final now = DateTime.now().millisecondsSinceEpoch;
            if (now - updatedAt > 30000) {
              isStale = true;
            }
          }

          if (mounted) {
            setState(() {
              _driverPos = newPos;
              _driverProximity = proximity;
              _isDriverSignalStale = isStale;
            });
          }

          if (_ride?['status'] == 'matched') {
             _fetchApproachRoute();
             if (_cameraFitted) {
                // we keep camera stable, user can manually move
             } else {
                _mapController?.animateCamera(CameraUpdate.newLatLng(newPos));
             }
          }
        } catch (e) {
          debugPrint('Error parsing driver location: $e');
        }
      }
    }, onError: (error) {
      debugPrint('RTDB driver location error: $error');
    });
  }

  Widget _buildEndScreen(String status) {
    final isCompleted = status == 'completed';

    _confettiController ??= ConfettiController(duration: const Duration(seconds: 4));
    if (isCompleted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _confettiController?.play();
      });
    }

    final finalPrice = _ride?['finalPrice'] ?? _ride?['riderBid'] ?? 0;
    final distanceKm = _ride?['distanceKm'];
    final durationMin = _ride?['durationMin'];

    return Container(
      color: Colors.black.withValues(alpha: 0.6), // Semi-transparent overlay
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
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.bg,
                borderRadius: BorderRadius.circular(32),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Icon
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: (isCompleted ? AppTheme.success : AppTheme.danger)
                            .withValues(alpha: 0.12),
                      ),
                      child: Icon(
                        isCompleted ? Icons.check_circle_rounded : Icons.cancel_rounded,
                        color: isCompleted ? AppTheme.success : AppTheme.danger,
                        size: 60,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isCompleted ? 'Ride Completed! 🎉' : 'Ride Cancelled',
                      style: GoogleFonts.inter(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isCompleted
                          ? 'Thank you for riding with Ashwa!'
                          : 'The ride was cancelled.',
                      style: GoogleFonts.inter(fontSize: 14, color: AppTheme.text2),
                      textAlign: TextAlign.center,
                    ),

                    if (isCompleted) ...[
                      const SizedBox(height: 24),
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
                                fontSize: 42,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.success,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Total Fare — Paid via Cash',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: AppTheme.text2,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Divider(),
                            const SizedBox(height: 12),
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
                                  durationMin != null ? '$durationMin min' : '—',
                                  'Duration',
                                ),
                                _statChip(
                                  Icons.percent_rounded,
                                  '0%',
                                  'App Fee',
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
                                'Ashwa takes ZERO commission. 100% of the fare goes directly to your driver!',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.success,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          _confettiController?.stop();
                          context.read<RideProvider>().resetRide();
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(builder: (_) => const MainScreen()),
                            (_) => false,
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: AppTheme.primary,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        child: Text(
                          'Back to Home',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
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
                fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.text)),
        Text(label,
            style: GoogleFonts.inter(fontSize: 11, color: AppTheme.text3)),
      ],
    );
  }

  Future<void> _cancelRide() async {
    if (_updating) return;
    setState(() => _updating = true);

    try {
      final callable = FirebaseFunctions.instance.httpsCallable('cancelRide');
      await callable.call({'rideId': widget.rideId});

      if (!mounted) return;
      context.read<RideProvider>().resetRide();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainScreen()),
        (_) => false,
      );
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

  @override
  Widget build(BuildContext context) {
    if (_ride == null) {
      return Scaffold(
        body: Stack(
          children: [
            const SkeletonBox(height: double.infinity),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 340,
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 20,
                      offset: const Offset(0, -5),
                    )
                  ],
                ),
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: SkeletonBox(width: 40, height: 4, borderRadius: 2)),
                    const SizedBox(height: 24),
                    const SkeletonBox(width: 140, height: 28, borderRadius: 8),
                    const SizedBox(height: 24),
                    const SkeletonBox(width: double.infinity, height: 80, borderRadius: 16),
                    const SizedBox(height: 16),
                    const SkeletonBox(width: double.infinity, height: 60, borderRadius: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    final status = _ride!['status'] ?? 'matched';
    final isEndState = status == 'completed' || status == 'cancelled';

    // Build route coordinates based on status
    final routeCoords = <LatLng>[];
    if (status == 'matched') {
      routeCoords.addAll(_approachRouteCoords);
    } else if (status == 'started' || status == 'completed') {
      if (_ride!['routeCoordinates'] != null) {
        for (final c in _ride!['routeCoordinates']) {
          routeCoords.add(LatLng(
            (c['lat'] as num).toDouble(),
            (c['lng'] as num).toDouble(),
          ));
        }
      }
    }

    return Scaffold(
      body: Stack(
        children: [
          // Map
          GoogleMap(
            // Ensure maps buttons (zoom, etc) are above the bottom sheet in all states
            padding: EdgeInsets.only(bottom: status == 'matched' ? 320 : 340),
            style: lightMapStyle,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            initialCameraPosition: CameraPosition(
              target: _driverPos ??
                  (routeCoords.isNotEmpty
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
                      width: 4,
                    )
                  }
                : {},
            markers: {
              // Rider's own location is shown by the native blue dot (myLocationEnabled: true).
              // No custom pickup marker needed — avoids the green icon confusion.
              if (_ride!['drop'] != null && status == 'started')
                Marker(
                  markerId: const MarkerId('drop'),
                  position: LatLng(
                    (_ride!['drop']['lat'] as num).toDouble(),
                    (_ride!['drop']['lng'] as num).toDouble(),
                  ),
                  icon: _dropDot ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                ),
              if (_driverPos != null)
                Marker(
                  markerId: const MarkerId('driver'),
                  position: _driverPos!,
                  icon: _vehicleIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
                  rotation: _driverHeading,
                  anchor: const Offset(0.5, 0.5),
                  zIndexInt: 1,
                ),
              // Only show "Driver is here" label during matched phase; hide once ride starts
              if (_driverPos != null && _driverLabelIcon != null && status == 'matched')
                Marker(
                  markerId: const MarkerId('driver_label'),
                  position: _driverPos!,
                  icon: _driverLabelIcon!,
                  anchor: const Offset(0.5, 1.8),
                  zIndexInt: 2,
                ),
            },
          ),

          // Status bar — hidden when ride ends
          if (!isEndState)
            SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
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
                        Expanded(
                          child: Text(
                            status == 'started'
                                ? '🚀 Ride in Progress'
                                : '✅ Driver Matched${_driverProximity.isNotEmpty ? " • $_driverProximity" : ""}',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                              color: status == 'started'
                                  ? AppTheme.success
                                  : AppTheme.primary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_isDriverSignalStale && (status == 'matched' || status == 'started'))
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.warning,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.signal_wifi_bad, color: Colors.white, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              'Driver signal lost. Updating...',
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),

          // Bottom driver info panel — hidden when ride ends
          if (!isEndState)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildDriverPanel(),
            ),

          // Success / Cancellation Overlay
          if (isEndState) Positioned.fill(child: _buildEndScreen(status)),
        ],
      ),
    );
  }

  Widget _buildDriverPanel() {
    final vType = _ride!['vehicleType'] ?? 'auto';
    final icon = AppConstants.vehicleTypes[vType]?.icon ?? '🚗';

    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).padding.bottom + 16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(24)),
        border: const Border(top: BorderSide(color: AppTheme.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 40,
            offset: const Offset(0, -10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppTheme.text3,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          Row(
            children: [
              // Driver avatar
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppTheme.bg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.border),
                  image: _ride!['driverImageUrl'] != null && _ride!['driverImageUrl'].toString().isNotEmpty
                      ? DecorationImage(
                          image: NetworkImage(_ride!['driverImageUrl']),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: _ride!['driverImageUrl'] == null || _ride!['driverImageUrl'].toString().isEmpty
                    ? Center(
                        child: Text(icon, style: const TextStyle(fontSize: 28)),
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _ride!['driverName'] ?? 'Driver',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _ride!['vehicleNumber'] ?? '',
                      style: GoogleFonts.inter(
                        color: AppTheme.text2,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₹${_ride!['finalPrice'] ?? _ride!['riderBid']}',
                    style: GoogleFonts.inter(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.success,
                    ),
                  ),
                  Text(
                    'Cash',
                    style: GoogleFonts.inter(
                      color: AppTheme.text3,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // OTP Verification Code
          if (_ride!['rideOtp'] != null && (_ride!['status'] == 'matched')) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primary.withValues(alpha: 0.12),
                    AppTheme.primary.withValues(alpha: 0.04),
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  // Label
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.shield, size: 13, color: AppTheme.primary),
                          const SizedBox(width: 4),
                          Text(
                            'Your OTP',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Share with driver',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          color: AppTheme.text3,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // OTP digits — compact
                  Row(
                    children: (_ride!['rideOtp'] as String).split('').map((d) {
                      return Container(
                        width: 40,
                        height: 46,
                        margin: const EdgeInsets.only(left: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.primary, width: 1.5),
                        ),
                        child: Center(
                          child: Text(
                            d,
                            style: GoogleFonts.inter(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.primary,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Route info
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.circle, size: 8, color: AppTheme.success),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _ride!['pickup']?['short_name'] ?? '',
                    style: GoogleFonts.inter(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward,
                      size: 16, color: AppTheme.text3),
                ),
                const Icon(Icons.location_on,
                    size: 10, color: AppTheme.danger),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _ride!['drop']?['short_name'] ?? '',
                    style: GoogleFonts.inter(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // Call and SOS buttons
          if (_ride!['driverPhone'] != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final phone = _ride!['driverPhone'];
                      final uri = Uri.parse('tel:$phone');
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri);
                      }
                    },
                    icon: const Icon(Icons.phone, size: 18),
                    label: Text(
                      'Call Driver',
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
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final lat = _driverPos?.latitude ?? _ride!['pickup']['lat'];
                      final lng = _driverPos?.longitude ?? _ride!['pickup']['lng'];
                      final message = "🚨 SOS EMERGENCY ALERT! 🚨\n"
                          "I am in an emergency during my Mana Yatra ride.\n\n"
                          "📍 My Live Location: https://maps.google.com/?q=$lat,$lng\n\n"
                          "🚗 Ride Details:\n"
                          "- Driver: ${_ride!['driverName']}\n"
                          "- Vehicle: ${_ride!['vehicleNumber']}\n"
                          "- Driver Phone: ${_ride!['driverPhone']}";
                      
                      // 1. Fetch user's custom emergency contacts
                      final uid = FirebaseAuth.instance.currentUser?.uid;
                      String emergencyNumber = '';
                      
                      if (uid != null) {
                        final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
                        final userData = userDoc.data();
                        final customContacts = (userData?['emergencyContacts'] as List<dynamic>?) ?? [];
                        
                        if (customContacts.isNotEmpty) {
                          // Use the first contact's phone
                          String rawPhone = customContacts.first['phone'] as String;
                          // Remove all non-digit characters
                          emergencyNumber = rawPhone.replaceAll(RegExp(r'\D'), '');
                          
                          // Normalize: If it's a 10-digit number, assume it's Indian and prefix 91
                          if (emergencyNumber.length == 10) {
                            emergencyNumber = '91$emergencyNumber';
                          } else if (emergencyNumber.length > 10 && emergencyNumber.startsWith('0')) {
                            // If it starts with 0 and is more than 10 digits, replace 0 with 91
                            emergencyNumber = '91${emergencyNumber.substring(1)}';
                          }
                        }
                      }

                      // 2. Build URI: If no emergency number, it opens WhatsApp contact picker
                      final uriString = emergencyNumber.isNotEmpty 
                          ? 'whatsapp://send?phone=$emergencyNumber&text=${Uri.encodeComponent(message)}'
                          : 'whatsapp://send?text=${Uri.encodeComponent(message)}';
                      
                      final uri = Uri.parse(uriString);
                      
                      try {
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        } else {
                          // Fallback to web-based API if whatsapp scheme fails
                          final fallbackUriString = emergencyNumber.isNotEmpty
                              ? 'https://wa.me/$emergencyNumber?text=${Uri.encodeComponent(message)}'
                              : 'https://api.whatsapp.com/send?text=${Uri.encodeComponent(message)}';
                          
                          final fallbackUri = Uri.parse(fallbackUriString);
                          if (await canLaunchUrl(fallbackUri)) {
                            await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
                          } else {
                            if (mounted) {
                              CustomToast.show(
                                context: context,
                                message: 'WhatsApp is not installed on your device.',
                                isError: true,
                              );
                            }
                          }
                        }
                      } catch (e) {
                        if (mounted) {
                          CustomToast.show(
                            context: context,
                            message: 'Could not open WhatsApp.',
                            isError: true,
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.warning_rounded, size: 18, color: Colors.white),
                    label: Text(
                      'SOS Alert',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.danger,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
          
          if (_ride!['status'] == 'matched') ...[
            const SizedBox(height: 16),
            SwipeAction(
              text: 'Swipe to Cancel',
              onSwipe: _cancelRide,
              baseColor: AppTheme.danger,
              activeColor: AppTheme.danger,
            ),
          ],
        ],
      ),
    );
  }
}
