// lib/screens/dashboard_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../config/constants.dart';
import '../utils/map_style.dart';
import '../providers/driver_provider.dart';
import '../services/ride_signal_service.dart';
import 'active_ride_screen.dart';
import 'ride_earnings_history_screen.dart';
import 'subscription_screen.dart';
import 'profile_screen.dart';
import 'support_screen.dart';
import 'settings_screen.dart';
import '../utils/custom_toast.dart';
import '../services/sync_engine.dart';
import '../models/queue_item.dart';
import 'package:uuid/uuid.dart';
import '../utils/map_utils.dart';
import '../widgets/premium_retry_button.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
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
  final Set<String> _declinedRides = {};
  final Map<String, int> _biddedRides = {};
  final Map<String, StreamSubscription> _declineSubs = {};

  // Snap carousel
  late final PageController _ridePageController;
  int _focusedRideIndex = 0;
  // Cache of fare bubble markers keyed by "<rideId>_<isActive>"
  final Map<String, BitmapDescriptor> _fareBubbleCache = {};

  bool _locating = false;
  bool _locationGranted = false;

  @override
  void initState() {
    super.initState();
    _ridePageController = PageController(viewportFraction: 0.84);
    _requestPermissionsSequentially();
    _listenForActiveRide();
    _loadCustomMarkers();
  }

  /// Request notification permission first, then location permission.
  /// Android cannot show two permission dialogs at the same time,
  /// so they must be chained sequentially.
  Future<void> _requestPermissionsSequentially() async {
    await _checkNotificationPermission();
    await _getCurrentLocation();
  }

  Future<void> _loadCustomMarkers() async {
    const config = ImageConfiguration(size: Size(48, 48));
    _autoIcon = await BitmapDescriptor.asset(config, 'assets/images/map_icons/auto.png');
    _bikeIcon = await BitmapDescriptor.asset(config, 'assets/images/map_icons/bike.png');

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

  Future<void> _getCurrentLocation() async {
    if (mounted) setState(() => _locating = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          CustomToast.show(
            context: context,
            message: 'Please enable location services',
            isError: true,
          );
          setState(() {
            _locating = false;
            _locationGranted = false;
          });
        }
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) {
          CustomToast.show(
            context: context,
            message: 'Location permission is required. Please enable in settings.',
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
        provider.updateLocation(pos.latitude, pos.longitude);
        _mapController?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 15));
        setState(() => _locating = false);
        
        // If online, start RTDB signal listener
        if (provider.isOnline) {
          _startSignalService(provider);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  void dispose() {
    _ridePageController.dispose();
    _rideListener?.cancel();
    _signalSub?.cancel();
    _signalService?.dispose();
    for (final sub in _declineSubs.values) {
      sub.cancel();
    }
    _declineSubs.clear();
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
        .listen((snap) {
      if (snap.docs.isNotEmpty) {
        if (!mounted) return;
        try {
          final ride = snap.docs.first;
          final data = Map<String, dynamic>.from(ride.data() as Map);
          data['id'] = ride.id;

          context.read<DriverProvider>().setActiveRide(data);
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => ActiveRideScreen(rideId: ride.id),
            ),
          );
        } catch (e) {
          debugPrint('Error in DashboardScreen _listenForActiveRide: $e');
        }
      }
    }, onError: (error) {
      debugPrint('Firestore stream error in DashboardScreen: $error');
    });
  }

  Future<void> _toggleOnline() async {
    final provider = context.read<DriverProvider>();
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final goingOnline = !provider.isOnline;

    // If going online, check location permission first
    if (goingOnline) {
      if (!provider.isSubscriptionActive) {
        if (mounted) {
          CustomToast.show(
            context: context,
            message: 'Your subscription is expired. Please renew to go online.',
            isError: true,
          );
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
          );
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
              message: 'Location permission is required to go online. Please allow location access.',
              isError: true,
            );
          }
          return;
        }
      }
    }

    final newDriverState = goingOnline ? 'ONLINE_IDLE' : 'OFFLINE';

    await FirebaseFirestore.instance
        .collection('drivers')
        .doc(uid)
        .update({
          'driverState': newDriverState,
          'isOnline': goingOnline, // Keep for backward compat during migration
        });

    provider.setOnline(goingOnline);

    if (goingOnline) {
      _startSignalService(provider);
    } else {
      _signalSub?.cancel();
      _signalService?.dispose();
      _signalService = null;
      setState(() => _nearbyRides = []);
    }
  }

  /// Initialize the RTDB-based ride signal listener.
  /// Replaces the old 10-second Firestore polling.
  void _startSignalService(DriverProvider provider) {
    if (_signalService != null) return; // already running

    final vehicleType = provider.profile?['vehicleType'] as String? ?? 'auto';
    _signalService = RideSignalService(
      vehicleType: vehicleType,
      onErrorCallback: (errorMsg) {
        if (mounted) {
          CustomToast.show(
            context: context,
            message: errorMsg,
            isError: true,
          );
        }
      },
    );

    // Set the vehicle type on the tracker for FCM topic subscriptions
    provider.tracker?.setVehicleType(vehicleType);

    // Seed initial zone from current location
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

    // Load existing bids for this driver
    _loadExistingBids();

    // Listen to the stream and update UI
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

      enriched.sort((a, b) =>
          ((a['distance'] as double?) ?? 0).compareTo((b['distance'] as double?) ?? 0));

      setState(() {
        _nearbyRides = enriched
            .take(AppConstants.maxVisibleRides)
            .toList();
        _loadingRides = false;
        // Reset carousel to first card when ride list refreshes
        _focusedRideIndex = 0;
      });
      _rebuildFareBubbles();
    });
  }

  /// One-time load of this driver's existing pending bids.
  Future<void> _loadExistingBids() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final bidsSnap = await FirebaseFirestore.instance
          .collection('bids')
          .where('driverId', isEqualTo: uid)
          .where('status', isEqualTo: 'pending')
          .get();

      _biddedRides.clear();
      for (final doc in bidsSnap.docs) {
        final rideId = doc['rideId'] as String;
        _biddedRides[rideId] = doc['price'] as int;
        // Start decline listener for each existing bid
        _listenForDecline(rideId);
      }
      if (mounted) setState(() {});
    } catch (_) {}
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
        .listen((event) {
      if (event.snapshot.value == true) {
        if (mounted) {
          setState(() {
            _biddedRides.remove(rideId);
            _declinedRides.add(rideId);
            _nearbyRides.removeWhere((r) => r['id'] == rideId);
          });
          CustomToast.show(
            context: context,
            message: '⚠️ Rider declined your bid.',
            isError: true,
          );
        }
        // Clean up this listener — no longer needed
        _declineSubs[rideId]?.cancel();
        _declineSubs.remove(rideId);
      }
    }, onError: (error) {
      debugPrint('Error listening to ride declines: $error');
    });
  }

  Future<void> _placeBid(Map<String, dynamic> ride, int bidPrice) async {
    final provider = context.read<DriverProvider>();

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
        message: '⚠️ Maximum ${AppConstants.maxActiveBids} active bids reached.',
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
          'vehicleType': provider.profile?['vehicleType'] ?? 'auto',
          'vehicleNumber': provider.profile?['vehicleNumber'] ?? '',
          'driverImageUrl': provider.profile?['documents']?['selfieUrl'] ?? '',
          'vehicleImageUrl': provider.profile?['documents']?['vehicleUrl'] ?? '',
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
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                  24, 20, 24, MediaQuery.of(ctx).viewInsets.bottom + MediaQuery.of(ctx).padding.bottom + 20),
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
                  Text('Place Your Bid',
                      style: GoogleFonts.inter(
                          fontSize: 20, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(
                    '${ride['pickup']?['short_name']} → ${ride['drop']?['short_name']}',
                    style: GoogleFonts.inter(
                        fontSize: 14, color: AppTheme.text2),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${ride['distanceKm']} km ride · $distLabel away · ~$etaLabel pickup',
                    style: GoogleFonts.inter(
                        fontSize: 13, color: AppTheme.text3),
                  ),
                  const SizedBox(height: 12),
                  // Rider's bid reference
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                            border: Border.all(color: AppTheme.danger.withValues(alpha: 0.3)),
                          ),
                          child: const Icon(Icons.remove,
                              color: AppTheme.danger, size: 22),
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
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: AppTheme.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: AppTheme.success, width: 2),
                            ),
                            filled: true,
                            fillColor: AppTheme.bg,
                          ),
                          onChanged: (val) {
                            final parsed = int.tryParse(val);
                            if (parsed != null && parsed > 0) {
                              bidPrice = parsed;
                              if (parsed > maxBid) {
                                capWarning = 'Max counter price is ₹$maxBid (2× rider offer)';
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
                            border: Border.all(color: AppTheme.success.withValues(alpha: 0.3)),
                          ),
                          child: const Icon(Icons.add,
                              color: AppTheme.success, size: 22),
                        ),
                      ),
                    ],
                  ),
                  // Cap warning
                  if (capWarning != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: AppTheme.danger, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(capWarning!,
                                style: GoogleFonts.inter(fontSize: 12, color: AppTheme.danger, fontWeight: FontWeight.w600)),
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
                              final finalPrice = int.tryParse(bidController.text) ?? bidPrice;
                              if (finalPrice > maxBid) return;
                              Navigator.pop(ctx);
                              _placeBid(ride, finalPrice);
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: bidPrice > maxBid ? AppTheme.text3 : AppTheme.success,
                      ),
                      child: Text('Place Bid ₹$bidPrice',
                          style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700, fontSize: 16)),
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

    return Scaffold(
      drawer: _buildDrawer(context, provider),
      body: Stack(
        children: [
          // Map
          GoogleMap(
            style: lightMapStyle,
            // Top padding keeps the compass/north-reset button below the status bar
            padding: const EdgeInsets.only(top: 90),
            initialCameraPosition: CameraPosition(
              target: provider.lat != null
                  ? LatLng(provider.lat!, provider.lng!)
                  : const LatLng(17.385, 78.487),
              zoom: 14,
            ),
            onMapCreated: (controller) {
              _mapController = controller;
            },
            markers: {
              if (provider.lat != null && provider.isOnline)
                Marker(
                  markerId: const MarkerId('driver'),
                  position: LatLng(provider.lat!, provider.lng!),
                  icon: _getVehicleIcon(provider.profile?['vehicleType']),
                ),
              ..._buildRideMarkers(),
            },
          ),

          // Loading overlay
          if (_locating)
            Container(
              color: AppTheme.bg.withValues(alpha: 0.9),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(
                        color: AppTheme.primary),
                    const SizedBox(height: 16),
                    Text('Getting your location...',
                        style: GoogleFonts.inter(color: AppTheme.text2)),
                  ],
                ),
              ),
            ),

          // Top status bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
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
                      AppConstants.vehicleTypes[provider.profile?['vehicleType']]
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
                                fontWeight: FontWeight.w700, fontSize: 16),
                          ),
                          Text(
                            provider.isOnline
                                ? '🟢 Online'
                                : '⚫ Offline',
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
                        icon: const Icon(Icons.menu, color: AppTheme.text3, size: 24),
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
      markers.add(Marker(
        markerId: MarkerId(rideId),
        position: LatLng(lat, lng),
        icon: icon,
        onTap: () {
          _ridePageController.animateToPage(
            i,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOut,
          );
        },
      ));
    }
    return markers;
  }

  Widget _buildBottomPanel(DriverProvider provider) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          0, 12, 0, MediaQuery.of(context).padding.bottom + 8),
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
                        fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const Spacer(),
                  Text('${_nearbyRides.length} rides',
                      style: GoogleFonts.inter(
                          color: AppTheme.text3, fontSize: 13)),
                ],
              ),
            ),

            if (_nearbyRides.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
                child: Text(
                  provider.lat == null
                      ? 'Getting your location...'
                      : 'No rides nearby. Stay online!',
                  style: GoogleFonts.inter(color: AppTheme.text3, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              )
            else
              // ── Snap Carousel ──────────────────────────────────────
              SizedBox(
                height: 255,
                child: PageView.builder(
                  controller: _ridePageController,
                  itemCount: _nearbyRides.length,
                  onPageChanged: (index) {
                    setState(() => _focusedRideIndex = index);
                    // Rebuild markers so active glow switches correctly
                    _rebuildFareBubbles();
                    // Animate map camera to the focused pickup
                    final ride = _nearbyRides[index];
                    final lat = (ride['pickup']?['lat'] as num?)?.toDouble();
                    final lng = (ride['pickup']?['lng'] as num?)?.toDouble();
                    if (lat != null && lng != null) {
                      _mapController?.animateCamera(
                        CameraUpdate.newLatLngZoom(LatLng(lat, lng), 15),
                      );
                    }
                  },
                  itemBuilder: (context, index) {
                    final ride = _nearbyRides[index];
                    final distMeters = (ride['distance'] as double);
                    final distLabel = distMeters < 1000
                        ? '${distMeters.toInt()}m'
                        : '${(distMeters / 1000).toStringAsFixed(1)} km';
                    final etaMin =
                        ((distMeters / 1000) / AppConstants.avgSpeedKmh * 60)
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
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              color: AppTheme.bg,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                  color: isBidded
                                      ? AppTheme.primary
                                      : isFocused
                                          ? AppTheme.border
                                          : AppTheme.border.withValues(alpha: 0.5),
                                  width: isBidded ? 2 : 1),
                              boxShadow: isFocused
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.18),
                                        blurRadius: 16,
                                        offset: const Offset(0, 6),
                                      )
                                    ]
                                  : [],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                              // Card header — fare + distance
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 14, 16, 10),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(children: [
                                          Text(
                                            'Ride ${index + 1} of ${_nearbyRides.length}',
                                            style: GoogleFonts.inter(
                                                fontSize: 11,
                                                color: AppTheme.text3,
                                                fontWeight: FontWeight.w600),
                                          ),
                                          const SizedBox(width: 8),
                                          const Icon(Icons.timer_outlined,
                                              size: 13, color: AppTheme.primary),
                                          const SizedBox(width: 3),
                                          RideTimerText(
                                            createdAtMs:
                                                (ride['createdAt'] as num?)
                                                        ?.toInt() ??
                                                    DateTime.now()
                                                        .millisecondsSinceEpoch,
                                            onExpired: () {
                                              if (mounted) {
                                                setState(() {
                                                  _nearbyRides.removeWhere(
                                                      (r) => r['id'] == rideId);
                                                });
                                                _rebuildFareBubbles();
                                              }
                                            },
                                          ),
                                        ]),
                                        const SizedBox(height: 4),
                                        Row(children: [
                                          const Icon(Icons.electric_rickshaw,
                                              color: AppTheme.primary, size: 18),
                                          const SizedBox(width: 5),
                                          Text(
                                            '${ride['distanceKm']} km',
                                            style: GoogleFonts.inter(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 17),
                                          ),
                                        ]),
                                      ],
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          isBidded ? 'Your Bid' : 'Offered',
                                          style: GoogleFonts.inter(
                                              fontSize: 11,
                                              color: isBidded
                                                  ? AppTheme.primary
                                                  : AppTheme.text3,
                                              fontWeight: FontWeight.w600),
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
                                                  : AppTheme.success),
                                        ),
                                        if (isBidded &&
                                            _biddedRides[rideId] !=
                                                ride['riderBid'])
                                          Text(
                                            'Offer: ₹${ride['riderBid']}',
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              color: AppTheme.text3,
                                              decoration:
                                                  TextDecoration.lineThrough,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              // ETA chip
                              Builder(builder: (_) {
                                final chipColor = etaMin < 3
                                    ? AppTheme.success
                                    : etaMin <= 7
                                        ? AppTheme.warning
                                        : AppTheme.danger;
                                return Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: chipColor.withValues(alpha: 0.07),
                                    border: Border.symmetric(
                                        horizontal: BorderSide(
                                            color: AppTheme.border)),
                                  ),
                                  child: Row(children: [
                                    Icon(Icons.near_me_rounded,
                                        size: 13, color: chipColor),
                                    const SizedBox(width: 5),
                                    Text(
                                      '$distLabel to pickup  ·  ~$etaLabel',
                                      style: GoogleFonts.inter(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: chipColor),
                                    ),
                                  ]),
                                );
                              }),

                              // Route preview
                              Padding(
                                padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Column(children: [
                                      const Icon(Icons.my_location,
                                          color: AppTheme.primary, size: 18),
                                      Container(
                                          width: 2,
                                          height: 20,
                                          margin: const EdgeInsets.symmetric(
                                              vertical: 3),
                                          color: AppTheme.border),
                                      const Icon(Icons.location_on,
                                          color: AppTheme.danger, size: 18),
                                    ]),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            ride['pickup']?['short_name'] ??
                                                ride['pickup']?['display_name'] ??
                                                'Pickup',
                                            style: GoogleFonts.inter(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 14),
                                          Text(
                                            ride['drop']?['short_name'] ??
                                                ride['drop']?['display_name'] ??
                                                'Drop',
                                            style: GoogleFonts.inter(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
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
                                  color: AppTheme.surface,
                                  borderRadius: BorderRadius.vertical(
                                      bottom: Radius.circular(18)),
                                ),
                                child: isBidded
                                    ? Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 12),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            const Icon(Icons.check_circle,
                                                color: AppTheme.success,
                                                size: 18),
                                            const SizedBox(width: 6),
                                            Text(
                                              'Bid placed · waiting for rider',
                                              style: GoogleFonts.inter(
                                                  color: AppTheme.success,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 13),
                                            ),
                                          ],
                                        ),
                                      )
                                    : Row(children: [
                                        Expanded(
                                          child: InkWell(
                                            onTap: () {
                                              setState(() {
                                                _declinedRides.add(rideId);
                                                _nearbyRides.removeWhere(
                                                    (r) => r['id'] == rideId);
                                                if (_focusedRideIndex >=
                                                    _nearbyRides.length) {
                                                  _focusedRideIndex =
                                                      (_nearbyRides.length - 1)
                                                          .clamp(0, 999);
                                                }
                                              });
                                              _rebuildFareBubbles();
                                            },
                                            borderRadius: const BorderRadius.only(
                                                bottomLeft: Radius.circular(18)),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 14),
                                              decoration: BoxDecoration(
                                                color: AppTheme.danger
                                                    .withValues(alpha: 0.1),
                                                borderRadius:
                                                    const BorderRadius.only(
                                                        bottomLeft:
                                                            Radius.circular(18)),
                                              ),
                                              alignment: Alignment.center,
                                              child: Text('Decline',
                                                  style: GoogleFonts.inter(
                                                      color: AppTheme.danger,
                                                      fontWeight: FontWeight.w700,
                                                      fontSize: 15)),
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: InkWell(
                                            onTap: () => _showBidDialog(ride),
                                            borderRadius: const BorderRadius.only(
                                                bottomRight:
                                                    Radius.circular(18)),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 14),
                                              decoration: BoxDecoration(
                                                color: AppTheme.primary
                                                    .withValues(alpha: 0.1),
                                                borderRadius:
                                                    const BorderRadius.only(
                                                        bottomRight:
                                                            Radius.circular(18)),
                                              ),
                                              alignment: Alignment.center,
                                              child: Text('Place Bid',
                                                  style: GoogleFonts.inter(
                                                      color: AppTheme.primary,
                                                      fontWeight: FontWeight.w700,
                                                      fontSize: 15)),
                                            ),
                                          ),
                                        ),
                                      ]),
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
    );
  }

  Widget _buildDrawer(BuildContext context, DriverProvider provider) {
    return Drawer(
      backgroundColor: AppTheme.surface,
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(color: AppTheme.bg),
            accountName: Text(
              provider.profile?['name'] ?? 'Driver',
              style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppTheme.text),
            ),
            accountEmail: Text(
              provider.profile?['phone'] ?? '',
              style: GoogleFonts.inter(color: AppTheme.text2),
            ),
            currentAccountPicture: CircleAvatar(
              backgroundColor: AppTheme.primary,
              backgroundImage: provider.profile?['documents']?['selfieUrl'] != null
                  ? NetworkImage(provider.profile!['documents']['selfieUrl'])
                  : null,
              child: provider.profile?['documents']?['selfieUrl'] == null
                  ? const Icon(Icons.person, color: Colors.white)
                  : null,
            ),
          ),
          // Earnings Progress Stub
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.bg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Today\'s Goal', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                    Text('₹450 / ₹1000', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppTheme.success)),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: const LinearProgressIndicator(
                    value: 0.45,
                    backgroundColor: AppTheme.border,
                    color: AppTheme.success,
                    minHeight: 8,
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.history, color: AppTheme.text),
            title: Text('Earnings History', style: GoogleFonts.inter(color: AppTheme.text)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const RideEarningsHistoryScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.person, color: AppTheme.text),
            title: Text('My Profile', style: GoogleFonts.inter(color: AppTheme.text)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.card_membership, color: AppTheme.text),
            title: Text('Subscription', style: GoogleFonts.inter(color: AppTheme.text)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SubscriptionScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.support_agent, color: AppTheme.text),
            title: Text('Support', style: GoogleFonts.inter(color: AppTheme.text)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SupportScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings, color: AppTheme.text),
            title: Text('Settings', style: GoogleFonts.inter(color: AppTheme.text)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
            },
          ),
          const Spacer(),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: AppTheme.danger),
            title: Text('Log Out', style: GoogleFonts.inter(color: AppTheme.danger, fontWeight: FontWeight.bold)),
            onTap: () async {
              provider.setOnline(false);
              await FirebaseFirestore.instance
                  .collection('drivers')
                  .doc(FirebaseAuth.instance.currentUser!.uid)
                  .update({
                    'isOnline': false,
                    'driverState': 'OFFLINE',
                  });
              await FirebaseAuth.instance.signOut();
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

  const RideTimerText({super.key, required this.createdAtMs, required this.onExpired});

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
