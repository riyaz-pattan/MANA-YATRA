import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fmap;
import 'package:latlong2/latlong.dart' as latlong2;
import '../../core/theme/app_theme.dart';

class SOSLiveMap extends StatelessWidget {
  final double lat;
  final double lng;
  final bool isDark;

  const SOSLiveMap({super.key, required this.lat, required this.lng, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return fmap.FlutterMap(
      options: fmap.MapOptions(
        initialCenter: latlong2.LatLng(lat, lng),
        initialZoom: 15,
      ),
      children: [
        fmap.TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.gaman.admin',
          // Forced light mode tiles on both web and mobile
        ),
        fmap.MarkerLayer(
          markers: [
            fmap.Marker(
              point: latlong2.LatLng(lat, lng),
              width: 40,
              height: 40,
              child: const Icon(Icons.location_on, color: AppTheme.danger, size: 40),
            ),
          ],
        ),
      ],
    );
  }
}
