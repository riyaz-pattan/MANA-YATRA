// lib/screens/dashboard_screen.dart
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../config/theme.dart';
import '../config/constants.dart';
import '../utils/map_style.dart';
// Removed invalid imports
import '../services/region_service.dart';
import '../providers/driver_provider.dart';
import '../services/ride_signal_service.dart';
import 'active_ride_screen.dart';
import 'ride_earnings_history_screen.dart';
import 'subscription_screen.dart';
import 'profile_screen.dart';
import 'support_screen.dart';
import 'settings_screen.dart';
import 'referral_screen.dart';
import '../main.dart';
import '../utils/custom_toast.dart';
import '../services/sync_engine.dart';
import '../models/queue_item.dart';
import '../widgets/moving_vehicle_loader.dart';
import 'package:uuid/uuid.dart';
import '../widgets/premium_retry_button.dart';
import '../utils/marker_animator.dart';
import '../utils/map_utils.dart';
import '../widgets/promo_banner_dialog.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  GoogleMapController? _mapController;
  BitmapDescriptor? _autoIcon;
  BitmapDescriptor? _bikeIcon;

  List<Map<String, dynamic>> _nearbyRides = [];
  // ignore: unused_field
  bool _loadingRides = false;
  bool _bidding = false;
  StreamSubscription? _rideListener;
  RideSignalService? _signalService;
  StreamSubscription? _signalSub;
  Set<String> _declinedRides = {};
  final Map<String, int> _biddedRides = {};
  final Map<String, StreamSubscription> _declineSubs = {};

  // Snap carousel
  late final PageController _ridePageController;
  int _focusedRideIndex = 0;
  // Cache of fare bubble markers keyed by "<rideId>_<isActive>"
  final Map<String, BitmapDescriptor> _fareBubbleCache = {};

  // Dotted curve line from driver to focused pickup
  Set<Polyline> _routeCurvePolylines = {};
  Marker? _distanceLabelMarker;

  bool _locating = false;
  bool _locationGranted = false;

  // Auto-offline: track last user activity to disconnect idle drivers
  DateTime _lastActiveTime = DateTime.now();
  Timer? _autoOfflineTimer;

  late final MarkerAnimator _driverAnimator;
  DriverProvider? _driverProvider;

  @override
  void initState() {
    super.initState();
    _driverAnimator = MarkerAnimator(vsync: this);
    WidgetsBinding.instance.addObserver(this);
    _ridePageController = PageController(viewportFraction: 0.84);
    _requestPermissionsSequentially();
    _listenForActiveRide();
    _loadCustomMarkers();
    _loadDeclinedRides();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _driverProvider = context.read<DriverProvider>();
      _driverProvider?.addListener(_onDriverLocationChanged);
      // If driver is already online (e.g. returning from completed ride),
      // restart the signal service so ride requests are visible immediately.
      _resumeIfOnline();
    });
  }

  Future<void> _loadDeclinedRides() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('declinedRides_$uid') ?? [];
      if (mounted) {
        setState(() {
          _declinedRides = list.toSet();
          // Prevent race condition: filter any rides that loaded before SharedPreferences finished
          _nearbyRides.removeWhere((r) => _declinedRides.contains(r['id']));
        });
      }
    } catch (_) {}
  }

  Future<void> _saveDeclinedRides() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      // Keep only the last 30 declined rides to prevent infinite growth
      final listToSave = _declinedRides.toList();
      if (listToSave.length > 30) {
        listToSave.removeRange(0, listToSave.length - 30);
      }
      await prefs.setStringList('declinedRides_$uid', listToSave);
    } catch (_) {}
  }

  void _onDriverLocationChanged() {
    if (_driverProvider?.lat != null && _driverProvider?.lng != null) {
      final newPos = LatLng(_driverProvider!.lat!, _driverProvider!.lng!);
      _driverAnimator.animate(
        newPos: newPos,
        newHeading: _driverProvider?.heading ?? 0.0,
        onUpdate: () {
          if (mounted) setState(() {});
        },
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // App came back to foreground — check if we've been idle too long
      final provider = context.read<DriverProvider>();
      if (provider.isOnline) {
        final elapsed = DateTime.now().difference(_lastActiveTime);
        if (elapsed.inMinutes >= AppConstants.autoOfflineMinutes) {
          _autoOffline();
          return;
        }
      }
      // Reset activity timer since user is actively using the app
      _lastActiveTime = DateTime.now();

      // Check if a ride was assigned while backgrounded (state updated via stream but UI failed to navigate)
      if (provider.persistedRideId != null) {
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => ActiveRideScreen(rideId: provider.persistedRideId!)),
          (route) => false,
        );
      }
    } else if (state == AppLifecycleState.paused) {
      // App went to background — _lastActiveTime stays at the last foreground time
      // so we can measure how long the app was backgrounded
    }
  }

  /// Request notification permission on startup.
  /// Location permission is deferred until the driver toggles online,
  /// so we don't fetch location or show the "getting your location" spinner
  /// while the driver is offline.
  Future<void> _requestPermissionsSequentially() async {
    await _checkNotificationPermission();
  }

  Future<void> _loadCustomMarkers() async {
    const config = ImageConfiguration(size: Size(48, 48));
    _autoIcon = await BitmapDescriptor.asset(
      config,
      'assets/images/map_icons/auto.png',
    );
    _bikeIcon = await BitmapDescriptor.asset(
      config,
      'assets/images/map_icons/bike.png',
    );

    if (mounted) setState(() {});
  }

  BitmapDescriptor _getVehicleIcon(String? vehicleType) {
    if (vehicleType == 'bike' && _bikeIcon != null) return _bikeIcon!;

    if (vehicleType == 'auto' && _autoIcon != null) return _autoIcon!;
    return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
  }

  Future<void> _checkNotificationPermission() async {
    final status = await Permission.notification.status;
    if (status.isDenied) {
      await Permission.notification.request();
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
        backgroundColor: AppTheme.bg,
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
                'Your device location (GPS) is turned off. Please enable it to use Gaman Driver.',
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
        backgroundColor: AppTheme.bg,
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
    if (mounted) setState(() => _locating = true);
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
            setState(() {
              _locating = false;
              _locationGranted = false;
            });
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
            setState(() {
              _locating = false;
              _locationGranted = false;
            });
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
          if (mounted) {
            setState(() {
              _locating = false;
              _locationGranted = false;
            });
          }
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
            message:
                'Location permission is required. Please enable in settings.',
            isError: true,
          );
          setState(() {
            _locating = false;
            _locationGranted = false;
          });
        }
        return;
      }
      _locationGranted = true;

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
          setState(() => _locating = false);
        }
        return;
      }

      if (mounted) {
        final provider = context.read<DriverProvider>();
        provider.updateLocation(pos.latitude, pos.longitude, pos.heading);
        _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 15),
        );
        setState(() => _locating = false);
        _checkPromoCampaign(pos.latitude, pos.longitude);

        // If online, start RTDB signal listener
        if (provider.isOnline) {
          _startSignalService(provider);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _checkPromoCampaign(double currentLat, double currentLng) async {
    try {
      final remoteConfig = FirebaseRemoteConfig.instance;
      final promoJson = remoteConfig.getString('promotional_banner');

      if (promoJson.isEmpty) return;

      final Map<String, dynamic> promoData = jsonDecode(promoJson);

      final bool isActive = promoData['isActive'] ?? false;
      if (!isActive) return;

      final targetLat = (promoData['targetLat'] as num?)?.toDouble() ?? 0.0;
      final targetLng = (promoData['targetLng'] as num?)?.toDouble() ?? 0.0;
      final radiusKm = (promoData['radiusKm'] as num?)?.toDouble() ?? 0.0;

      if (targetLat != 0.0 && targetLng != 0.0 && radiusKm > 0) {
        final distanceInMeters = Geolocator.distanceBetween(
          currentLat,
          currentLng,
          targetLat,
          targetLng,
        );

        if (distanceInMeters > (radiusKm * 1000)) {
          return;
        }
      }

      if (mounted) {
        PromoBannerDialog.showIfEligible(context, promoData);
      }
    } catch (e) {
      debugPrint('Error checking promo campaign: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoOfflineTimer?.cancel();
    _ridePageController.dispose();
    _rideListener?.cancel();
    _signalSub?.cancel();
    _signalService?.dispose();
    for (final sub in _declineSubs.values) {
      sub.cancel();
    }
    _declineSubs.clear();
    _driverAnimator.dispose();
    _driverProvider?.removeListener(_onDriverLocationChanged);
    super.dispose();
  }

  /// Rebuilds fare bubble markers for all visible rides.
  /// Called whenever [_nearbyRides] or [_focusedRideIndex] changes.
  Future<void> _rebuildFareBubbles() async {
    final Map<String, BitmapDescriptor> newCache = {};
    for (int i = 0; i < _nearbyRides.length; i++) {
      final ride = _nearbyRides[i];
      final rideId = ride['id'] as String;
      final fare = (ride['riderBid'] ?? ride['offeredPrice'] ?? 80) as num;
      final isActive = i == _focusedRideIndex;
      final key = '${rideId}_$isActive';
      if (_fareBubbleCache.containsKey(key)) {
        newCache[key] = _fareBubbleCache[key]!;
      } else {
        newCache[key] = await MapUtils.createFareBubbleMarker(
          index: i + 1,
          fare: fare.toInt(),
          isActive: isActive,
        );
      }
    }
    _fareBubbleCache
      ..clear()
      ..addAll(newCache);
    if (mounted) setState(() {});
  }

  void _listenForActiveRide() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _rideListener = FirebaseFirestore.instance
        .collection('rides')
        .where('driverId', isEqualTo: uid)
        .where('status', whereIn: ['matched', 'started'])
        .snapshots()
        .listen(
          (snap) {
            if (snap.docs.isNotEmpty) {
              if (!mounted) return;
              try {
                final ride = snap.docs.first;
                final data = Map<String, dynamic>.from(ride.data() as Map);
                data['id'] = ride.id;

                context.read<DriverProvider>().setActiveRide(data);
                Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (_) => ActiveRideScreen(rideId: ride.id),
                  ),
                  (route) => false,
                );
              } catch (e) {
                debugPrint('Error in DashboardScreen _listenForActiveRide: $e');
              }
            }
          },
          onError: (error) {
            debugPrint('Firestore stream error in DashboardScreen: $error');
          },
        );
  }

  /// Shows a beautiful floating dialog when the driver's subscription is expired
  /// and they attempt to go online.
  void _showSubscriptionExpiredDialog() {
    final provider = context.read<DriverProvider>();
    final bool hasTrial = provider.profile?['hasFreeTrialUsed'] != true;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        backgroundColor: AppTheme.bg,
        child: Padding(
          padding: const EdgeInsets.all(0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Gradient header with icon
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 32),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: hasTrial
                        ? [const Color(0xFF6C63FF), const Color(0xFF9B59B6)]
                        : [const Color(0xFFFF6B6B), const Color(0xFFFF8E53)],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        hasTrial ? Icons.star_rounded : Icons.timer_off_rounded,
                        size: 48,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      hasTrial ? 'Start Free Trial' : 'Subscription Expired',
                      style: GoogleFonts.inter(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              // Body content
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                child: Column(
                  children: [
                    Text(
                      hasTrial
                          ? 'Start your 7-day free trial to go online and receive rides.'
                          : 'Activate your subscription to go online and receive rides.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        color: AppTheme.text2,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Per-day starting price hint
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        hasTrial
                            ? '7 Days of full access for free'
                            : 'Plans starting at just ₹18/day',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Renew Plan button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SubscriptionScreen(),
                            ),
                          );
                        },
                        icon: Icon(
                          hasTrial ? Icons.star : Icons.rocket_launch_rounded,
                          size: 20,
                        ),
                        label: Text(
                          hasTrial ? 'Get Free Trial' : 'Renew Plan',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(
                        'Maybe Later',
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
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleOnline() async {
    final provider = context.read<DriverProvider>();
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final goingOnline = !provider.isOnline;

    // If going online, check location permission first
    if (goingOnline) {
      if (!provider.isSubscriptionActive) {
        if (mounted) {
          _showSubscriptionExpiredDialog();
        }
        return;
      }

      if (!_locationGranted) {
        // Try to get location permission
        await _getCurrentLocation();
        if (!_locationGranted) {
          if (mounted) {
            CustomToast.show(
              context: context,
              message:
                  'Location permission is required to go online. Please allow location access.',
              isError: true,
            );
          }
          return;
        }
      }

      // Check Serviceable Region
      if (provider.lat != null && provider.lng != null) {
        final regionService = RegionService();
        await regionService.initialize();
        if (!regionService.isLocationServiceable(provider.lat!, provider.lng!)) {
          _showOutOfRegionBottomSheet(provider.lat!, provider.lng!);
          return; // Block going online
        }
      }
    }

    try {
      final newDriverState = goingOnline ? 'ONLINE_IDLE' : 'OFFLINE';

      await FirebaseFirestore.instance.collection('drivers').doc(uid).update({
        'driverState': newDriverState,
        'isOnline': goingOnline, // Keep for backward compat during migration
      });

      provider.setOnline(goingOnline);

      if (goingOnline) {
        _lastActiveTime = DateTime.now();
        _startAutoOfflineTimer();
        _startSignalService(provider);
      } else {
        _stopAutoOfflineTimer();
        _signalSub?.cancel();
        _signalService?.dispose();
        _signalService = null;
        _clearRouteCurve();
        setState(() => _nearbyRides = []);
      }
    } catch (e) {
      debugPrint('Error toggling online status: $e');
      if (mounted) {
        CustomToast.show(
          context: context,
          message: 'Failed to go online. Please try again.',
          isError: true,
        );
      }
      provider.setOnline(!goingOnline); // Revert state on error
    }
  }

  void _showOutOfRegionBottomSheet(double lat, double lng) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppTheme.bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.block_rounded, color: AppTheme.primary, size: 30),
              ),
              const SizedBox(height: 20),
              Text(
                'Hold tight! 🚧',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.text),
              ),
              const SizedBox(height: 12),
              Text(
                'We are launching in your area soon. Join the waitlist to be the first driver on the road here when we open!',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 14, color: AppTheme.text2),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    RegionService().addToWaitlist(lat: lat, lng: lng, type: 'driver');
                    Navigator.pop(ctx);
                    CustomToast.show(
                      context: context,
                      message: 'Thanks! We will notify you when we launch in your area.',
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text('Join Waitlist', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Close', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: AppTheme.text2)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Starts a periodic timer that checks for driver inactivity.
  /// Fires every 60 seconds to see if 2 hours have elapsed since last activity.
  void _startAutoOfflineTimer() {
    _autoOfflineTimer?.cancel();
    _autoOfflineTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      final elapsed = DateTime.now().difference(_lastActiveTime);
      if (elapsed.inMinutes >= AppConstants.autoOfflineMinutes) {
        _autoOffline();
      }
    });
  }

  void _stopAutoOfflineTimer() {
    _autoOfflineTimer?.cancel();
    _autoOfflineTimer = null;
  }

  /// Automatically takes the driver offline after prolonged inactivity.
  Future<void> _autoOffline() async {
    _stopAutoOfflineTimer();
    final provider = context.read<DriverProvider>();
    if (!provider.isOnline) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      await FirebaseFirestore.instance.collection('drivers').doc(uid).update({
        'driverState': 'OFFLINE',
        'isOnline': false,
      });

      provider.setOnline(false);
      _signalSub?.cancel();
      _signalService?.dispose();
      _signalService = null;
      if (mounted) {
        _clearRouteCurve();
        setState(() => _nearbyRides = []);
        CustomToast.show(
          context: context,
          message: 'You were automatically taken offline due to inactivity.',
          isError: true,
        );
      }
    } catch (e) {
      debugPrint('Auto-offline failed: $e');
    }
  }

  /// Resume ride signal listening if the driver is already online.
  /// This handles the case where the dashboard is recreated (e.g. after
  /// completing a ride via pushAndRemoveUntil) while the driver is still online.
  void _resumeIfOnline() {
    final provider = context.read<DriverProvider>();
    if (provider.isOnline && _signalService == null) {
      _lastActiveTime = DateTime.now();
      _startAutoOfflineTimer();
      // _getCurrentLocation fetches fresh GPS, initializes the animator,
      // animates the camera, and then internally calls _startSignalService.
      _getCurrentLocation();
    }
  }

  /// Initialize the RTDB-based ride signal listener.
  /// Replaces the old 10-second Firestore polling.
  void _startSignalService(DriverProvider provider) {
    if (_signalService != null) return; // already running

    final vehicleType =
        (provider.profile?['vehicleType'] as String?)?.toLowerCase() ?? 'auto';
    _signalService = RideSignalService(
      vehicleType: vehicleType,
      onErrorCallback: (errorMsg) {
        if (mounted) {
          CustomToast.show(context: context, message: errorMsg, isError: true);
        }
      },
    );

    // Set the vehicle type on the tracker for FCM topic subscriptions
    provider.tracker?.setVehicleType(vehicleType);

    // IMPORTANT: Set up the stream listener BEFORE calling updateZone/start.
    // The ridesStream uses a broadcast StreamController, meaning events
    // are only delivered to listeners that are active at the time of emission.
    // If updateZone triggers an immediate RTDB snapshot (data already exists),
    // the event would be lost if _signalSub wasn't set up yet.
    _signalSub?.cancel();
    _signalSub = _signalService!.ridesStream.listen((rides) {
      if (!mounted) return;

      // Compute distance from driver to each ride pickup
      final enriched = <Map<String, dynamic>>[];
      for (final signal in rides) {
        // Skip rides that have been declined via the separate ride_declines node
        if (_declinedRides.contains(signal['id'])) continue;

        final pickup = signal['pickup'];
        if (pickup == null || pickup['lat'] == null) continue;

        if (provider.lat != null) {
          final dist = Geolocator.distanceBetween(
            provider.lat!,
            provider.lng!,
            (pickup['lat'] as num).toDouble(),
            (pickup['lng'] as num).toDouble(),
          );
          if (dist < AppConstants.searchRadiusMeters) {
            signal['distance'] = dist;
            enriched.add(signal);
          }
        }
      }

      enriched.sort(
        (a, b) => ((a['distance'] as double?) ?? 0).compareTo(
          (b['distance'] as double?) ?? 0,
        ),
      );

      final bool wasEmpty = _nearbyRides.isEmpty;

      setState(() {
        _nearbyRides = enriched.take(AppConstants.maxVisibleRides).toList();
        _loadingRides = false;
        // Reset carousel to first card when ride list refreshes
        _focusedRideIndex = 0;
      });
      _rebuildFareBubbles();

      // Check RTDB to see if the driver has already placed a bid for any of these rides
      _checkExistingBidsForNearbyRides();

      if (_nearbyRides.isNotEmpty) {
        // If it was empty, animate the camera to frame it.
        // If it wasn't empty, just silently update the curve to point to the new index 0.
        _frameDriverAndPickup(animateCamera: wasEmpty);
      } else {
        _clearRouteCurve();
      }
    });

    // Now seed the zone and start — any RTDB snapshot will be caught by _signalSub
    if (provider.lat != null && provider.lng != null) {
      _signalService!.updateZone(provider.lat!, provider.lng!);
    }

    // Listen for zone changes from SmartTracker
    provider.tracker?.onZoneChanged = (lat, lng) {
      _signalService?.updateZone(lat, lng);
    };

    // Start the RTDB listener
    _signalService!.start();
    setState(() => _loadingRides = true);
  }

  void _frameDriverAndPickup({int? rideIndex, bool animateCamera = true}) {
    if (_mapController == null || _nearbyRides.isEmpty) return;
    final provider = context.read<DriverProvider>();
    if (provider.lat == null || provider.lng == null) return;

    final idx = rideIndex ?? 0;
    if (idx >= _nearbyRides.length) return;

    final ride = _nearbyRides[idx];
    final pickup = ride['pickup'];
    if (pickup == null || pickup['lat'] == null || pickup['lng'] == null)
      return;

    final double driverLat = provider.lat!;
    final double driverLng = provider.lng!;
    final double pickupLat = (pickup['lat'] as num).toDouble();
    final double pickupLng = (pickup['lng'] as num).toDouble();

    final driverPos = LatLng(driverLat, driverLng);
    final pickupPos = LatLng(pickupLat, pickupLng);

    // Calculate distance for the label
    final distMeters = Geolocator.distanceBetween(
      driverLat,
      driverLng,
      pickupLat,
      pickupLng,
    );
    final distLabel = distMeters < 1000
        ? '${distMeters.toInt()} m'
        : '${(distMeters / 1000).toStringAsFixed(1)} km';

    // Build the curved polyline (straight if distance < 100m)
    final curvePoints = _generateCurvePoints(
      driverPos,
      pickupPos,
      isStraight: distMeters < 100,
    );

    // Build the dotted polyline from curve points
    final dottedSegments = _buildDottedPolyline(curvePoints);

    // Create distance label at the apex of the curve
    _buildDistanceLabelMarker(curvePoints, distLabel).then((marker) {
      if (mounted) {
        setState(() {
          _routeCurvePolylines = dottedSegments;
          _distanceLabelMarker = marker;
        });
      }
    });

    if (animateCamera) {
      // Fit bounds to show both points
      final minLat = math.min(driverLat, pickupLat);
      final maxLat = math.max(driverLat, pickupLat);
      final minLng = math.min(driverLng, pickupLng);
      final maxLng = math.max(driverLng, pickupLng);

      final bounds = LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      );

      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && _mapController != null) {
          _mapController?.animateCamera(
            CameraUpdate.newLatLngBounds(bounds, 120.0),
          );
        }
      });
    }
  }

  /// Clear the curve and distance label when rides disappear
  void _clearRouteCurve() {
    setState(() {
      _routeCurvePolylines = {};
      _distanceLabelMarker = null;
    });
  }

  void _removeRideLocally(
    String rideId, {
    bool markDeclined = false,
    bool removeBid = false,
  }) {
    if (!mounted) return;
    setState(() {
      if (removeBid) _biddedRides.remove(rideId);
      if (markDeclined) _declinedRides.add(rideId);

      _nearbyRides.removeWhere((r) => r['id'] == rideId);

      if (_focusedRideIndex >= _nearbyRides.length) {
        _focusedRideIndex = (_nearbyRides.length - 1).clamp(0, 999);
      }
    });

    if (markDeclined) {
      _saveDeclinedRides();
    }

    _rebuildFareBubbles();

    if (_nearbyRides.isNotEmpty) {
      _frameDriverAndPickup(rideIndex: _focusedRideIndex, animateCamera: false);
    } else {
      _clearRouteCurve();
    }
  }

  /// Generate a smooth quadratic Bézier curve between two points.
  /// The control point is offset perpendicular to the line, creating an arc.
  List<LatLng> _generateCurvePoints(
    LatLng start,
    LatLng end, {
    bool isStraight = false,
  }) {
    const int segments = 40;
    final points = <LatLng>[];

    final double midLat = (start.latitude + end.latitude) / 2;
    final double midLng = (start.longitude + end.longitude) / 2;

    // Calculate perpendicular offset for the control point
    final double dLat = end.latitude - start.latitude;
    final double dLng = end.longitude - start.longitude;
    final double dist = math.sqrt(dLat * dLat + dLng * dLng);

    // Arc height proportional to distance (clamped)
    final double arcHeight = isStraight
        ? 0.0
        : (dist * 0.25).clamp(0.001, 0.02);

    // Perpendicular direction (rotate 90°)
    final double perpLat = -dLng / dist * arcHeight;
    final double perpLng = dLat / dist * arcHeight;

    // Control point
    final double ctrlLat = midLat + perpLat;
    final double ctrlLng = midLng + perpLng;

    for (int i = 0; i <= segments; i++) {
      final double t = i / segments;
      final double oneMinusT = 1 - t;

      // Quadratic Bézier: B(t) = (1-t)²P0 + 2(1-t)tP1 + t²P2
      final double lat =
          oneMinusT * oneMinusT * start.latitude +
          2 * oneMinusT * t * ctrlLat +
          t * t * end.latitude;
      final double lng =
          oneMinusT * oneMinusT * start.longitude +
          2 * oneMinusT * t * ctrlLng +
          t * t * end.longitude;

      points.add(LatLng(lat, lng));
    }

    return points;
  }

  /// Build a dotted polyline from a list of curve points.
  /// Creates alternating visible/invisible segments.
  Set<Polyline> _buildDottedPolyline(List<LatLng> points) {
    final polylines = <Polyline>{};
    const int dashLength = 3; // points per dash
    const int gapLength = 2; // points per gap
    int idx = 0;
    int segmentId = 0;

    while (idx < points.length) {
      // Dash segment
      final dashEnd = math.min(idx + dashLength, points.length);
      if (dashEnd > idx + 1) {
        polylines.add(
          Polyline(
            polylineId: PolylineId('route_dash_$segmentId'),
            points: points.sublist(idx, dashEnd),
            color: const Color(0xFF4285F4), // Google blue
            width: 4,
            patterns: [],
          ),
        );
      }
      segmentId++;
      idx = dashEnd;

      // Gap segment (just skip points)
      idx += gapLength;
    }

    return polylines;
  }

  /// Build a distance label marker at the apex (midpoint) of the curve.
  Future<Marker> _buildDistanceLabelMarker(
    List<LatLng> curvePoints,
    String label,
  ) async {
    // Place marker at the apex of the curve (the midpoint)
    final apexIndex = curvePoints.length ~/ 2;
    final apexPos = curvePoints[apexIndex];

    final icon = await _createDistanceBubbleIcon(label);

    return Marker(
      markerId: const MarkerId('distance_label'),
      position: apexPos,
      icon: icon,
      anchor: const Offset(0.5, 0.5),
      flat: true,
      zIndexInt: 10,
    );
  }

  /// Paint a compact rounded pill showing the distance text (e.g. "2.5 km").
  Future<BitmapDescriptor> _createDistanceBubbleIcon(String label) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: label,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.2,
        ),
      ),
    )..layout();

    const double hPad = 10;
    const double vPad = 5;
    final double w = textPainter.width + hPad * 2;
    final double h = textPainter.height + vPad * 2;

    // Shadow
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(1, 2, w, h),
        Radius.circular(h / 2),
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // Background pill
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h),
        Radius.circular(h / 2),
      ),
      Paint()..color = const Color(0xFF4285F4),
    );

    // Text
    textPainter.paint(canvas, Offset(hPad, vPad));

    final image = await recorder.endRecording().toImage(
      w.ceil() + 2,
      h.ceil() + 3,
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  }

  /// Dynamically check RTDB for existing bids for the currently visible nearby rides.
  Future<void> _checkExistingBidsForNearbyRides() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || !mounted) return;

    final syncEngine = context.read<SyncEngine>();

    for (final ride in _nearbyRides) {
      final rideId = ride['id'];
      if (!_biddedRides.containsKey(rideId)) {
        // 1. Check local SyncEngine queue (if the app was force-closed before RTDB sync finished)
        final localPendingPrice = syncEngine.getPendingBidPrice(rideId);
        if (localPendingPrice != null) {
          _biddedRides[rideId] = localPendingPrice;
          _listenForDecline(rideId);
          if (mounted) setState(() {});
          continue; // Skip RTDB check since we found it locally
        }

        // 2. Check RTDB (if it was successfully synced but we just restarted the app)
        try {
          final snap = await FirebaseDatabase.instance
              .ref('active_bids/$rideId/$uid')
              .get();
          if (snap.exists && snap.value != null) {
            final data = Map<String, dynamic>.from(snap.value as Map);
            final price = (data['price'] as num).toInt();
            _biddedRides[rideId] = price;
            // Start decline listener for this bid
            _listenForDecline(rideId);
            if (mounted) setState(() {});
          }
        } catch (_) {}
      }
    }
  }

  /// Listen for rider bid-decline on the separate `ride_declines/{rideId}/{driverUid}` node.
  /// When the rider declines, this value is set to `true` and we remove the ride
  /// from the driver's view with a toast notification.
  void _listenForDecline(String rideId) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    // Don't double-subscribe
    if (_declineSubs.containsKey(rideId)) return;

    _declineSubs[rideId] = FirebaseDatabase.instance
        .ref('ride_declines/$rideId/$uid')
        .onValue
        .listen(
          (event) {
            if (event.snapshot.value == true) {
              _removeRideLocally(rideId, markDeclined: true, removeBid: true);
              CustomToast.show(
                context: context,
                message: '⚠️ Rider declined your bid.',
                isError: true,
              );
              // Clean up this listener — no longer needed
              _declineSubs[rideId]?.cancel();
              _declineSubs.remove(rideId);
            }
          },
          onError: (error) {
            debugPrint('Error listening to ride declines: $error');
          },
        );
  }

  Future<void> _placeBid(Map<String, dynamic> ride, int bidPrice) async {
    final provider = context.read<DriverProvider>();

    // Block if driver already declined or rider declined this bid
    if (_declinedRides.contains(ride['id'])) {
      CustomToast.show(
        context: context,
        message: '⚠️ This ride has been declined.',
        isError: true,
      );
      return;
    }

    // Block if driver is in ON_RIDE state
    if (provider.isBusy) {
      CustomToast.show(
        context: context,
        message: '⚠️ You are already in an active ride!',
        isError: true,
      );
      return;
    }

    // Block if driver has too many active bids
    if (_biddedRides.length >= AppConstants.maxActiveBids) {
      CustomToast.show(
        context: context,
        message:
            '⚠️ Maximum ${AppConstants.maxActiveBids} active bids reached.',
        isError: true,
      );
      return;
    }

    setState(() => _bidding = true);
    try {
      final operationId = const Uuid().v4();

      // Enqueue to durable queue — SyncEngine will deliver via placeBid Cloud Function
      final item = QueueItem(
        id: operationId,
        type: 'PLACE_BID',
        payload: {
          'rideId': ride['id'],
          'riderId': ride['riderId'],
          'price': bidPrice,
          'driverName': provider.profile?['name'] ?? 'Driver',
          'driverPhone': provider.profile?['phone'] ?? '',
          'vehicleType':
              (provider.profile?['vehicleType'] as String?)?.toLowerCase() ??
              'auto',
          'vehicleNumber': provider.profile?['vehicleNumber'] ?? '',
          'driverImageUrl': provider.profile?['documents']?['selfieUrl'] ?? '',
          'vehicleImageUrl':
              provider.profile?['documents']?['vehicleUrl'] ?? '',
          'driverLat': provider.lat,
          'driverLng': provider.lng,
        },
      );
      await context.read<SyncEngine>().enqueue(item);

      // Optimistic local state update
      if (provider.driverState == 'ONLINE_IDLE') {
        provider.setDriverState('BIDDING');
      }

      setState(() {
        _biddedRides[ride['id']] = bidPrice;
      });

      // Start listening for rider decline on this ride
      _listenForDecline(ride['id'] as String);

      if (mounted) {
        CustomToast.show(
          context: context,
          message: 'Bid of ₹$bidPrice placed!',
          isError: false,
        );
      }
    } catch (e) {
      if (mounted) {
        CustomToast.show(
          context: context,
          message: 'Failed to place bid',
          isError: true,
        );
      }
    }
    setState(() => _bidding = false);
  }

  void _showBidDialog(Map<String, dynamic> ride) {
    final riderOffer = (ride['offeredPrice'] ?? ride['riderBid'] ?? 80) as num;
    int bidPrice = riderOffer.toInt();
    final maxBid = (riderOffer * 2).toInt(); // 100% cap
    final bidController = TextEditingController(text: bidPrice.toString());
    String? capWarning;

    // Distance info
    final distMeters = (ride['distance'] as double?) ?? 0;
    final distLabel = distMeters < 1000
        ? '${distMeters.toInt()}m'
        : '${(distMeters / 1000).toStringAsFixed(1)} km';
    final etaMin = ((distMeters / 1000) / AppConstants.avgSpeedKmh * 60).ceil();
    final etaLabel = etaMin < 1 ? '<1 min' : '$etaMin min';

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bg,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                20,
                24,
                MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.text3,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Place Your Bid',
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${ride['pickup']?['short_name']} → ${ride['drop']?['short_name']}',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: AppTheme.text2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${ride['distanceKm']} km ride · $distLabel away · ~$etaLabel pickup',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppTheme.text3,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Rider's bid reference
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Rider offered ₹${riderOffer.toInt()}  (max ₹$maxBid)',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Manual bid input with +/- quick adjust
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      InkWell(
                        onTap: () {
                          if (bidPrice > 20) {
                            bidPrice -= 10;
                            bidController.text = bidPrice.toString();
                            setSheetState(() {});
                          }
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppTheme.danger.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.danger.withValues(alpha: 0.3),
                            ),
                          ),
                          child: const Icon(
                            Icons.remove,
                            color: AppTheme.danger,
                            size: 22,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Text input field
                      SizedBox(
                        width: 120,
                        child: TextField(
                          controller: bidController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.success,
                          ),
                          decoration: InputDecoration(
                            prefixText: '₹ ',
                            prefixStyle: GoogleFonts.inter(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.success,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: AppTheme.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                color: AppTheme.success,
                                width: 2,
                              ),
                            ),
                            filled: true,
                            fillColor: AppTheme.bg,
                          ),
                          onChanged: (val) {
                            final parsed = int.tryParse(val);
                            if (parsed != null && parsed > 0) {
                              bidPrice = parsed;
                              if (parsed > maxBid) {
                                capWarning =
                                    'Max counter price is ₹$maxBid (2× rider offer)';
                              } else {
                                capWarning = null;
                              }
                              setSheetState(() {});
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      InkWell(
                        onTap: () {
                          bidPrice += 10;
                          bidController.text = bidPrice.toString();
                          setSheetState(() {});
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppTheme.success.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.success.withValues(alpha: 0.3),
                            ),
                          ),
                          child: const Icon(
                            Icons.add,
                            color: AppTheme.success,
                            size: 22,
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Cap warning
                  if (capWarning != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: AppTheme.danger,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              capWarning!,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppTheme.danger,
                                fontWeight: FontWeight.w600,
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
                    height: 54,
                    child: ElevatedButton(
                      onPressed: (_bidding || bidPrice > maxBid)
                          ? null
                          : () {
                              final finalPrice =
                                  int.tryParse(bidController.text) ?? bidPrice;
                              if (finalPrice > maxBid) return;
                              Navigator.pop(ctx);
                              _placeBid(ride, finalPrice);
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: bidPrice > maxBid
                            ? AppTheme.text3
                            : AppTheme.success,
                      ),
                      child: Text(
                        'Place Bid ₹$bidPrice',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DriverProvider>();

    // Calculate dynamic bottom padding so native Google Map controls
    // (Zoom buttons, Location button, Google logo) stay above the bottom sheet
    final double mapBottomPadding = !provider.isOnline
        ? 120.0
        : (_nearbyRides.isEmpty ? 160.0 : 380.0);

    return Scaffold(
      drawer: _buildDrawer(context, provider),
      body: Stack(
        children: [
          // Map
          GoogleMap(
            style: lightMapStyle,
            // Top padding keeps compass below status bar, bottom padding keeps controls above sheet
            padding: EdgeInsets.only(top: 90, bottom: mapBottomPadding),
            myLocationEnabled:
                false, // Turn off blue dot as we have our own marker
            myLocationButtonEnabled:
                false, // Disable native location button since we use a custom one
            zoomControlsEnabled: true, // Keep zoom buttons
            initialCameraPosition: CameraPosition(
              target: provider.lat != null
                  ? LatLng(provider.lat!, provider.lng!)
                  : const LatLng(17.385, 78.487),
              zoom: 14,
            ),
            onMapCreated: (controller) {
              _mapController = controller;
              _mapController?.setMapStyle(lightMapStyle);
            },
            markers: {
              if (_driverAnimator.currentPos != null && provider.isOnline)
                Marker(
                  markerId: const MarkerId('driver'),
                  position: _driverAnimator.currentPos!,
                  rotation: _driverAnimator.currentHeading,
                  anchor: const Offset(
                    0.5,
                    0.5,
                  ), // Forces rotation exactly around the center of the image
                  icon: _getVehicleIcon(
                    (provider.profile?['vehicleType'] as String?)
                        ?.toLowerCase(),
                  ),
                ),
              ..._buildRideMarkers(),
              if (_distanceLabelMarker != null) _distanceLabelMarker!,
            },
            polylines: _routeCurvePolylines,
          ),

          // Loading overlay
          if (_locating)
            Container(
              color: AppTheme.bg.withValues(alpha: 0.9),
              child: const Center(
                child: MovingVehicleLoader(text: 'Getting your location...'),
              ),
            ),

          // Top status bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.bg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Text(
                      AppConstants
                              .vehicleTypes[(provider.profile?['vehicleType']
                                      as String?)
                                  ?.toLowerCase()]
                              ?.icon ??
                          '🚗',
                      style: const TextStyle(fontSize: 28),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            provider.profile?['name'] ?? 'Driver',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            provider.isOnline ? '🟢 Online' : '⚫ Offline',
                            style: GoogleFonts.inter(
                              color: provider.isOnline
                                  ? AppTheme.success
                                  : AppTheme.text3,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: provider.isOnline,
                      onChanged: (val) => _toggleOnline(),
                      activeThumbColor: AppTheme.success,
                    ),
                    Builder(
                      builder: (ctx) => IconButton(
                        icon: const Icon(
                          Icons.menu,
                          color: AppTheme.text3,
                          size: 24,
                        ),
                        onPressed: () => Scaffold.of(ctx).openDrawer(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Sync Engine Retry Button
          Consumer<SyncEngine>(
            builder: (ctx, syncEngine, _) {
              if (!syncEngine.hasFailedItems) return const SizedBox.shrink();
              return Positioned(
                top: 100, // Below top status bar
                left: 0,
                right: 0,
                child: Center(
                  child: PremiumRetryButton(
                    onRetry: () {
                      syncEngine.forceRetry();
                      CustomToast.show(
                        context: context,
                        message: 'Retrying connection...',
                        isError: false,
                      );
                    },
                  ),
                ),
              );
            },
          ),

          // Custom Location Button
          Positioned(
            bottom:
                mapBottomPadding +
                115, // Places it right above the native zoom controls
            right: 12,
            child: InkWell(
              onTap: () {
                if (provider.lat != null &&
                    provider.lng != null &&
                    _mapController != null) {
                  _mapController!.animateCamera(
                    CameraUpdate.newLatLngZoom(
                      LatLng(provider.lat!, provider.lng!),
                      16,
                    ),
                  );
                }
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.my_location_rounded,
                  color: Colors.black54,
                  size: 22,
                ),
              ),
            ),
          ),

          // Bottom panel
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomPanel(provider),
          ),
        ],
      ),
    );
  }

  /// Builds the Set of fare-bubble Markers for the nearby rides list.
  Set<Marker> _buildRideMarkers() {
    final markers = <Marker>{};
    for (int i = 0; i < _nearbyRides.length; i++) {
      final ride = _nearbyRides[i];
      final rideId = ride['id'] as String;
      final isActive = i == _focusedRideIndex;
      final cacheKey = '${rideId}_$isActive';
      final icon = _fareBubbleCache[cacheKey];
      if (icon == null) continue;
      final lat = (ride['pickup']?['lat'] as num?)?.toDouble();
      final lng = (ride['pickup']?['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      markers.add(
        Marker(
          markerId: MarkerId(rideId),
          position: LatLng(lat, lng),
          icon: icon,
          anchor: const Offset(0.5, 54 / 62),
          onTap: () {
            _ridePageController.animateToPage(
              i,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeInOut,
            );
          },
        ),
      );
    }
    return markers;
  }

  Widget _buildBottomPanel(DriverProvider provider) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bg,
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
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: AppTheme.text3,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              if (provider.isOnline) ...[
                // Header row
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Row(
                    children: [
                      Text(
                        'Nearby Rides',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${_nearbyRides.length} rides',
                        style: GoogleFonts.inter(
                          color: AppTheme.text3,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),

                if (_nearbyRides.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 20,
                      horizontal: 20,
                    ),
                    child: Text(
                      provider.lat == null
                          ? 'Getting your location...'
                          : 'No rides nearby. Stay online!',
                      style: GoogleFonts.inter(
                        color: AppTheme.text3,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  // ── Snap Carousel ──────────────────────────────────────
                  SizedBox(
                    height: 270,
                    child: PageView.builder(
                      controller: _ridePageController,
                      itemCount: _nearbyRides.length,
                      onPageChanged: (index) {
                        setState(() => _focusedRideIndex = index);
                        // Rebuild markers so active glow switches correctly
                        _rebuildFareBubbles();
                        // Fit map to show both driver and focused pickup with curve
                        _frameDriverAndPickup(rideIndex: index);
                      },
                      itemBuilder: (context, index) {
                        final ride = _nearbyRides[index];
                        final distMeters = (ride['distance'] as double);
                        final distLabel = distMeters < 1000
                            ? '${distMeters.toInt()}m'
                            : '${(distMeters / 1000).toStringAsFixed(1)} km';
                        final etaMin =
                            ((distMeters / 1000) /
                                    AppConstants.avgSpeedKmh *
                                    60)
                                .ceil();
                        final etaLabel = etaMin < 1 ? '<1 min' : '$etaMin min';
                        final rideId = ride['id'] as String;
                        final isBidded = _biddedRides.containsKey(rideId);
                        final isFocused = index == _focusedRideIndex;

                        return AnimatedScale(
                          scale: isFocused ? 1.0 : 0.93,
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeOut,
                          child: AnimatedOpacity(
                            opacity: isFocused ? 1.0 : 0.60,
                            duration: const Duration(milliseconds: 280),
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.bg,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: isBidded
                                        ? AppTheme.primary
                                        : isFocused
                                        ? AppTheme.border
                                        : AppTheme.border.withValues(
                                            alpha: 0.5,
                                          ),
                                    width: isBidded ? 2 : 1,
                                  ),
                                  boxShadow: isFocused
                                      ? [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.18,
                                            ),
                                            blurRadius: 16,
                                            offset: const Offset(0, 6),
                                          ),
                                        ]
                                      : [],
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Card header — fare + distance
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        14,
                                        16,
                                        10,
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Text(
                                                    'Ride ${index + 1} of ${_nearbyRides.length}',
                                                    style: GoogleFonts.inter(
                                                      fontSize: 11,
                                                      color: AppTheme.text3,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  const Icon(
                                                    Icons.timer_outlined,
                                                    size: 13,
                                                    color: AppTheme.primary,
                                                  ),
                                                  const SizedBox(width: 3),
                                                  RideTimerText(
                                                    createdAtMs:
                                                        (ride['createdAt']
                                                                as num?)
                                                            ?.toInt() ??
                                                        DateTime.now()
                                                            .millisecondsSinceEpoch,
                                                    onExpired: () {
                                                      if (mounted) {
                                                        _removeRideLocally(
                                                          rideId,
                                                        );
                                                      }
                                                    },
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  Icon(
                                                    provider.profile?['vehicleType'] == 'bike'
                                                        ? Icons.motorcycle
                                                        : Icons.electric_rickshaw,
                                                    color: AppTheme.primary,
                                                    size: 18,
                                                  ),
                                                  const SizedBox(width: 5),
                                                  Text(
                                                    '${ride['distanceKm']} km',
                                                    style: GoogleFonts.inter(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      fontSize: 17,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                isBidded
                                                    ? 'Your Bid'
                                                    : 'Offered',
                                                style: GoogleFonts.inter(
                                                  fontSize: 11,
                                                  color: isBidded
                                                      ? AppTheme.primary
                                                      : AppTheme.text3,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                isBidded
                                                    ? '₹${_biddedRides[rideId]}'
                                                    : '₹${ride['riderBid']}',
                                                style: GoogleFonts.inter(
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.w800,
                                                  color: isBidded
                                                      ? AppTheme.primary
                                                      : AppTheme.success,
                                                ),
                                              ),
                                              if (isBidded &&
                                                  _biddedRides[rideId] !=
                                                      ride['riderBid'])
                                                Text(
                                                  'Offer: ₹${ride['riderBid']}',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 11,
                                                    color: AppTheme.text3,
                                                    decoration: TextDecoration
                                                        .lineThrough,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),

                                    // ETA chip
                                    Builder(
                                      builder: (_) {
                                        final chipColor = etaMin < 3
                                            ? AppTheme.success
                                            : etaMin <= 7
                                            ? AppTheme.warning
                                            : AppTheme.danger;
                                        return Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: chipColor.withValues(
                                              alpha: 0.07,
                                            ),
                                            border: Border.symmetric(
                                              horizontal: BorderSide(
                                                color: AppTheme.border,
                                              ),
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.near_me_rounded,
                                                size: 13,
                                                color: chipColor,
                                              ),
                                              const SizedBox(width: 5),
                                              Text(
                                                '$distLabel to pickup  ·  ~$etaLabel',
                                                style: GoogleFonts.inter(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  color: chipColor,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),

                                    // Route preview
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        14,
                                        10,
                                        14,
                                        8,
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Column(
                                            children: [
                                              const Icon(
                                                Icons.my_location,
                                                color: AppTheme.primary,
                                                size: 18,
                                              ),
                                              Container(
                                                width: 2,
                                                height: 28,
                                                margin:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 3,
                                                    ),
                                                color: AppTheme.border,
                                              ),
                                              const Icon(
                                                Icons.location_on,
                                                color: AppTheme.danger,
                                                size: 18,
                                              ),
                                            ],
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  ride['pickup']?['display_name'] ??
                                                      ride['pickup']?['short_name'] ??
                                                      'Pickup',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 10),
                                                Text(
                                                  ride['drop']?['display_name'] ??
                                                      ride['drop']?['short_name'] ??
                                                      'Drop',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Action buttons
                                    Container(
                                      decoration: const BoxDecoration(
                                        color: AppTheme.bg,
                                        borderRadius: BorderRadius.vertical(
                                          bottom: Radius.circular(18),
                                        ),
                                      ),
                                      child: isBidded
                                          ? Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 12,
                                                  ),
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  const Icon(
                                                    Icons.check_circle,
                                                    color: AppTheme.success,
                                                    size: 18,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    'Bid placed · waiting for rider',
                                                    style: GoogleFonts.inter(
                                                      color: AppTheme.success,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            )
                                          : Row(
                                              children: [
                                                Expanded(
                                                  child: InkWell(
                                                    onTap: () {
                                                      _removeRideLocally(
                                                        rideId,
                                                        markDeclined: true,
                                                      );
                                                    },
                                                    borderRadius:
                                                        const BorderRadius.only(
                                                          bottomLeft:
                                                              Radius.circular(
                                                                18,
                                                              ),
                                                        ),
                                                    child: Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            vertical: 14,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: AppTheme.danger
                                                            .withValues(
                                                              alpha: 0.1,
                                                            ),
                                                        borderRadius:
                                                            const BorderRadius.only(
                                                              bottomLeft:
                                                                  Radius.circular(
                                                                    18,
                                                                  ),
                                                            ),
                                                      ),
                                                      alignment:
                                                          Alignment.center,
                                                      child: Text(
                                                        'Decline',
                                                        style:
                                                            GoogleFonts.inter(
                                                              color: AppTheme
                                                                  .danger,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                              fontSize: 15,
                                                            ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                Expanded(
                                                  child: InkWell(
                                                    onTap: () =>
                                                        _showBidDialog(ride),
                                                    borderRadius:
                                                        const BorderRadius.only(
                                                          bottomRight:
                                                              Radius.circular(
                                                                18,
                                                              ),
                                                        ),
                                                    child: Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            vertical: 14,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: AppTheme.primary
                                                            .withValues(
                                                              alpha: 0.1,
                                                            ),
                                                        borderRadius:
                                                            const BorderRadius.only(
                                                              bottomRight:
                                                                  Radius.circular(
                                                                    18,
                                                                  ),
                                                            ),
                                                      ),
                                                      alignment:
                                                          Alignment.center,
                                                      child: Text(
                                                        'Place Bid',
                                                        style:
                                                            GoogleFonts.inter(
                                                              color: AppTheme
                                                                  .primary,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                              fontSize: 15,
                                                            ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDrawer(BuildContext context, DriverProvider provider) {
    return Drawer(
      backgroundColor: AppTheme.bg,
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(color: AppTheme.bg),
            accountName: Text(
              provider.profile?['name'] ?? 'Driver',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.bold,
                color: AppTheme.text,
              ),
            ),
            accountEmail: Text(
              provider.profile?['phone'] ?? '',
              style: GoogleFonts.inter(color: AppTheme.text2),
            ),
            currentAccountPicture: CircleAvatar(
              backgroundColor: AppTheme.primary,
              backgroundImage:
                  provider.profile?['documents']?['selfieUrl'] != null
                  ? NetworkImage(provider.profile!['documents']['selfieUrl'])
                  : null,
              child: provider.profile?['documents']?['selfieUrl'] == null
                  ? const Icon(Icons.person, color: Colors.white)
                  : null,
            ),
          ),
          // Today's Earnings — real data from Firestore
          StreamBuilder<QuerySnapshot>(
            stream: () {
              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (uid == null) return Stream<QuerySnapshot>.empty();
              final now = DateTime.now();
              final todayStart = DateTime(now.year, now.month, now.day);
              return FirebaseFirestore.instance
                  .collection('rides')
                  .where('driverId', isEqualTo: uid)
                  .where('status', isEqualTo: 'completed')
                  .where(
                    'completedAt',
                    isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart),
                  )
                  .snapshots();
            }(),
            builder: (context, snapshot) {
              double todayEarnings = 0;
              int todayRides = 0;
              if (snapshot.hasData) {
                for (final doc in snapshot.data!.docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  todayEarnings +=
                      double.tryParse(data['finalPrice']?.toString() ?? '0') ??
                      0.0;
                  todayRides++;
                }
              }
              final isLoading =
                  snapshot.connectionState == ConnectionState.waiting;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.bg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppTheme.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.account_balance_wallet_rounded,
                        color: AppTheme.success,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Today's Earnings",
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.text2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          isLoading
                              ? Container(
                                  height: 20,
                                  width: 80,
                                  decoration: BoxDecoration(
                                    color: AppTheme.border,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                )
                              : Text(
                                  '₹${todayEarnings.toStringAsFixed(0)}',
                                  style: GoogleFonts.inter(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.success,
                                  ),
                                ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          isLoading ? '--' : '$todayRides',
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.text,
                          ),
                        ),
                        Text(
                          'rides',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppTheme.text3,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),

          ListTile(
            leading: const Icon(Icons.history, color: AppTheme.text),
            title: Text(
              'Earnings History',
              style: GoogleFonts.inter(color: AppTheme.text),
            ),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const RideEarningsHistoryScreen(),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.person, color: AppTheme.text),
            title: Text(
              'My Profile',
              style: GoogleFonts.inter(color: AppTheme.text),
            ),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.card_membership, color: AppTheme.text),
            title: Text(
              'Subscription',
              style: GoogleFonts.inter(color: AppTheme.text),
            ),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.card_giftcard, color: AppTheme.text),
            title: Text(
              'Refer & Earn',
              style: GoogleFonts.inter(color: AppTheme.text),
            ),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ReferralScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.support_agent, color: AppTheme.text),
            title: Text(
              'Support',
              style: GoogleFonts.inter(color: AppTheme.text),
            ),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SupportScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings, color: AppTheme.text),
            title: Text(
              'Settings',
              style: GoogleFonts.inter(color: AppTheme.text),
            ),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
          const Spacer(),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: AppTheme.danger),
            title: Text(
              'Log Out',
              style: GoogleFonts.inter(
                color: AppTheme.danger,
                fontWeight: FontWeight.bold,
              ),
            ),
            onTap: () async {
              provider.setOnline(false);
              await FirebaseFirestore.instance
                  .collection('drivers')
                  .doc(FirebaseAuth.instance.currentUser!.uid)
                  .update({'isOnline': false, 'driverState': 'OFFLINE'});
              await FirebaseAuth.instance.signOut();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const AuthGate()),
                  (_) => false,
                );
              }
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class RideTimerText extends StatefulWidget {
  final int createdAtMs;
  final VoidCallback onExpired;

  const RideTimerText({
    super.key,
    required this.createdAtMs,
    required this.onExpired,
  });

  @override
  State<RideTimerText> createState() => _RideTimerTextState();
}

class _RideTimerTextState extends State<RideTimerText> {
  Timer? _timer;
  int _remainingSeconds = 0;

  @override
  void initState() {
    super.initState();
    _calculateRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _calculateRemaining();
    });
  }

  void _calculateRemaining() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final elapsed = ((now - widget.createdAtMs) / 1000).floor();
    final remaining = AppConstants.rideExpiryMinutes * 60 - elapsed;
    if (remaining <= 0) {
      if (_remainingSeconds > 0 || _timer?.isActive == true) {
        if (mounted) setState(() => _remainingSeconds = 0);
        _timer?.cancel();
        widget.onExpired();
      }
    } else {
      if (mounted) setState(() => _remainingSeconds = remaining);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_remainingSeconds <= 0) {
      return Text(
        'Expired',
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppTheme.danger,
        ),
      );
    }
    final mins = _remainingSeconds ~/ 60;
    final secs = _remainingSeconds % 60;
    final color = _remainingSeconds < 30 ? AppTheme.danger : AppTheme.primary;
    return Text(
      '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}',
      style: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    );
  }
}
