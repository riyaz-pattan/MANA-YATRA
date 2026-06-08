import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:flutter_map/flutter_map.dart' as fmap;
import 'package:latlong2/latlong.dart' as latlong2;
import '../../utils/marker_utils.dart';
import '../../core/theme/app_theme.dart';

class RideLiveMap extends StatefulWidget {
  final Map<String, dynamic> rideData;
  final bool isDark;

  const RideLiveMap({super.key, required this.rideData, required this.isDark});

  @override
  State<RideLiveMap> createState() => _RideLiveMapState();
}

class _RideLiveMapState extends State<RideLiveMap> {
  gmaps.GoogleMapController? _gmapController;
  final fmap.MapController _fmapController = fmap.MapController();

  gmaps.BitmapDescriptor? _gmapPickupDot;
  gmaps.BitmapDescriptor? _gmapDropDot;
  gmaps.BitmapDescriptor? _gmapCarIcon;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _loadGmapMarkers();
    }
  }

  @override
  void didUpdateWidget(covariant RideLiveMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!kIsWeb && (_gmapPickupDot == null || _gmapDropDot == null)) {
      _loadGmapMarkers();
    } else {
      _updateMapBounds();
    }
  }

  Future<void> _loadGmapMarkers() async {
    _gmapPickupDot = await MarkerGenerator.createDotMarker(color: Colors.green);
    _gmapDropDot = await MarkerGenerator.createDotMarker(color: AppTheme.danger);
    if (mounted) setState(() {});
    _updateMapBounds();
  }

  void _updateMapBounds() {
    final pLat = widget.rideData['pickup']?['lat'];
    final pLng = widget.rideData['pickup']?['lng'];
    final dLat = widget.rideData['drop']?['lat'];
    final dLng = widget.rideData['drop']?['lng'];

    if (pLat != null && pLng != null && dLat != null && dLng != null) {
      if (kIsWeb) {
        // flutter_map
        final bounds = fmap.LatLngBounds.fromPoints([
          latlong2.LatLng(pLat, pLng),
          latlong2.LatLng(dLat, dLng),
        ]);
        try {
          _fmapController.fitCamera(fmap.CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50)));
        } catch (_) {}
      } else {
        // google_maps_flutter
        if (_gmapController != null) {
          final bounds = gmaps.LatLngBounds(
            southwest: gmaps.LatLng(
              pLat < dLat ? pLat : dLat,
              pLng < dLng ? pLng : dLng,
            ),
            northeast: gmaps.LatLng(
              pLat > dLat ? pLat : dLat,
              pLng > dLng ? pLng : dLng,
            ),
          );
          _gmapController!.animateCamera(gmaps.CameraUpdate.newLatLngBounds(bounds, 50));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pLat = widget.rideData['pickup']?['lat'];
    final pLng = widget.rideData['pickup']?['lng'];
    final dLat = widget.rideData['drop']?['lat'];
    final dLng = widget.rideData['drop']?['lng'];

    if (pLat == null || pLng == null || dLat == null || dLng == null) {
      return Center(
        child: Text('Coordinates unavailable for this ride.', style: TextStyle(color: widget.isDark ? AppTheme.darkText2 : AppTheme.lightText2)),
      );
    }

    if (kIsWeb) {
      return fmap.FlutterMap(
        mapController: _fmapController,
        options: fmap.MapOptions(
          initialCenter: latlong2.LatLng((pLat + dLat) / 2, (pLng + dLng) / 2),
          initialZoom: 13,
        ),
        children: [
          fmap.TileLayer(
            urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
            subdomains: const ['a', 'b', 'c'],
          ),
          fmap.MarkerLayer(
            markers: [
              fmap.Marker(
                point: latlong2.LatLng(pLat, pLng),
                width: 30,
                height: 45,
                alignment: Alignment.topCenter,
                child: CustomPaint(painter: _DotPainter(color: Colors.green)),
              ),
              fmap.Marker(
                point: latlong2.LatLng(dLat, dLng),
                width: 30,
                height: 45,
                alignment: Alignment.topCenter,
                child: CustomPaint(painter: _DotPainter(color: AppTheme.danger)),
              ),
            ],
          ),
        ],
      );
    } else {
      if (_gmapPickupDot == null || _gmapDropDot == null) {
        return const Center(child: CircularProgressIndicator());
      }

      Set<gmaps.Marker> markers = {
        gmaps.Marker(
          markerId: const gmaps.MarkerId('pickup'),
          position: gmaps.LatLng(pLat, pLng),
          icon: _gmapPickupDot!,
          anchor: const Offset(0.5, 0.8), // Align stem to point
        ),
        gmaps.Marker(
          markerId: const gmaps.MarkerId('drop'),
          position: gmaps.LatLng(dLat, dLng),
          icon: _gmapDropDot!,
          anchor: const Offset(0.5, 0.8),
        ),
      };

      return gmaps.GoogleMap(
        initialCameraPosition: gmaps.CameraPosition(
          target: gmaps.LatLng((pLat + dLat) / 2, (pLng + dLng) / 2),
          zoom: 13,
        ),
        markers: markers,
        onMapCreated: (ctrl) {
          _gmapController = ctrl;
          // Google Maps defaults to light mode; no styling needed for light mode
          _updateMapBounds();
        },
      );
    }
  }
}

class _DotPainter extends CustomPainter {
  final Color color;

  _DotPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final double radius = size.width * 0.4;
    final double stemHeight = size.height * 0.4;
    final Offset center = Offset(size.width / 2, size.height * 0.35);

    // 1. Draw shadow
    final Paint shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    
    final Path shadowPath = Path()
      ..addOval(Rect.fromCircle(center: center.translate(0, 1), radius: radius))
      ..moveTo(center.dx - 1.0, center.dy + radius)
      ..lineTo(center.dx + 1.0, center.dy + radius)
      ..lineTo(center.dx, center.dy + radius + stemHeight + 0.5)
      ..close();
    canvas.drawPath(shadowPath, shadowPaint);

    // 2. Draw the stem (pinpoint line)
    final Paint stemPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
      
    canvas.drawLine(
      Offset(center.dx, center.dy + radius - 1),
      Offset(center.dx, center.dy + radius + stemHeight),
      stemPaint
    );

    // 3. Draw thin white outer border circle
    final Paint borderPaint = Paint()..color = Colors.white;
    canvas.drawCircle(center, radius, borderPaint);

    // 4. Draw hollow colored circle (the ring)
    final Paint ringPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius - 2, ringPaint);

    // 5. Draw white center dot
    final Paint centerDotPaint = Paint()..color = Colors.white;
    canvas.drawCircle(center, radius * 0.4, centerDotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
