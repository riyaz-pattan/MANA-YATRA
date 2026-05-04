// lib/screens/dashboard_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../config/constants.dart';
import '../utils/map_style.dart';
import '../providers/driver_provider.dart';
import 'active_ride_screen.dart';
import 'ride_earnings_history_screen.dart';
import 'subscription_screen.dart';
import 'profile_screen.dart';
import 'support_screen.dart';
import 'settings_screen.dart';
import '../utils/custom_toast.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  GoogleMapController? _mapController;
  BitmapDescriptor? _autoIcon;
  BitmapDescriptor? _bikeIcon;
  BitmapDescriptor? _carIcon;
  List<Map<String, dynamic>> _nearbyRides = [];
  bool _loadingRides = false;
  bool _bidding = false;
  StreamSubscription? _rideListener;
  Timer? _pollTimer;
  final Map<String, int> _biddedRides = {}; // Maps rideId to bid amount

  bool _locating = true;

  @override
  void initState() {
    super.initState();
    _checkNotificationPermission();
    _getCurrentLocation();
    _listenForActiveRide();
    _loadCustomMarkers();
  }

  Future<void> _loadCustomMarkers() async {
    const config = ImageConfiguration(size: Size(48, 48));
    _autoIcon = await BitmapDescriptor.asset(config, 'assets/images/map_icons/auto.png');
    _bikeIcon = await BitmapDescriptor.asset(config, 'assets/images/map_icons/bike.png');
    _carIcon = await BitmapDescriptor.asset(config, 'assets/images/map_icons/car.png');
    if (mounted) setState(() {});
  }

  BitmapDescriptor _getVehicleIcon(String? vehicleType) {
    if (vehicleType == 'bike' && _bikeIcon != null) return _bikeIcon!;
    if (vehicleType == 'car' && _carIcon != null) return _carIcon!;
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
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          CustomToast.show(
            context: context,
            message: 'Please enable location services',
            isError: true,
          );
          setState(() => _locating = false);
        }
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          CustomToast.show(
            context: context,
            message: 'Location permission denied. Please enable in settings.',
            isError: true,
          );
          setState(() => _locating = false);
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
          setState(() => _locating = false);
        }
        return;
      }

      if (mounted) {
        final provider = context.read<DriverProvider>();
        provider.updateLocation(pos.latitude, pos.longitude);
        _mapController?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 15));
        setState(() => _locating = false);
        
        // If online, start polling rides
        if (provider.isOnline) {
          _startPollingRides();
        }
      }
    } catch (e) {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  void dispose() {
    _rideListener?.cancel();
    _pollTimer?.cancel();
    super.dispose();
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
        final ride = snap.docs.first;
        final data = ride.data();
        data['id'] = ride.id;
        context.read<DriverProvider>().setActiveRide(data);
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ActiveRideScreen(rideId: ride.id),
          ),
        );
      }
    });
  }

  Future<void> _toggleOnline() async {
    final provider = context.read<DriverProvider>();
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final newState = !provider.isOnline;

    await FirebaseFirestore.instance
        .collection('drivers')
        .doc(uid)
        .update({'isOnline': newState});

    provider.setOnline(newState);

    if (newState) {
      _startPollingRides();
    } else {
      _pollTimer?.cancel();
      setState(() => _nearbyRides = []);
    }
  }

  void _startPollingRides() {
    _loadNearbyRides();
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _loadNearbyRides();
    });
  }

  Future<void> _loadNearbyRides() async {
    final provider = context.read<DriverProvider>();
    if (provider.lat == null) return;

    setState(() => _loadingRides = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      
      // Fetch user's pending bids
      if (uid != null) {
        final bidsSnap = await FirebaseFirestore.instance
            .collection('bids')
            .where('driverId', isEqualTo: uid)
            .where('status', isEqualTo: 'pending')
            .get();
        
        _biddedRides.clear();
        for (final doc in bidsSnap.docs) {
          _biddedRides[doc['rideId'] as String] = doc['price'] as int;
        }
      }

      // Get driver's vehicle type for filtering
      final driverVehicleType = provider.profile?['vehicleType'] as String? ?? 'auto';

      final snap = await FirebaseFirestore.instance
          .collection('rides')
          .where('status', whereIn: ['searching', 'bidding'])
          .orderBy('createdAt', descending: true)
          .limit(40)
          .get();

      final rides = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        data['id'] = doc.id;

        // ── Vehicle Type Filter ──
        // Only show rides that match this driver's vehicle type
        final rideVehicleType = (data['vehicleType'] as String?) ?? 'auto';
        if (rideVehicleType != driverVehicleType) continue;

        // Filter by distance
        if (data['pickup']?['lat'] != null) {
          final dist = Geolocator.distanceBetween(
            provider.lat!,
            provider.lng!,
            (data['pickup']['lat'] as num).toDouble(),
            (data['pickup']['lng'] as num).toDouble(),
          );
          if (dist < AppConstants.searchRadiusMeters) {
            data['distance'] = dist;
            rides.add(data);
          }
        }
      }
      rides.sort((a, b) =>
          (a['distance'] as double).compareTo(b['distance'] as double));

      setState(() {
        _nearbyRides = rides;
        _loadingRides = false;
      });
    } catch (e) {
      setState(() => _loadingRides = false);
    }
  }

  Future<void> _placeBid(Map<String, dynamic> ride, int bidPrice) async {
    setState(() => _bidding = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final provider = context.read<DriverProvider>();

      await FirebaseFirestore.instance.collection('bids').add({
        'rideId': ride['id'],
        'riderId': ride['riderId'],
        'driverId': uid,
        'driverName': provider.profile?['name'] ?? 'Driver',
        'driverPhone': provider.profile?['phone'] ?? '',
        'vehicleType': provider.profile?['vehicleType'] ?? 'auto',
        'vehicleNumber': provider.profile?['vehicleNumber'] ?? '',
        'price': bidPrice,
        'driverLat': provider.lat,
        'driverLng': provider.lng,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Update ride status to bidding
      await FirebaseFirestore.instance
          .collection('rides')
          .doc(ride['id'])
          .update({'status': 'bidding'});
      
      setState(() {
        _biddedRides[ride['id']] = bidPrice;
      });

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
    int bidPrice = ride['riderBid'] ?? 80;
    final bidController = TextEditingController(text: bidPrice.toString());

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
                      'Rider offered ₹${ride['riderBid']}',
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
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _bidding
                          ? null
                          : () {
                              final finalPrice = int.tryParse(bidController.text) ?? bidPrice;
                              Navigator.pop(ctx);
                              _placeBid(ride, finalPrice);
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.success,
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
              // Nearby ride markers
              ..._nearbyRides.map((ride) {
                return Marker(
                  markerId: MarkerId(ride['id'] ?? ride.hashCode.toString()),
                  position: LatLng(
                    (ride['pickup']['lat'] as num).toDouble(),
                    (ride['pickup']['lng'] as num).toDouble(),
                  ),
                  icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
                );
              }),
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

  Widget _buildBottomPanel(DriverProvider provider) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).padding.bottom + 16),
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
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppTheme.text3,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Nearby rides
          if (provider.isOnline) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  'Nearby Rides',
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const Spacer(),
                if (_loadingRides)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.primary),
                  )
                else
                  Text('${_nearbyRides.length} rides',
                      style: GoogleFonts.inter(
                          color: AppTheme.text3, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 8),
            if (_nearbyRides.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                child: Text(
                  provider.lat == null
                      ? 'Getting your location...'
                      : 'No rides nearby. Stay online!',
                  style: GoogleFonts.inter(
                      color: AppTheme.text3, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              )
            else
              ...(_nearbyRides.take(5).map((ride) {
                final distMeters = (ride['distance'] as double);
                final distLabel = distMeters < 1000
                    ? '${distMeters.toInt()}m'
                    : '${(distMeters / 1000).toStringAsFixed(1)} km';
                final etaMin = ((distMeters / 1000) / AppConstants.avgSpeedKmh * 60).ceil();
                final etaLabel = etaMin < 1 ? '<1 min' : '$etaMin min';
                final rideId = ride['id'] as String;
                final isBidded = _biddedRides.containsKey(rideId);
                final bidAmount = _biddedRides[rideId];

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.bg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isBidded ? AppTheme.primary : AppTheme.border, width: isBidded ? 2 : 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Ride Header (Fare & Distance)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Ride Request',
                                  style: GoogleFonts.inter(fontSize: 12, color: AppTheme.text3, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.directions_car, color: AppTheme.primary, size: 20),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${ride['distanceKm']} km',
                                      style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 18),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'Offered Fare',
                                  style: GoogleFonts.inter(fontSize: 12, color: AppTheme.text3, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '₹${ride['riderBid']}',
                                  style: GoogleFonts.inter(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.success),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: AppTheme.border),
                      // Locations
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Column(
                                  children: [
                                    const Icon(Icons.my_location, color: AppTheme.primary, size: 20),
                                    Container(
                                      width: 2,
                                      height: 24,
                                      color: AppTheme.border,
                                      margin: const EdgeInsets.symmetric(vertical: 4),
                                    ),
                                    const Icon(Icons.location_on, color: AppTheme.danger, size: 20),
                                  ],
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        ride['pickup']?['display_name'] ?? ride['pickup']?['short_name'] ?? 'Pickup',
                                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '$distLabel away (~$etaLabel)',
                                        style: GoogleFonts.inter(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        ride['drop']?['display_name'] ?? ride['drop']?['short_name'] ?? 'Drop',
                                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Action Button
                      Container(
                        width: double.infinity,
                        decoration: const BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                        ),
                        child: isBidded
                            ? Padding(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.check_circle, color: AppTheme.success, size: 20),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Bid placed, waiting for rider to accept',
                                      style: GoogleFonts.inter(
                                          color: AppTheme.success,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14),
                                    ),
                                  ],
                                ),
                              )
                            : InkWell(
                                onTap: () => _showBidDialog(ride),
                                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary.withValues(alpha: 0.1),
                                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    'Place Bid',
                                    style: GoogleFonts.inter(
                                        color: AppTheme.primary,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16),
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                );
              })),
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
                  .update({'isOnline': false});
              await FirebaseAuth.instance.signOut();
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
