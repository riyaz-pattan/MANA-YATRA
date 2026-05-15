// lib/screens/home_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../config/constants.dart';
import '../providers/ride_provider.dart';
import '../services/google_maps_service.dart';
import '../utils/map_style.dart';
import '../utils/custom_toast.dart';
import 'package:uuid/uuid.dart';
import '../utils/marker_utils.dart';
import 'location_search_screen.dart';
import 'matching_screen.dart';
import 'active_ride_screen.dart';

class HomeScreen extends StatefulWidget {
  final void Function(bool isBooking)? onBookingStateChanged;
  const HomeScreen({super.key, this.onBookingStateChanged});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum RideFlowState { pickup, drop, route }

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  GoogleMapController? _mapController;
  
  // Custom Markers
  BitmapDescriptor? _pickupDot;
  BitmapDescriptor? _dropDot;
  BitmapDescriptor? _pickupLabel;
  BitmapDescriptor? _dropLabel;

  final _pickupSearchController = TextEditingController();
  final _dropSearchController = TextEditingController();
  final _bidController = TextEditingController();
  final _pickupFocusNode = FocusNode();
  final _dropFocusNode = FocusNode();
  LatLng? _currentPos;
  RideFlowState _flowState = RideFlowState.pickup;
  bool _calculatingRoute = false;
  Timer? _debounce;
  Set<Marker> _driverMarkers = {};
  Map<String, dynamic>? _savedHome;
  Map<String, dynamic>? _savedWork;

  StreamSubscription? _rideListener;
  bool _isLocationCentered = false;

  @override
  void initState() {
    super.initState();
    _requestPermissionsSequentially();
    _listenForActiveRide();
    _loadSavedPlaces();
    _pickupFocusNode.addListener(() { setState(() {}); });
    _dropFocusNode.addListener(() { setState(() {}); });
  }

  /// Request notification permission first, then location permission.
  /// Android cannot show two permission dialogs at the same time,
  /// so they must be chained sequentially.
  Future<void> _requestPermissionsSequentially() async {
    await _requestNotificationPermission();
    await _getCurrentLocation();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _pickupSearchController.dispose();
    _dropSearchController.dispose();
    _bidController.dispose();
    _pickupFocusNode.dispose();
    _dropFocusNode.dispose();
    _rideListener?.cancel();
    super.dispose();
  }

  void _listenForActiveRide() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _rideListener = FirebaseFirestore.instance
        .collection('rides')
        .where('riderId', isEqualTo: uid)
        .where('status', whereIn: ['searching', 'bidding', 'matched', 'started'])
        .snapshots()
        .listen((snap) {
      if (snap.docs.isNotEmpty) {
        if (!mounted) return;
        final ride = snap.docs.first;
        final data = ride.data();
        data['id'] = ride.id;
        final provider = context.read<RideProvider>();
        provider.setActiveRide(data);

        final status = data['status'];
        final createdAt = (data['createdAt'] as Timestamp?)?.toDate();

        if (status == 'searching' || status == 'bidding') {
          if (createdAt != null && DateTime.now().difference(createdAt).inMinutes >= AppConstants.rideExpiryMinutes) {
            // Force expire locally if the app was closed and server hasn't cleaned it up yet
            FirebaseFirestore.instance.collection('rides').doc(ride.id).update({'status': 'expired'});
            provider.setActiveRide(null);
            return;
          }
          
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => MatchingScreen(rideId: ride.id),
            ),
          );
        } else if (status == 'matched') {
          if (createdAt != null && DateTime.now().difference(createdAt).inMinutes >= 60) {
            // Force expire locally if it's been stuck in matched for over 60 minutes
            FirebaseFirestore.instance.collection('rides').doc(ride.id).update({
              'status': 'cancelled',
              'cancelReason': 'local_stale_cleanup'
            });
            provider.setActiveRide(null);
            return;
          }
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => ActiveRideScreen(rideId: ride.id),
            ),
          );
        } else if (status == 'started') {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => ActiveRideScreen(rideId: ride.id),
            ),
          );
        }
      } else {
        if (mounted) {
          context.read<RideProvider>().setActiveRide(null);
        }
      }
    });
  }

  Future<void> _requestNotificationPermission() async {
    try {
      await Permission.notification.request();
    } catch (e) {
      // Silently fail
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          CustomToast.show(context: context, message: 'Please enable location services', isError: true);
        }
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          CustomToast.show(context: context, message: 'Location permission denied. Please enable in settings.', isError: true);
        }
        return;
      }

      // Try getCurrentPosition with a longer timeout
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 30),
          ),
        );
      } catch (e) {
        // Fallback to last known position
        pos = await Geolocator.getLastKnownPosition();
      }

      if (pos == null) {
        if (mounted) {
          CustomToast.show(context: context, message: 'Could not get location. Please try again.', isError: true);
        }
        return;
      }

      final pickup = await GoogleMapsService.reverseGeocode(
        pos.latitude,
        pos.longitude,
      );
      if (mounted) {
        context.read<RideProvider>().setPickup(pickup);
        setState(() {
          _currentPos = LatLng(pos!.latitude, pos.longitude);
        });
        _mapController?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 15));
        _loadNearbyDrivers(pos.latitude, pos.longitude);
      }
    } catch (e) {
      if (mounted) setState(() {});
    }
  }

  Future<void> _loadNearbyDrivers(double lat, double lng) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('drivers')
          .where('isOnline', isEqualTo: true)
          .where('isApproved', isEqualTo: true)
          .where('isBlocked', isNotEqualTo: true)
          .get();

      final markers = <Marker>{};
      for (final doc in snap.docs) {
        final d = doc.data();
        if (d['lat'] != null && d['lng'] != null) {
          final dLat = (d['lat'] as num).toDouble();
          final dLng = (d['lng'] as num).toDouble();
          final dist = Geolocator.distanceBetween(
            lat, lng,
            dLat, dLng,
          );
          if (dist < 5000) {
            markers.add(Marker(
              markerId: MarkerId(doc.id),
              position: LatLng(dLat, dLng),
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
            ));
          }
        }
      }
      setState(() => _driverMarkers = markers);
    } catch (e) {
      // Silently fail
    }
  }

  Future<void> _loadSavedPlaces() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((snap) {
      final data = snap.data();
      if (mounted) {
        setState(() {
          _savedHome = data?['savedHome'] as Map<String, dynamic>?;
          _savedWork = data?['savedWork'] as Map<String, dynamic>?;
        });
      }
    });
  }



  void _toggleMapFocus() {
    final provider = context.read<RideProvider>();
    setState(() {
      _isLocationCentered = !_isLocationCentered;
    });

    if (_isLocationCentered) {
      // Focus on current location
      if (_currentPos != null) {
        _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(_currentPos!, 16),
        );
      } else {
        _getCurrentLocation();
      }
    } else {
      // Focus on full route
      _fitRoute();
    }
  }

  void _fitRoute() {
    final provider = context.read<RideProvider>();
    if (provider.pickup == null || provider.drop == null) return;

    final bounds = LatLngBounds(
      southwest: LatLng(
        provider.pickup!.lat < provider.drop!.lat ? provider.pickup!.lat : provider.drop!.lat,
        provider.pickup!.lng < provider.drop!.lng ? provider.pickup!.lng : provider.drop!.lng,
      ),
      northeast: LatLng(
        provider.pickup!.lat > provider.drop!.lat ? provider.pickup!.lat : provider.drop!.lat,
        provider.pickup!.lng > provider.drop!.lng ? provider.pickup!.lng : provider.drop!.lng,
      ),
    );

    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 100),
    );
  }

  Future<void> _confirmDrop() async {
    final provider = context.read<RideProvider>();
    if (provider.pickup == null || provider.drop == null) return;

    setState(() {
      _calculatingRoute = true;
      _flowState = RideFlowState.route;
      _isLocationCentered = false; // Default to showing route
    });

    final route = await GoogleMapsService.getRoute(
      provider.pickup!.lat,
      provider.pickup!.lng,
      provider.drop!.lat,
      provider.drop!.lng,
    );

    if (mounted) {
      provider.setRoute(route);
      
      // Generate custom markers
      _pickupDot = await MarkerGenerator.createDotMarker(color: Colors.green);
      _dropDot = await MarkerGenerator.createDotMarker(color: Colors.red);
      _pickupLabel = await MarkerGenerator.createLabelMarker(
        text: provider.pickup?.displayName ?? 'Pickup',
        isPickup: true,
      );
      _dropLabel = await MarkerGenerator.createLabelMarker(
        text: provider.drop?.displayName ?? 'Drop',
        isPickup: false,
      );

      setState(() => _calculatingRoute = false);

      if (route != null) {
        // Delay slightly to allow the bottom sheet to animate in and map padding to take effect
        Future.delayed(const Duration(milliseconds: 500), () {
          _fitRoute();
        });

        final estimate = AppConstants.estimatePrice(
          route.distanceKm,
          provider.vehicleType,
        );
        provider.setBidPrice(estimate.toInt());
        _bidController.text = estimate.toInt().toString();
      }
    }
  }

  Future<void> _requestRide() async {
    final provider = context.read<RideProvider>();
    if (provider.pickup == null ||
        provider.drop == null ||
        provider.route == null) {
      return;
    }

    final uid = FirebaseAuth.instance.currentUser!.uid;
    final phone = FirebaseAuth.instance.currentUser!.phoneNumber;

    // Client-generated doc ID — allows immediate navigation while
    // Firestore's offline persistence + Cloud Function handles delivery.
    final rideId = const Uuid().v4();

    await FirebaseFirestore.instance.collection('rides').doc(rideId).set({
      'riderId': uid,
      'riderPhone': phone,
      'pickup': provider.pickup!.toMap(),
      'drop': provider.drop!.toMap(),
      'vehicleType': provider.vehicleType,
      'riderBid': provider.bidPrice,
      'distanceKm': provider.route!.distanceKm,
      'durationMin': provider.route!.durationMin,
      'routeCoordinates': provider.route!.coordinates
          .map((c) => {'lat': c.latitude, 'lng': c.longitude})
          .toList(),
      'status': 'searching',
      'createdAt': FieldValue.serverTimestamp(),
    });

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => MatchingScreen(rideId: rideId),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RideProvider>();

    // Notify parent about booking state for bottom nav visibility
    final isBooking = _flowState == RideFlowState.route;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onBookingStateChanged?.call(isBooking);
    });

    // ── Route confirmation view: map + bottom panel ──
    if (_flowState == RideFlowState.route) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (_, __) => setState(() {
          _flowState = RideFlowState.pickup;
          provider.setDrop(null);
          provider.setRoute(null);
        }),
        child: Scaffold(
          body: Stack(
            children: [
              GoogleMap(
                style: lightMapStyle,
                onMapCreated: (c) => _mapController = c,
                initialCameraPosition: CameraPosition(
                  target: _currentPos ?? const LatLng(17.385, 78.487),
                  zoom: 14,
                ),
                // Add padding so the route fits ABOVE the bottom sheet
                padding: const EdgeInsets.only(bottom: 420, top: 80),
                polylines: provider.route != null
                    ? {
                        Polyline(
                          polylineId: const PolylineId('route'),
                          points: provider.route!.coordinates,
                          color: Colors.black.withValues(alpha: 0.8), // Sleek black route
                          width: 5,
                        )
                      }
                    : {},
                markers: {
                  if (provider.pickup != null) ...[
                    // Pickup Dot
                    Marker(
                      markerId: const MarkerId('pickup_dot'),
                      position: LatLng(provider.pickup!.lat, provider.pickup!.lng),
                      icon: _pickupDot ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
                      anchor: const Offset(0.5, 0.9), // Anchor at the bottom of the stem
                    ),
                    // Pickup Label
                    if (_pickupLabel != null)
                      Marker(
                        markerId: const MarkerId('pickup_label'),
                        position: LatLng(provider.pickup!.lat, provider.pickup!.lng),
                        icon: _pickupLabel!,
                        anchor: const Offset(0.88, 2.1), // Shift left to align pencil icon over pin
                        onTap: () => _openSearchScreen(focusDrop: false), // Focus pickup
                      ),
                  ],
                  if (provider.drop != null) ...[
                    // Drop Dot
                    Marker(
                      markerId: const MarkerId('drop_dot'),
                      position: LatLng(provider.drop!.lat, provider.drop!.lng),
                      icon: _dropDot ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                      anchor: const Offset(0.5, 0.9), // Anchor at the bottom of the stem
                    ),
                    // Drop Label
                    if (_dropLabel != null)
                      Marker(
                        markerId: const MarkerId('drop_label'),
                        position: LatLng(provider.drop!.lat, provider.drop!.lng),
                        icon: _dropLabel!,
                        anchor: const Offset(0.88, 2.1), // Shift left to align pencil icon over pin
                        onTap: () => _openSearchScreen(focusDrop: true), // Focus drop
                      ),
                  ],
                  ..._driverMarkers,
                },
                zoomControlsEnabled: false,
                myLocationButtonEnabled: false,
              ),
              // Back button
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, top: 12),
                  child: Builder(
                    builder: (ctx) => GestureDetector(
                      onTap: () => setState(() {
                        _flowState = RideFlowState.pickup;
                        provider.setDrop(null);
                        provider.setRoute(null);
                      }),
                      child: Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: AppTheme.bg,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8)],
                        ),
                        child: const Icon(Icons.arrow_back, color: AppTheme.text, size: 22),
                      ),
                    ),
                  ),
                ),
              ),
              // GPS Toggle Button
              Positioned(
                right: 16,
                bottom: 440, // Positioned above the bottom panel
                child: GestureDetector(
                  onTap: _toggleMapFocus,
                  child: Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: AppTheme.bg,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8)],
                      border: Border.all(
                        color: _isLocationCentered ? AppTheme.primary : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      _isLocationCentered ? Icons.my_location : Icons.route,
                      color: _isLocationCentered ? AppTheme.primary : AppTheme.text,
                      size: 24,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: _buildBottomPanel(provider),
              ),
            ],
          ),
        ),
      );
    }

    // ── Landing screen (default) ──
    return Stack(
      children: [
        // Full-screen background illustration
        Positioned.fill(
          child: Image.asset(
            'assets/images/landing_illustration.png',
            fit: BoxFit.cover,
          ),
        ),

        // "Where are you going?" card pinned at the TOP
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: _buildLandingCard(provider),
          ),
        ),
      ],
    );
  }

  /// Bottom card: shows only the "Where are you going?" search field.
  Widget _buildLandingCard(RideProvider provider) {

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: GestureDetector(
        onTap: _openSearchScreen,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.search_rounded, color: Colors.black54, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Where are you going?',
                  style: GoogleFonts.inter(
                    color: Colors.black87,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens the LocationSearchScreen and processes the result.
  Future<void> _openSearchScreen({bool? focusDrop}) async {
    // If location is not available, try to get it now
    if (_currentPos == null) {
      await _getCurrentLocation();
      // If still null after requesting, show toast
      if (_currentPos == null && mounted) {
        CustomToast.show(
          context: context,
          message: 'Location permission is required to book a ride. Please allow location access.',
          isError: true,
        );
        return;
      }
    }
    if (_currentPos == null) return;
    final provider = context.read<RideProvider>();

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationSearchScreen(
          currentPosition: _currentPos!,
          savedHome: _savedHome,
          savedWork: _savedWork,
          focusDrop: focusDrop,
        ),
      ),
    );

    if (result == true && mounted) {
      // Both pickup and drop are set in the provider by LocationSearchScreen.
      // If pickup was set to current location inside search screen, restore it.
      if (provider.pickup == null) {
        final loc = await GoogleMapsService.reverseGeocode(
          _currentPos!.latitude,
          _currentPos!.longitude,
        );
        provider.setPickup(loc);
      }
      // Calculate route and go to route flow.
      await _confirmDrop();
    }
  }





  Widget _buildBottomPanel(RideProvider provider) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).padding.bottom + 16),
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


          // Vehicle type selector
          Row(
            children: AppConstants.vehicleTypes.entries.map((entry) {
              final isSelected = provider.vehicleType == entry.key;
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    provider.setVehicleType(entry.key);
                    if (provider.route != null) {
                      final estimate = AppConstants.estimatePrice(
                        provider.route!.distanceKm,
                        entry.key,
                      );
                      provider.setBidPrice(estimate.toInt());
                      _bidController.text = estimate.toInt().toString();
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? Colors.black : AppTheme.border,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(entry.value.icon,
                                style: const TextStyle(fontSize: 32)),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: AppTheme.border, width: 0.5),
                                boxShadow: [
                                  BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.05),
                                      blurRadius: 2)
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.person,
                                      size: 10, color: Colors.black54),
                                  Text(
                                    ' ${entry.value.seats}',
                                    style: GoogleFonts.inter(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          entry.value.label,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight:
                                isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Route info + price
          if (provider.route != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.bg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _routeInfoChip(
                          Icons.straighten,
                          '${provider.route!.distanceKm} km',
                          AppTheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _routeInfoChip(
                          Icons.schedule,
                          '${provider.route!.durationMin} min',
                          AppTheme.warning,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1, color: AppTheme.border),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Your Bid Price',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.text,
                            ),
                          ),
                          Text(
                            'Enter your offer',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: AppTheme.text3,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        width: 100,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.surface2,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Row(
                          children: [
                            Text(
                              '₹',
                              style: GoogleFonts.inter(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.success,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: TextField(
                                controller: _bidController,
                                keyboardType: TextInputType.number,
                                style: GoogleFonts.inter(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.success,
                                ),
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                onChanged: (val) {
                                  final price = int.tryParse(val);
                                  if (price != null) {
                                    provider.setBidPrice(price);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Request ride button
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _requestRide,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  'Request Ride →',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ] else if (_calculatingRoute) ...[
            const Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(color: AppTheme.primary),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Search for a destination above',
                style: GoogleFonts.inter(
                  color: AppTheme.text3,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _routeInfoChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
