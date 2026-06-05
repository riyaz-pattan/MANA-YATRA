import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart' as fmap;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart' as ll;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/providers/dashboard_provider.dart';

class DashboardLiveMap extends ConsumerWidget {
  const DashboardLiveMap({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mapState = ref.watch(liveMapProvider);

    return Container(
      height: 400,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          mapState.when(
            data: (drivers) {
              if (!kIsWeb) {
                return _GoogleLiveMapWidget(drivers: drivers);
              }
              return fmap.FlutterMap(
                options: const fmap.MapOptions(
                  initialCenter: ll.LatLng(
                    17.3850,
                    78.4867,
                  ), // Default Center (Hyderabad)
                  initialZoom: 12.0,
                  minZoom: 3.0,
                  maxZoom: 18.0,
                ),
                children: [
                  fmap.TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.gaman.admin',
                  ),
                  fmap.MarkerLayer(
                    markers: drivers.map((driver) {
                      return fmap.Marker(
                        point: ll.LatLng(driver.lat, driver.lng),
                        width: 50,
                        height: 50,
                        child: GestureDetector(
                          onTap: () {
                            _showDriverProfile(context, driver);
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: driver.status == 'in_ride'
                                      ? Colors.blue.withOpacity(0.6)
                                      : driver.status == 'idle'
                                      ? Colors.green.withOpacity(0.6)
                                      : Colors.grey.withOpacity(0.6),
                                  blurRadius: 12,
                                  spreadRadius: 4,
                                ),
                              ],
                            ),
                            child: Transform.rotate(
                              angle: driver.heading * (3.14159 / 180),
                              child: Image.asset(
                                driver.vehicleType == 'bike'
                                    ? 'assets/images/map_icons/bike.png'
                                    : 'assets/images/map_icons/auto.png',
                                width: 40,
                                height: 40,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => Center(child: Text('Map Error: $err')),
          ),
          Positioned(
            top: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Row(
                children: [
                  Icon(Icons.map, color: Colors.blue, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Live Drivers',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDriverProfile(BuildContext context, DriverMapModel driver) {
    showDialog(
      context: context,
      builder: (context) => DriverProfileDialog(driver: driver),
    );
  }
}

class DriverProfileDialog extends StatefulWidget {
  final DriverMapModel driver;
  const DriverProfileDialog({super.key, required this.driver});

  @override
  State<DriverProfileDialog> createState() => _DriverProfileDialogState();
}

class _DriverProfileDialogState extends State<DriverProfileDialog> {
  Map<String, dynamic>? _rideData;
  Map<String, dynamic>? _riderData;
  bool _isLoadingRide = false;

  @override
  void initState() {
    super.initState();
    if (widget.driver.status == 'in_ride' && widget.driver.rideId != null) {
      _fetchRideDetails();
    }
  }

  Future<void> _fetchRideDetails() async {
    setState(() => _isLoadingRide = true);
    try {
      final rideDoc = await FirebaseFirestore.instance
          .collection('rides')
          .doc(widget.driver.rideId)
          .get();
      if (rideDoc.exists) {
        _rideData = rideDoc.data();
        final riderId = _rideData!['riderId'];
        if (riderId != null) {
          final riderDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(riderId)
              .get();
          if (riderDoc.exists) {
            _riderData = riderDoc.data();
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching ride: $e');
    }
    if (mounted) setState(() => _isLoadingRide = false);
  }

  @override
  Widget build(BuildContext context) {
    final driver = widget.driver;
    Color statusColor = Colors.grey;
    String statusText = 'Offline';
    if (driver.status == 'idle') {
      statusColor = Colors.green;
      statusText = 'Online (Idle)';
    } else if (driver.status == 'in_ride') {
      statusColor = Colors.blue;
      statusText = 'In Ride';
    }

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          CircleAvatar(
            backgroundColor: statusColor.withOpacity(0.1),
            child: Icon(Icons.person, color: statusColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  driver.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.phone, size: 20, color: Colors.grey),
                const SizedBox(width: 12),
                Text(driver.phone, style: const TextStyle(fontSize: 16)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  driver.vehicleType == 'bike'
                      ? Icons.two_wheeler
                      : Icons.local_taxi,
                  size: 20,
                  color: Colors.grey,
                ),
                const SizedBox(width: 12),
                Text(
                  'Vehicle: ${driver.vehicleType.toUpperCase()}',
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),

            // Active Ride Details
            if (driver.status == 'in_ride') ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: _isLoadingRide
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(8.0),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.directions_car,
                                color: Colors.blue,
                                size: 16,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'ACTIVE RIDE',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_riderData != null) ...[
                            Row(
                              children: [
                                Icon(
                                  Icons.person_outline,
                                  size: 16,
                                  color:
                                      Theme.of(
                                        context,
                                      ).iconTheme.color?.withOpacity(0.7) ??
                                      Colors.grey,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Rider: ${_riderData!['name'] ?? 'Unknown'}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.phone_android,
                                  size: 16,
                                  color:
                                      Theme.of(
                                        context,
                                      ).iconTheme.color?.withOpacity(0.7) ??
                                      Colors.grey,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${_riderData!['phone'] ?? 'Unknown'}',
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium?.color,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pop(
                                    context,
                                  ); // Close profile dialog
                                  _showFullRideDetails(
                                    context,
                                    _rideData,
                                    _riderData,
                                  );
                                },
                                icon: const Icon(Icons.receipt_long, size: 16),
                                label: const Text('View Ride Details'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                          ],
                          if (_rideData == null && _riderData == null)
                            const Text(
                              'Could not load ride details.',
                              style: TextStyle(color: Colors.red, fontSize: 12),
                            ),
                        ],
                      ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  void _showFullRideDetails(
    BuildContext context,
    Map<String, dynamic>? ride,
    Map<String, dynamic>? rider,
  ) {
    if (ride == null) return;

    final pickup = ride['pickup']?['address'] ?? 'Unknown';
    final drop = ride['drop']?['address'] ?? 'Unknown';
    final fare =
        ride['finalPrice']?.toString() ??
        ride['proposedPrice']?.toString() ??
        'N/A';
    final distance = ride['distance']?.toString() ?? 'Unknown';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ride Details'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (rider != null) ...[
                Text(
                  'Rider: ${rider['name'] ?? 'Unknown'}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text('Phone: ${rider['phone'] ?? 'Unknown'}'),
                const Divider(height: 24),
              ],
              const Text(
                'Pickup',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.my_location, color: Colors.green, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(pickup)),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Dropoff',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.location_on, color: Colors.red, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(drop)),
                ],
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total Fare',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '₹$fare',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.blue,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Distance', style: TextStyle(color: Colors.grey)),
                  Text(
                    '$distance km',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _GoogleLiveMapWidget extends StatefulWidget {
  final List<DriverMapModel> drivers;
  const _GoogleLiveMapWidget({required this.drivers});

  @override
  State<_GoogleLiveMapWidget> createState() => _GoogleLiveMapWidgetState();
}

class _GoogleLiveMapWidgetState extends State<_GoogleLiveMapWidget> {
  gmaps.GoogleMapController? _controller;
  gmaps.BitmapDescriptor? _autoIdle;
  gmaps.BitmapDescriptor? _autoInRide;
  gmaps.BitmapDescriptor? _autoOffline;
  gmaps.BitmapDescriptor? _bikeIdle;
  gmaps.BitmapDescriptor? _bikeInRide;
  gmaps.BitmapDescriptor? _bikeOffline;

  @override
  void initState() {
    super.initState();
    _loadCustomIcons();
  }

  Future<gmaps.BitmapDescriptor> _createMarkerImage(
    String assetPath,
    Color glowColor,
  ) async {
    final int canvasSize = 300;
    final double imageSize = 150.0;

    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);

    // Draw the glow layer
    final Paint glowPaint = Paint()
      ..color = glowColor
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 32.0);

    canvas.drawCircle(
      Offset(canvasSize / 2, canvasSize / 2),
      imageSize / 2,
      glowPaint,
    );

    // Load image
    final ByteData data = await rootBundle.load(assetPath);
    final ui.Codec codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
      targetWidth: imageSize.toInt(),
      targetHeight: imageSize.toInt(),
    );
    final ui.FrameInfo frameInfo = await codec.getNextFrame();
    final ui.Image image = frameInfo.image;

    // Draw the exact image over the glow
    canvas.drawImage(
      image,
      Offset((canvasSize - imageSize) / 2, (canvasSize - imageSize) / 2),
      Paint(),
    );

    final ui.Picture picture = pictureRecorder.endRecording();
    final ui.Image finalImage = await picture.toImage(canvasSize, canvasSize);
    final ByteData? byteData = await finalImage.toByteData(
      format: ui.ImageByteFormat.png,
    );

    return gmaps.BitmapDescriptor.fromBytes(byteData!.buffer.asUint8List());
  }

  Future<void> _loadCustomIcons() async {
    final autoIdle = await _createMarkerImage(
      'assets/images/map_icons/auto.png',
      Colors.green.withOpacity(0.6),
    );
    final autoInRide = await _createMarkerImage(
      'assets/images/map_icons/auto.png',
      Colors.blue.withOpacity(0.6),
    );
    final autoOffline = await _createMarkerImage(
      'assets/images/map_icons/auto.png',
      Colors.grey.withOpacity(0.6),
    );

    final bikeIdle = await _createMarkerImage(
      'assets/images/map_icons/bike.png',
      Colors.green.withOpacity(0.6),
    );
    final bikeInRide = await _createMarkerImage(
      'assets/images/map_icons/bike.png',
      Colors.blue.withOpacity(0.6),
    );
    final bikeOffline = await _createMarkerImage(
      'assets/images/map_icons/bike.png',
      Colors.grey.withOpacity(0.6),
    );

    if (mounted) {
      setState(() {
        _autoIdle = autoIdle;
        _autoInRide = autoInRide;
        _autoOffline = autoOffline;
        _bikeIdle = bikeIdle;
        _bikeInRide = bikeInRide;
        _bikeOffline = bikeOffline;
      });
    }
  }

  void _showDriverProfile(BuildContext context, DriverMapModel driver) {
    showDialog(
      context: context,
      builder: (context) => DriverProfileDialog(driver: driver),
    );
  }

  @override
  Widget build(BuildContext context) {
    final markers = widget.drivers.map((driver) {
      gmaps.BitmapDescriptor icon = gmaps.BitmapDescriptor.defaultMarker;

      if (driver.vehicleType == 'bike') {
        if (driver.status == 'in_ride' && _bikeInRide != null)
          icon = _bikeInRide!;
        else if (driver.status == 'idle' && _bikeIdle != null)
          icon = _bikeIdle!;
        else if (_bikeOffline != null)
          icon = _bikeOffline!;
      } else {
        if (driver.status == 'in_ride' && _autoInRide != null)
          icon = _autoInRide!;
        else if (driver.status == 'idle' && _autoIdle != null)
          icon = _autoIdle!;
        else if (_autoOffline != null)
          icon = _autoOffline!;
      }

      return gmaps.Marker(
        markerId: gmaps.MarkerId(driver.id),
        position: gmaps.LatLng(driver.lat, driver.lng),
        rotation: driver.heading,
        icon: icon,
        anchor: const Offset(0.5, 0.5),
        onTap: () => _showDriverProfile(context, driver),
      );
    }).toSet();

    return gmaps.GoogleMap(
      initialCameraPosition: const gmaps.CameraPosition(
        target: gmaps.LatLng(17.3850, 78.4867),
        zoom: 12.0,
      ),
      markers: markers,
      myLocationEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
        Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
      },
      onMapCreated: (controller) => _controller = controller,
    );
  }
}
