// lib/screens/active_ride_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../config/constants.dart';
import '../providers/ride_provider.dart';
import '../services/google_maps_service.dart';
import '../utils/map_style.dart';
import '../utils/map_utils.dart';
import 'main_screen.dart';
import '../utils/custom_toast.dart';
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
  LatLng? _driverPos;
  StreamSubscription? _rideListener;
  StreamSubscription? _locationListener;
  bool _cameraFitted = false;
  BitmapDescriptor? _vehicleIcon;
  BitmapDescriptor? _driverLabelIcon;
  List<LatLng> _approachRouteCoords = [];
  bool _isFetchingApproach = false;
  double _driverHeading = 0.0;
  String _driverProximity = '';
  bool _updating = false;

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
      final data = snap.data()!;
      data['id'] = snap.id;
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
        _showRideEndDialog(data['status']);
      }
    });
  }

  Future<void> _loadIcon(String type) async {
    final path = 'assets/images/map_icons/$type.png';
    try {
      _vehicleIcon = await MapUtils.getBytesFromAsset(path, 100);
      _driverLabelIcon = await MapUtils.createLabelMarker('Driver is here');
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
        
        setState(() {
          _driverPos = newPos;
          _driverProximity = proximity;
        });

        if (_ride?['status'] == 'matched') {
           _fetchApproachRoute();
           if (_cameraFitted) {
              // we keep camera stable, user can manually move
           } else {
              _mapController?.animateCamera(CameraUpdate.newLatLng(newPos));
           }
        }
      }
    });
  }

  void _showRideEndDialog(String status) {
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
                status == 'completed'
                    ? 'Ride Completed!'
                    : 'Ride Cancelled',
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
                  'Cash Payment',
                  style: GoogleFonts.inter(
                    color: AppTheme.text3,
                    fontSize: 14,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    context.read<RideProvider>().resetRide();
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                          builder: (_) => const MainScreen()),
                      (_) => false,
                    );
                  },
                  child: const Text('Back to Home'),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  Future<void> _cancelRide() async {
    if (_updating) return;
    setState(() => _updating = true);

    try {
      final batch = FirebaseFirestore.instance.batch();
      batch.update(
        FirebaseFirestore.instance.collection('rides').doc(widget.rideId),
        {
          'status': 'cancelled',
          'cancelledBy': 'rider',
          'cancelledAt': FieldValue.serverTimestamp(),
        },
      );

      // Reset driver state if a driver was matched
      final driverId = _ride?['driverId'];
      if (driverId != null) {
        batch.update(
          FirebaseFirestore.instance.collection('drivers').doc(driverId),
          {
            'driverState': 'ONLINE_IDLE',
            'activeRideId': null,
            'activeBidCount': 0,
          },
        );
      }
      await batch.commit();
    } catch (e) {
      debugPrint('Error cancelling ride: $e');
    }

    if (!mounted) return;
    context.read<RideProvider>().setActiveRide(null);
    setState(() => _updating = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_ride == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      );
    }

    final status = _ride!['status'] ?? 'matched';
    // Build route coordinates based on status
    final routeCoords = <LatLng>[];
    if (status == 'matched') {
      routeCoords.addAll(_approachRouteCoords);
    } else if (status == 'started') {
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
              if (_ride!['pickup'] != null && status == 'matched')
                Marker(
                  markerId: const MarkerId('pickup'),
                  position: LatLng(
                    (_ride!['pickup']['lat'] as num).toDouble(),
                    (_ride!['pickup']['lng'] as num).toDouble(),
                  ),
                  icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
                ),
              if (_ride!['drop'] != null && status == 'started')
                Marker(
                  markerId: const MarkerId('drop'),
                  position: LatLng(
                    (_ride!['drop']['lat'] as num).toDouble(),
                    (_ride!['drop']['lng'] as num).toDouble(),
                  ),
                  icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                ),
              if (_driverPos != null)
                Marker(
                  markerId: const MarkerId('driver'),
                  position: _driverPos!,
                  icon: _vehicleIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
                  rotation: _driverHeading,
                  anchor: const Offset(0.5, 0.5),
                  zIndex: 1,
                ),
              if (_driverPos != null && _driverLabelIcon != null)
                Marker(
                  markerId: const MarkerId('driver_label'),
                  position: _driverPos!,
                  icon: _driverLabelIcon!,
                  anchor: const Offset(0.5, 1.8),
                  zIndex: 2,
                ),
            },
          ),

          // Status bar at top
          SafeArea(
            child: Container(
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
          ),

          // Bottom driver info panel
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildDriverPanel(),
          ),
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
                ),
                child: Center(
                  child: Text(icon, style: const TextStyle(fontSize: 28)),
                ),
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
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primary.withValues(alpha: 0.15),
                    AppTheme.primary.withValues(alpha: 0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.shield, size: 18, color: AppTheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        'Ride Verification Code',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: (_ride!['rideOtp'] as String).split('').map((d) {
                      return Container(
                        width: 48,
                        height: 56,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.primary),
                        ),
                        child: Center(
                          child: Text(
                            d,
                            style: GoogleFonts.inter(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.primary,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Share this code with your driver to start the ride',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppTheme.text3,
                    ),
                    textAlign: TextAlign.center,
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
                      final message = "SOS! I am in an emergency during my Mana Yatra ride. My location is: https://maps.google.com/?q=$lat,$lng . Driver info: ${_ride!['driverName']}, ${_ride!['vehicleNumber']}, Phone: ${_ride!['driverPhone']}";
                      final uri = Uri.parse('whatsapp://send?text=${Uri.encodeComponent(message)}');
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri);
                      } else {
                        if (mounted) {
                          CustomToast.show(
                            context: context,
                            message: 'WhatsApp is not installed on your device.',
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
