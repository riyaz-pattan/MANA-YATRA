// lib/screens/active_ride_screen.dart
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:confetti/confetti.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../utils/custom_toast.dart';
import 'package:geolocator/geolocator.dart';
import '../config/theme.dart';
import '../services/google_maps_service.dart';
import '../utils/map_style.dart';
import '../utils/map_utils.dart';
import '../utils/marker_animator.dart';

import 'package:cloud_functions/cloud_functions.dart';
import '../providers/driver_provider.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'dashboard_screen.dart';
import '../main.dart';
import '../widgets/swipe_action.dart';
import '../utils/skeleton.dart';

class ActiveRideScreen extends StatefulWidget {
  final String rideId;
  const ActiveRideScreen({super.key, required this.rideId});
  @override
  State<ActiveRideScreen> createState() => _ActiveRideScreenState();
}

class _ActiveRideScreenState extends State<ActiveRideScreen> with TickerProviderStateMixin {
  GoogleMapController? _mapController;
  Map<String, dynamic>? _ride;
  StreamSubscription? _rideListener;
  bool _updating = false;
  bool _cameraFitted = false;
  BitmapDescriptor? _pickupGreenPin;
  bool _arrivedAtPickup = false;
  // ignore: prefer_final_fields
  int _swipeArrivedCounter = 0;
  BitmapDescriptor? _vehicleIcon;
  BitmapDescriptor? _dropDot;
  List<LatLng> _approachRouteCoords = [];
  bool _isFetchingApproach = false;
  LatLng? _lastDriverPos;
  // ignore: unused_field
  String _driverProximity = '';
  DriverProvider? _driverProvider;
  ConfettiController? _confettiController;
  int _swipeCompleteCounter = 0;
  int _swipeCancelCounter = 0;
  late final MarkerAnimator _driverAnimator;

  // OTP verification
  final List<TextEditingController> _otpControllers = List.generate(
    4,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _otpFocusNodes = List.generate(4, (_) => FocusNode());

  @override
  void initState() {
    super.initState();
    _driverAnimator = MarkerAnimator(vsync: this);
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
    _driverAnimator.dispose();
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
            
            if (_vehicleIcon == null) {
              final vType = data['vehicleType'] ?? 'auto';
              _loadVehicleIcon(vType);
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

      _driverAnimator.animate(
        newPos: newPos,
        newHeading: _driverProvider?.heading ?? 0.0,
        onUpdate: () {
          if (mounted) setState(() {});
        },
      );

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
      _pickupGreenPin = await MapUtils.createDotMarker(color: const Color(0xFF10B981));
      _dropDot = await MapUtils.createDotMarker(color: const Color(0xFFEA4335));
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _loadVehicleIcon(String type) async {
    final path = 'assets/images/map_icons/$type.png';
    try {
      const config = ImageConfiguration(size: Size(48, 48));
      _vehicleIcon = await BitmapDescriptor.asset(config, path);
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
      LatLng? targetPos = _lastDriverPos;
      if (targetPos == null && _ride!['pickup'] != null) {
        targetPos = LatLng(
          (_ride!['pickup']['lat'] as num).toDouble(),
          (_ride!['pickup']['lng'] as num).toDouble(),
        );
      }

      if (targetPos != null) {
        _mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: targetPos,
              zoom: 17.5,
              bearing: 0.0,
            ),
          ),
        );
        _cameraFitted = true;
      }
      return;
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

  /// Notify rider via FCM that driver has arrived at pickup
  Future<void> _notifyRiderDriverArrived() async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('notifyDriverArrived');
      await callable.call({'rideId': widget.rideId});
    } catch (e) {
      debugPrint('Error notifying rider of arrival: $e');
      // Non-critical — rider will still see driverArrived in Firestore
    }
  }

  Future<void> _completeRide({BuildContext? sheetContext}) async {
    if (_updating) return;
    setState(() => _updating = true);
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const Center(
        child: CircularProgressIndicator(color: AppTheme.success),
      ),
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

      if (!mounted) return;
      
      // ✅ Clear active ride so SmartTracker reverts to discovery mode
      // and driver becomes visible to riders again.
      context.read<DriverProvider>().setActiveRide(null);

      Navigator.pop(context); // pop the loading dialog

      if (sheetContext != null && sheetContext.mounted) {
        Navigator.pop(sheetContext); // pop the bottom sheet
      }
    } catch (e) {
      debugPrint('Error completing ride: $e');
      if (mounted) {
        Navigator.pop(context); // pop the loading dialog
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

  Future<void> _showCompleteConfirmation() async {
    final paymentMethod = _ride!['paymentMethod'] as String? ?? 'Cash';
    final isUpi = paymentMethod.toUpperCase() == 'UPI';
    final finalPrice = _ride!['finalPrice'] ?? _ride!['riderBid'] ?? 0;
    
    final provider = context.read<DriverProvider>();
    final upiId = provider.profile?['upiId'] as String? ?? '';
    final driverName = provider.profile?['name'] as String? ?? 'Driver';
    
    // NPCI standard UPI intent link
    final upiLink = 'upi://pay?pa=$upiId&pn=${Uri.encodeComponent(driverName)}&am=$finalPrice&cu=INR';

    setState(() => _updating = true);
    try {
      await FirebaseFirestore.instance.collection('rides').doc(_ride!['id']).update({
        'status': 'payment_pending',
      });
    } catch (e) {
      debugPrint('Error updating to payment_pending: $e');
    }
    if (mounted) setState(() => _updating = false);

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.only(
            left: 20, right: 20, top: 16, bottom: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 24),
              
              if (isUpi && upiId.isNotEmpty) ...[
                Text('Scan to Pay', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.text)),
                const SizedBox(height: 4),
                Text('₹$finalPrice via UPI', style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w900, color: AppTheme.success)),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 20, spreadRadius: -5),
                    ],
                  ),
                  child: QrImageView(
                    data: upiLink,
                    version: QrVersions.auto,
                    size: 200.0,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Show this to the rider. Wait for payment confirmation on your bank app before completing.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 14, color: AppTheme.warning, fontWeight: FontWeight.w600),
                ),
              ] else ...[
                const Icon(Icons.payments_rounded, color: AppTheme.success, size: 60),
                const SizedBox(height: 16),
                Text('Collect Cash', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.text)),
                const SizedBox(height: 8),
                Text(
                  'Please collect ₹$finalPrice from the rider.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 18, color: AppTheme.success, fontWeight: FontWeight.w700),
                ),
              ],
              
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    _completeRide(sheetContext: sheetContext);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.success,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    isUpi ? '✅ Payment Received & Complete' : '✅ Cash Received & Complete',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    setState(() {
                      _swipeCompleteCounter++;
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.grey[300]!),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15, color: Colors.grey[700]),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ).whenComplete(() {
      // If the sheet was dismissed by tapping outside or swiping down, reset the slider
      setState(() {
        _swipeCompleteCounter++;
      });
    });
  }

  Future<void> _cancelRide({BuildContext? sheetContext}) async {
    if (_updating) return;
    setState(() => _updating = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const Center(
        child: CircularProgressIndicator(color: AppTheme.danger),
      ),
    );

    try {
      final callable = FirebaseFunctions.instance.httpsCallable('cancelRide');
      await callable.call({'rideId': widget.rideId, 'role': 'driver'});

      // Stop the foreground tracking service as the ride is cancelled
      try {
        await FlutterForegroundTask.stopService();
      } catch (e) {
        debugPrint('Error stopping foreground task: $e');
      }

      // ✅ Only reset local state on successful write
      if (!mounted) return;
      Navigator.pop(context); // pop the loading dialog

      if (sheetContext != null && sheetContext.mounted) {
        Navigator.pop(sheetContext); // pop the bottom sheet
      }
      
      context.read<DriverProvider>().setActiveRide(null);
    } catch (e) {
      debugPrint('Error cancelling ride: $e');
      if (mounted) {
        Navigator.pop(context); // pop the loading dialog
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

  void _showCancelConfirmation() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.only(
            left: 20, right: 20, top: 24, bottom: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 24),
              const Icon(Icons.cancel_outlined, color: AppTheme.danger, size: 60),
              const SizedBox(height: 16),
              Text('Cancel Ride?', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.text)),
              const SizedBox(height: 8),
              Text(
                'Are you sure you want to cancel this ride? This may affect your rating.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 15, color: Colors.grey[600]),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    _cancelRide(sheetContext: sheetContext);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.danger,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    'Yes, Cancel Ride',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    setState(() {
                      _swipeCancelCounter++;
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.grey[300]!),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    'No, Keep Ride',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15, color: Colors.grey[700]),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ).whenComplete(() {
      setState(() {
        _swipeCancelCounter++;
      });
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

    // Try to parse ride stats from Firestore
    final finalPrice = _ride?['finalPrice'] ?? _ride?['riderBid'] ?? 0;
    final distanceKm = _ride?['distanceKm'];
    // Prefer the actual elapsed time; fall back to the estimated duration
    final durationMin = _ride?['actualDurationMin'] ?? _ride?['durationMin'];

    final cancelledBy = _ride?['cancelledBy'];
    final cancelReasonDb = _ride?['cancelReason'];
    String cancelReason = 'The ride was cancelled.';
    if (cancelReasonDb == 'Admin Force Cancellation') {
      cancelReason = 'The ride was cancelled by the Admin.';
    } else if (cancelledBy == 'driver') {
      cancelReason = 'The ride was cancelled by you (Driver).';
    } else if (cancelledBy == 'rider') {
      cancelReason = 'The ride was cancelled by the Rider.';
    }

    return Container(
      color: AppTheme.bg,
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
                        : cancelReason,
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
                              'Gaman takes ZERO commission. Every rupee goes to you!',
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
                        // Clear the active ride state so we don't get stuck here
                        context.read<DriverProvider>().setActiveRide(null);
                        
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(
                            builder: (_) => const AuthGate(),
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
            color: AppTheme.bg,
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

  void _navigateToPickup() {
    if (_ride == null || _ride!['pickup'] == null) return;
    final lat = (_ride!['pickup']['lat'] as num).toDouble();
    final lng = (_ride!['pickup']['lng'] as num).toDouble();
    _launchNavigation(lat, lng);
  }

  void _navigateToDrop() {
    if (_ride == null || _ride!['drop'] == null) return;
    final lat = (_ride!['drop']['lat'] as num).toDouble();
    final lng = (_ride!['drop']['lng'] as num).toDouble();
    _launchNavigation(lat, lng);
  }

  Future<void> _launchNavigation(double lat, double lng) async {
    try {
      if (Platform.isAndroid) {
        final url = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
          return;
        }
      } else if (Platform.isIOS) {
        final googleMapsUrl = Uri.parse('comgooglemaps://?daddr=$lat,$lng&directionsmode=driving');
        if (await canLaunchUrl(googleMapsUrl)) {
          await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
          return;
        }
        // Fallback to Apple Maps
        final appleMapsUrl = Uri.parse('https://maps.apple.com/?daddr=$lat,$lng&dirflg=d');
        if (await canLaunchUrl(appleMapsUrl)) {
          await launchUrl(appleMapsUrl, mode: LaunchMode.externalApplication);
          return;
        }
      }

      // Web fallback
      final webUrl = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
      if (!await launchUrl(webUrl, mode: LaunchMode.externalApplication)) {
        if (mounted) {
          CustomToast.show(
            context: context,
            message: 'Could not open navigation',
            isError: true,
          );
        }
      }
    } catch (e) {
      debugPrint('Error launching navigation: $e');
      if (mounted) {
        CustomToast.show(
          context: context,
          message: 'Could not open navigation',
          isError: true,
        );
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
                  color: AppTheme.bg,
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
              top: 50,
              bottom: status == 'matched' ? 320 : 240,
            ),
            style: lightMapStyle,
            myLocationEnabled: false,
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
              _mapController?.setMapStyle(lightMapStyle);
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
                  icon: _pickupGreenPin ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
                  anchor: const Offset(0.5, 0.9),
                  zIndexInt: 1,
                ),

              if (_ride!['drop'] != null && status == 'started')
                Marker(
                  markerId: const MarkerId('drop'),
                  position: LatLng(
                    (_ride!['drop']['lat'] as num).toDouble(),
                    (_ride!['drop']['lng'] as num).toDouble(),
                  ),
                  icon: _dropDot ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                  anchor: const Offset(0.5, 0.9), // Anchor at the bottom of the stem
                ),
              // Show driver's vehicle marker instead of the blue dot
              if ((status == 'started' || status == 'matched') && _driverAnimator.currentPos != null)
                Marker(
                  markerId: const MarkerId('driver_vehicle'),
                  position: _driverAnimator.currentPos!,
                  rotation: _driverAnimator.currentHeading,
                  icon: _vehicleIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
                  anchor: const Offset(0.5, 0.5),
                  zIndexInt: 3,
                ),
            },
          ),

          // Bottom panel with floating navigate button — hidden when ride ends
          if (!isEndState)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Floating "Navigate to Pickup Location" button (Phase 1: navigating to pickup)
                  if (status == 'matched' && !_arrivedAtPickup)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: _navigateToPickup,
                          icon: const Icon(Icons.navigation_rounded, size: 20),
                          label: Text(
                            'Navigate to Pickup Location',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.success,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 6,
                            shadowColor: AppTheme.success.withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                    ),
                  // Floating "Navigate to Drop Location" button (Phase 3: ride started)
                  if (status == 'started')
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: _navigateToDrop,
                          icon: const Icon(Icons.navigation_rounded, size: 20),
                          label: Text(
                            'Navigate to Drop Location',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 6,
                            shadowColor: AppTheme.primary.withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                    ),
                  _buildBottomPanel(status),
                ],
              ),
            ),

          // Success / Cancellation Overlay
          if (isEndState) Positioned.fill(child: _buildEndScreen(status)),
        ],
      ),
    );
  }

  Widget _buildBottomPanel(String status) {
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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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



            // ── Phase 1: Navigate to Pickup ──
            if (status == 'matched' && !_arrivedAtPickup) ...[

              SwipeAction(
                key: ValueKey('arrived_$_swipeArrivedCounter'),
                text: 'Swipe: Arrived at Pickup',
                onSwipe: () {
                  setState(() => _arrivedAtPickup = true);
                  // Write arrival to Firestore so rider app detects it
                  FirebaseFirestore.instance.collection('rides').doc(widget.rideId).update({
                    'driverArrived': true,
                    'driverArrivedAt': FieldValue.serverTimestamp(),
                  });
                  // Send FCM notification to rider
                  _notifyRiderDriverArrived();
                },
                baseColor: AppTheme.success,
                activeColor: AppTheme.success,
              ),
              const SizedBox(height: 10),
              if (_ride!['riderPhone'] != null)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final phone = _ride!['riderPhone'];
                      final uri = Uri.parse('tel:$phone');
                      if (await canLaunchUrl(uri)) await launchUrl(uri);
                    },
                    icon: const Icon(Icons.phone, size: 16),
                    label: Text('Call Rider', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: AppTheme.border),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              if (_ride!['riderPhone'] != null) const SizedBox(height: 8),
              SwipeAction(
                key: ValueKey('cancel_p1_$_swipeCancelCounter'),
                text: 'Swipe to Cancel',
                onSwipe: () {
                  if (!_updating) _showCancelConfirmation();
                },
                baseColor: AppTheme.danger,
                activeColor: AppTheme.danger,
              ),
            ]

            // ── Phase 2: Verify Rider OTP ──
            else if (status == 'matched' && _arrivedAtPickup) ...[
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
              const SizedBox(height: 8),
              SwipeAction(
                key: ValueKey('cancel_p2_$_swipeCancelCounter'),
                text: 'Swipe to Cancel',
                onSwipe: () {
                  if (!_updating) _showCancelConfirmation();
                },
                baseColor: AppTheme.danger,
                activeColor: AppTheme.danger,
              ),
            ] else if (status == 'started' || status == 'payment_pending') ...[
              SwipeAction(
                key: ValueKey('complete_$_swipeCompleteCounter'),
                text: status == 'payment_pending' ? 'Swipe: View Payment Details' : 'Swipe to Complete',
                onSwipe: () {
                  if (!_updating) _showCompleteConfirmation();
                },
                baseColor: AppTheme.success,
                activeColor: AppTheme.success,
              ),
              const SizedBox(height: 8),
              SwipeAction(
                key: ValueKey('cancel_p3_$_swipeCancelCounter'),
                text: 'Swipe to Cancel',
                onSwipe: () {
                  if (!_updating) _showCancelConfirmation();
                },
                baseColor: AppTheme.danger,
                activeColor: AppTheme.danger,
              ),
            ],

          ],
        ),
        ),
        ),
      ),
    );
  }
}
