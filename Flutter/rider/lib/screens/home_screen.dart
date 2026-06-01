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
import '../utils/skeleton.dart';
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
  BitmapDescriptor? _autoIcon;
  BitmapDescriptor? _bikeIcon;

  final _pickupSearchController = TextEditingController();
  final _dropSearchController = TextEditingController();
  final _bidController = TextEditingController();
  final _pickupFocusNode = FocusNode();
  final _dropFocusNode = FocusNode();
  LatLng? _currentPos;
  RideFlowState _flowState = RideFlowState.pickup;
  bool _calculatingRoute = false;
  Timer? _debounce;
  Map<String, dynamic>? _savedHome;
  Map<String, dynamic>? _savedWork;
  List<Map<String, dynamic>>? _savedCustomPlaces;
  bool _bidBelowMinimum = false; // tracks min-fare warning state

  StreamSubscription? _rideListener;
  bool _isLocationCentered = false;
  bool _isFetchingLocation = false;

  @override
  void initState() {
    super.initState();
    _requestPermissionsSequentially();
    _listenForActiveRide();
    _loadSavedPlaces();
    _loadCustomIcons();
    _pickupFocusNode.addListener(() {
      setState(() {});
    });
    _dropFocusNode.addListener(() {
      setState(() {});
    });
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

  Future<void> _loadCustomIcons() async {
    try {
      _autoIcon = await BitmapDescriptor.asset(
        const ImageConfiguration(size: Size(48, 48)),
        'assets/images/map_icons/auto.png',
      );
      _bikeIcon = await BitmapDescriptor.asset(
        const ImageConfiguration(size: Size(48, 48)),
        'assets/images/map_icons/bike.png',
      );
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('[HomeScreen] Failed to load custom vehicle icons: $e');
    }
  }

  void _listenForActiveRide() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _rideListener = FirebaseFirestore.instance
        .collection('rides')
        .where('riderId', isEqualTo: uid)
        .where(
          'status',
          whereIn: ['searching', 'bidding', 'matched', 'started'],
        )
        .snapshots()
        .listen(
          (snap) {
            if (snap.docs.isNotEmpty) {
              if (!mounted) return;
              try {
                final ride = snap.docs.first;
                final data = Map<String, dynamic>.from(ride.data() as Map);
                data['id'] = ride.id;
                final provider = context.read<RideProvider>();
                provider.setActiveRide(data);

                final status = data['status'];
                final createdAt = (data['createdAt'] as Timestamp?)?.toDate();

                if (status == 'searching' || status == 'bidding') {
                  if (createdAt != null &&
                      DateTime.now().difference(createdAt).inMinutes >=
                          AppConstants.rideExpiryMinutes) {
                    // Force expire locally if the app was closed and server hasn't cleaned it up yet
                    FirebaseFirestore.instance
                        .collection('rides')
                        .doc(ride.id)
                        .update({'status': 'expired'});
                    provider.setActiveRide(null);
                    return;
                  }

                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => MatchingScreen(rideId: ride.id),
                    ),
                  );
                } else if (status == 'matched') {
                  if (createdAt != null &&
                      DateTime.now().difference(createdAt).inMinutes >= 60) {
                    // Force expire locally if it's been stuck in matched for over 60 minutes
                    FirebaseFirestore.instance
                        .collection('rides')
                        .doc(ride.id)
                        .update({
                          'status': 'cancelled',
                          'cancelReason': 'local_stale_cleanup',
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
              } catch (e) {
                debugPrint('Error in HomeScreen _listenForActiveRide: $e');
              }
            } else {
              if (mounted) {
                context.read<RideProvider>().setActiveRide(null);
              }
            }
          },
          onError: (error) {
            debugPrint('Firestore stream error in HomeScreen: $error');
          },
        );
  }

  Future<void> _requestNotificationPermission() async {
    try {
      await Permission.notification.request();
    } catch (e) {
      // Silently fail
    }
  }

  /// Shows a dialog prompting the user to enable device location (GPS).
  /// Returns true if the user enabled location after visiting settings.
  Future<bool> _showEnableLocationDialog() async {
    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: AppTheme.surface,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.location_off_rounded,
                  color: AppTheme.warning,
                  size: 44,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Enable Device Location',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.text,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                'Your device location (GPS) is turned off. Please enable it to use Gaman.',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: AppTheme.text2,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await Geolocator.openLocationSettings();
                    // After returning from settings, check again
                    final enabled = await Geolocator.isLocationServiceEnabled();
                    if (ctx.mounted) Navigator.pop(ctx, enabled);
                  },
                  icon: const Icon(Icons.settings_rounded, size: 18),
                  label: Text(
                    'Enable Location',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.inter(
                    color: AppTheme.text3,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return result ?? false;
  }

  /// Shows a dialog prompting the user to grant location permission in app settings.
  /// Used when permission is permanently denied (deniedForever).
  Future<bool> _showOpenAppSettingsDialog() async {
    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: AppTheme.surface,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppTheme.danger.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.location_disabled_rounded,
                  color: AppTheme.danger,
                  size: 44,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Location Permission Required',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.text,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                'Location permission has been permanently denied. Please enable it from app settings to continue.',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: AppTheme.text2,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await Geolocator.openAppSettings();
                    // After returning from settings, check again
                    final perm = await Geolocator.checkPermission();
                    final granted =
                        perm == LocationPermission.whileInUse ||
                        perm == LocationPermission.always;
                    if (ctx.mounted) Navigator.pop(ctx, granted);
                  },
                  icon: const Icon(Icons.settings_rounded, size: 18),
                  label: Text(
                    'Open Settings',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.inter(
                    color: AppTheme.text3,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return result ?? false;
  }

  Future<void> _getCurrentLocation() async {
    try {
      // Step 1: Check if device GPS/location service is enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // Show dialog prompting user to enable device location
        final enabled = await _showEnableLocationDialog();
        if (!enabled) {
          if (mounted) {
            CustomToast.show(
              context: context,
              message: 'Device location is required to continue.',
              isError: true,
            );
          }
          return;
        }
        // Re-verify after returning from settings
        serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          if (mounted) {
            CustomToast.show(
              context: context,
              message: 'Device location is still off. Please enable GPS.',
              isError: true,
            );
          }
          return;
        }
      }

      // Step 2: Check app-level location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        // Show dialog to open app settings
        final granted = await _showOpenAppSettingsDialog();
        if (!granted) {
          return;
        }
        // Re-check permission after returning from settings
        permission = await Geolocator.checkPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          CustomToast.show(
            context: context,
            message: 'Location permission denied. Please enable in settings.',
            isError: true,
          );
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
          CustomToast.show(
            context: context,
            message: 'Could not get location. Please try again.',
            isError: true,
          );
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
        _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 15),
        );
      }
    } catch (e) {
      if (mounted) setState(() {});
    }
  }

  Set<Marker> _dynamicDriverMarkers(RideProvider provider) {
    final markers = <Marker>{};
    for (var d in provider.nearbyDrivers) {
      if (d['vehicleType'] == provider.vehicleType) {
        markers.add(
          Marker(
            markerId: MarkerId(d['id']),
            position: LatLng(d['lat'], d['lng']),
            icon: d['vehicleType'] == 'bike'
                ? (_bikeIcon ??
                      BitmapDescriptor.defaultMarkerWithHue(
                        BitmapDescriptor.hueCyan,
                      ))
                : (_autoIcon ??
                      BitmapDescriptor.defaultMarkerWithHue(
                        BitmapDescriptor.hueCyan,
                      )),
            anchor: const Offset(0.5, 0.5),
            rotation: d['heading'] ?? 0.0,
          ),
        );
      }
    }
    return markers;
  }

  Future<void> _loadSavedPlaces() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    FirebaseFirestore.instance.collection('users').doc(uid).snapshots().listen((
      snap,
    ) {
      final data = snap.data();
      if (mounted) {
        setState(() {
          _savedHome = data?['savedHome'] as Map<String, dynamic>?;
          _savedWork = data?['savedWork'] as Map<String, dynamic>?;
          _savedCustomPlaces = (data?['savedCustomPlaces'] as List<dynamic>?)
              ?.map((e) => e as Map<String, dynamic>)
              .toList();
        });
      }
    });
  }

  void _toggleMapFocus() {
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
        provider.pickup!.lat < provider.drop!.lat
            ? provider.pickup!.lat
            : provider.drop!.lat,
        provider.pickup!.lng < provider.drop!.lng
            ? provider.pickup!.lng
            : provider.drop!.lng,
      ),
      northeast: LatLng(
        provider.pickup!.lat > provider.drop!.lat
            ? provider.pickup!.lat
            : provider.drop!.lat,
        provider.pickup!.lng > provider.drop!.lng
            ? provider.pickup!.lng
            : provider.drop!.lng,
      ),
    );

    _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100));
  }

  /// Shows a beautiful, informative error dialog when pickup/drop locations are invalid.
  void _showInvalidRouteDialog({
    required String title,
    required String message,
    required String hint,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: AppTheme.surface,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppTheme.danger.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.location_off_rounded,
                  color: AppTheme.danger,
                  size: 44,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.text,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                message,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: AppTheme.text2,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              // Hint pill
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.warning.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.lightbulb_outline_rounded,
                      color: AppTheme.warning,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        hint,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    // Reset to pickup state so rider can re-enter locations
                    setState(() {
                      _flowState = RideFlowState.pickup;
                      _calculatingRoute = false;
                    });
                    final p = context.read<RideProvider>();
                    p.setDrop(null);
                    p.setRoute(null);
                    // Reopen search screen to fix locations
                    _openSearchScreen();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Fix Locations',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: Colors.white,
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

  Future<void> _confirmDrop() async {
    final provider = context.read<RideProvider>();
    if (provider.pickup == null || provider.drop == null) return;

    // ── Layer 0: same-location guard ──
    final straightLineM = Geolocator.distanceBetween(
      provider.pickup!.lat,
      provider.pickup!.lng,
      provider.drop!.lat,
      provider.drop!.lng,
    );

    if (straightLineM < 50) {
      _showInvalidRouteDialog(
        title: 'Same Location Selected',
        message:
            'Your pickup and drop locations are the same place (less than 50 m apart).\n\nPlease choose a different drop location.',
        hint: 'Tip: Drop must be at least a few streets away from pickup.',
      );
      return;
    }

    // ── Layer 1: straight-line distance guard ──
    final straightLineKm = straightLineM / 1000.0;

    if (straightLineKm > 300) {
      // Show dialog immediately — no spinner, no API call
      _showInvalidRouteDialog(
        title: 'Locations Too Far Apart',
        message:
            'Your pickup and drop locations are ${straightLineKm.toStringAsFixed(0)} km apart in a straight line.\n\nGaman operates for local rides. Please set a nearby drop location.',
        hint: 'Tip: Both locations should be in the same city or region.',
      );
      return;
    }

    setState(() {
      _calculatingRoute = true;
      _flowState = RideFlowState.route;
      _isLocationCentered = false;
    });

    final route = await GoogleMapsService.getRoute(
      provider.pickup!.lat,
      provider.pickup!.lng,
      provider.drop!.lat,
      provider.drop!.lng,
    );

    if (!mounted) return;

    // ── Layer 2: route API failure guard ──
    // getRoute returns null when the API cannot find a driveable road path
    // (e.g. locations in different countries, separated by ocean, etc.)
    if (route == null) {
      _showInvalidRouteDialog(
        title: 'No Driveable Route Found',
        message:
            'We could not find a road route between your pickup and drop locations.\n\nThis usually happens when the locations are in different regions, countries, or separated by water.',
        hint:
            'Tip: Make sure both points are reachable by road in the same area.',
      );
      return;
    }

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

    // Delay slightly to allow bottom sheet to animate in before camera moves
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _fitRoute();
    });

    final estimate = AppConstants.estimatePrice(
      route.distanceKm,
      provider.vehicleType,
    );
    provider.setBidPrice(estimate.toInt());
    _bidController.text = estimate.toInt().toString();
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
      'paymentMethod': provider.paymentMethod,
      'routeCoordinates': provider.route!.coordinates
          .map((c) => {'lat': c.latitude, 'lng': c.longitude})
          .toList(),
      'status': 'searching',
      'createdAt': FieldValue.serverTimestamp(),
    });

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => MatchingScreen(rideId: rideId)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RideProvider>();

    if (provider.shouldCalculateRoute) {
      provider.clearRouteCalculationFlag();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _confirmDrop();
        }
      });
    }

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
                padding: const EdgeInsets.only(bottom: 410, top: 80),
                polylines: provider.route != null
                    ? {
                        Polyline(
                          polylineId: const PolylineId('route'),
                          points: provider.route!.coordinates,
                          color: Colors.black.withValues(
                            alpha: 0.8,
                          ), // Sleek black route
                          width: 3,
                        ),
                      }
                    : {},
                markers: {
                  if (provider.pickup != null) ...[
                    // Pickup Dot
                    Marker(
                      markerId: const MarkerId('pickup_dot'),
                      position: LatLng(
                        provider.pickup!.lat,
                        provider.pickup!.lng,
                      ),
                      icon:
                          _pickupDot ??
                          BitmapDescriptor.defaultMarkerWithHue(
                            BitmapDescriptor.hueGreen,
                          ),
                      anchor: const Offset(
                        0.5,
                        0.9,
                      ), // Anchor at the bottom of the stem
                    ),
                    // Pickup Label
                    if (_pickupLabel != null)
                      Marker(
                        markerId: const MarkerId('pickup_label'),
                        position: LatLng(
                          provider.pickup!.lat,
                          provider.pickup!.lng,
                        ),
                        icon: _pickupLabel!,
                        anchor: const Offset(
                          0.78,
                          2.0,
                        ), // Shift higher to float above the pin
                        onTap: () =>
                            _openSearchScreen(focusDrop: false), // Focus pickup
                      ),
                  ],
                  if (provider.drop != null) ...[
                    // Drop Dot
                    Marker(
                      markerId: const MarkerId('drop_dot'),
                      position: LatLng(provider.drop!.lat, provider.drop!.lng),
                      icon:
                          _dropDot ??
                          BitmapDescriptor.defaultMarkerWithHue(
                            BitmapDescriptor.hueRed,
                          ),
                      anchor: const Offset(
                        0.5,
                        0.9,
                      ), // Anchor at the bottom of the stem
                    ),
                    // Drop Label
                    if (_dropLabel != null)
                      Marker(
                        markerId: const MarkerId('drop_label'),
                        position: LatLng(
                          provider.drop!.lat,
                          provider.drop!.lng,
                        ),
                        icon: _dropLabel!,
                        anchor: const Offset(
                          0.78,
                          2.0,
                        ), // Shift higher to float above the pin
                        onTap: () =>
                            _openSearchScreen(focusDrop: true), // Focus drop
                      ),
                  ],
                  ..._dynamicDriverMarkers(provider),
                },
                zoomControlsEnabled: true,
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
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppTheme.bg,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.arrow_back,
                          color: AppTheme.text,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // GPS Toggle Button
              Positioned(
                right: 16,
                bottom: 520, // Positioned above the zoom controls (+/-)
                child: GestureDetector(
                  onTap: _toggleMapFocus,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppTheme.bg,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 8,
                        ),
                      ],
                      border: Border.all(
                        color: _isLocationCentered
                            ? AppTheme.primary
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      _isLocationCentered ? Icons.my_location : Icons.route,
                      color: _isLocationCentered
                          ? AppTheme.primary
                          : AppTheme.text,
                      size: 24,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildBottomPanel(provider),
              ),
              // Floating route stats pill removed.
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
          child: SafeArea(bottom: false, child: _buildLandingCard(provider)),
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
        onTap: _isFetchingLocation ? null : _openSearchScreen,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              if (_isFetchingLocation)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.black54,
                  ),
                )
              else
                const Icon(
                  Icons.search_rounded,
                  color: Colors.black54,
                  size: 22,
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _isFetchingLocation
                      ? 'Fetching location...'
                      : 'Where are you going?',
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
      setState(() => _isFetchingLocation = true);
      await _getCurrentLocation();
      setState(() => _isFetchingLocation = false);

      // If still null after requesting, show toast
      if (_currentPos == null && mounted) {
        CustomToast.show(
          context: context,
          message:
              'Location permission is required to book a ride. Please allow location access.',
          isError: true,
        );
        return;
      }
    }
    if (_currentPos == null) return;
    if (!mounted) return;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationSearchScreen(
          currentPosition: _currentPos!,
          savedHome: _savedHome,
          savedWork: _savedWork,
          savedCustomPlaces: _savedCustomPlaces,
          focusDrop: focusDrop,
        ),
      ),
    );

    if (!mounted) return;
    final provider = context.read<RideProvider>();

    if (result == true) {
      // Both pickup and drop are set in the provider by LocationSearchScreen.
      // If pickup was set to current location inside search screen, restore it.
      if (provider.pickup == null) {
        final loc = await GoogleMapsService.reverseGeocode(
          _currentPos!.latitude,
          _currentPos!.longitude,
        );
        if (!context.mounted) return;
        provider.setPickup(loc);
      }
      // Calculate route and go to route flow.
      await _confirmDrop();
    }
  }

  Widget _buildBottomPanel(RideProvider provider) {
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (provider.route != null) ...[
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Vertical vehicle list (fixed, non-scrollable)
            Column(
              children: AppConstants.vehicleTypes.entries.map((entry) {
                final isSelected = provider.vehicleType == entry.key;
                final (low, high) = AppConstants.estimatePriceRange(
                  provider.route!.distanceKm,
                  entry.key,
                );

                // Dynamic ETA Calculation
                final driversOfType = provider.nearbyDrivers
                    .where((d) => d['vehicleType'] == entry.key)
                    .toList();

                String etaString = '';
                if (driversOfType.isNotEmpty) {
                  driversOfType.sort(
                    (a, b) => (a['distance'] as double).compareTo(
                      b['distance'] as double,
                    ),
                  );
                  final closestDistanceMeters =
                      driversOfType.first['distance'] as double;
                  // Assume 20km/h = ~333 meters per minute
                  final etaMinutes = (closestDistanceMeters / 333).ceil();
                  final displayMinutes = etaMinutes < 1 ? 1 : etaMinutes;
                  etaString = '$displayMinutes mins away';
                }

                return GestureDetector(
                  onTap: () {
                    provider.setVehicleType(entry.key);
                    final estimate = AppConstants.estimatePrice(
                      provider.route!.distanceKm,
                      entry.key,
                    );
                    provider.setBidPrice(estimate.toInt());
                    _bidController.text = estimate.toInt().toString();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? AppTheme.primary : AppTheme.border,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        // Icon
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: AppTheme.bg,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            entry.value.icon,
                            style: const TextStyle(fontSize: 28),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Details
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    entry.value.label,
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.text,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    Icons.person,
                                    size: 16,
                                    color: AppTheme.text2,
                                  ),
                                  Text(
                                    ' ${entry.value.seats}',
                                    style: GoogleFonts.inter(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.text2,
                                    ),
                                  ),
                                ],
                              ),
                              if (etaString.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  etaString,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: AppTheme.text2,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 2),
                              Text(
                                '${provider.route!.distanceKm} km',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: AppTheme.text3,
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
                              '₹$low – ₹$high',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.text,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Estimated',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: AppTheme.text3,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),

            if (provider.vehicleType.isNotEmpty) ...[
              const SizedBox(height: 12),
              // Compact Row: Payment Method & Bid Price
              Row(
                children: [
                  // Payment Method Selector
                  Expanded(
                    flex: 1,
                    child: GestureDetector(
                      onTap: () => _showPaymentBottomSheet(provider),
                      child: Container(
                        height: 52,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: AppTheme.border),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              provider.paymentMethod == 'Cash'
                                  ? Icons.money
                                  : Icons.qr_code,
                              color: AppTheme.primary,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                provider.paymentMethod,
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.text,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right,
                              size: 16,
                              color: AppTheme.text3,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Bid Input
                  Expanded(
                    flex: 1,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          height: 52,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.primary,
                              width: 2,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '₹',
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.primary,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: TextField(
                                  controller: _bidController,
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.primary,
                                  ),
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    filled: false,
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                  onChanged: (val) {
                                    final price = int.tryParse(val);
                                    if (price != null) {
                                      provider.setBidPrice(price);
                                      final min =
                                          AppConstants.minFare[provider
                                              .vehicleType] ??
                                          20;
                                      setState(
                                        () => _bidBelowMinimum = price < min,
                                      );
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Tooltip hint pointing to the bid price
                        Positioned(
                          top: -38,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 1.0, end: 0.0),
                              duration: const Duration(milliseconds: 5000),
                              curve: const Interval(0.8, 1.0),
                              builder: (context, opacity, child) {
                                return Opacity(opacity: opacity, child: child);
                              },
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.info,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'You can change this price!',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  // Tail of the speech bubble
                                  Transform.translate(
                                    offset: const Offset(0, -6),
                                    child: const Icon(
                                      Icons.arrow_drop_down,
                                      color: AppTheme.info,
                                      size: 20,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              if (_bidBelowMinimum) ...[
                const SizedBox(height: 8),
                Text(
                  'Very low bid — drivers may not accept this offer.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.danger,
                  ),
                  textAlign: TextAlign.right,
                ),
              ],

              const SizedBox(height: 12),
              // Request Button
              SizedBox(
                height: 54,
                child: ElevatedButton(
                  onPressed: _requestRide,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    'Book ${AppConstants.vehicleTypes[provider.vehicleType]?.label ?? ''}',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ] else ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.touch_app,
                      size: 16,
                      color: AppTheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Select a vehicle type to continue',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ] else if (_calculatingRoute) ...[
            const Padding(
              padding: EdgeInsets.all(16),
              child: RoutePanelSkeleton(),
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Search for a destination above',
                style: GoogleFonts.inter(color: AppTheme.text3, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showPaymentBottomSheet(RideProvider provider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Select Payment Method',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.text,
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.money, color: AppTheme.primary),
                title: Text(
                  'Cash',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
                trailing: provider.paymentMethod == 'Cash'
                    ? const Icon(Icons.check_circle, color: AppTheme.primary)
                    : null,
                onTap: () {
                  provider.setPaymentMethod('Cash');
                  Navigator.pop(ctx);
                },
              ),
              const Divider(height: 1, color: AppTheme.border),
              ListTile(
                leading: const Icon(Icons.qr_code, color: AppTheme.primary),
                title: Text(
                  'UPI',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
                trailing: provider.paymentMethod == 'UPI'
                    ? const Icon(Icons.check_circle, color: AppTheme.primary)
                    : null,
                onTap: () {
                  provider.setPaymentMethod('UPI');
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
