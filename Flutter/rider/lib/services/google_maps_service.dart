import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class LocationResult {
  final String placeId;
  final String displayName;
  final String shortName;
  final double lat;
  final double lng;

  LocationResult({
    required this.placeId,
    required this.displayName,
    required this.shortName,
    required this.lat,
    required this.lng,
  });

  Map<String, dynamic> toMap() => {
        'display_name': displayName,
        'short_name': shortName,
        'lat': lat,
        'lng': lng,
      };
}

class RouteInfo {
  final double distanceKm;
  final int durationMin;
  final List<LatLng> coordinates;

  RouteInfo({
    required this.distanceKm,
    required this.durationMin,
    required this.coordinates,
  });
}

class GoogleMapsService {
  static String get _apiKey => dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

  static Future<List<LocationResult>> searchLocation(String query) async {
    if (_apiKey.isEmpty) {
      debugPrint('[GoogleMapsService] API key is empty! Check .env file.');
      return [];
    }
    
    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/textsearch/json?query=${Uri.encodeComponent(query)}&key=$_apiKey',
      );
      final res = await http.get(uri);
      if (res.statusCode != 200) {
        debugPrint('[GoogleMapsService] Places API HTTP ${res.statusCode}: ${res.body}');
        return [];
      }
      
      final data = jsonDecode(res.body);
      if (data['status'] != 'OK') {
        debugPrint('[GoogleMapsService] Places API error: ${data['status']} - ${data['error_message'] ?? 'no message'}');
        return [];
      }
      
      final results = data['results'] as List;
      return results.map((r) {
        final geometry = r['geometry']['location'];
        return LocationResult(
          placeId: r['place_id']?.toString() ?? '',
          displayName: r['formatted_address'] ?? r['name'] ?? '',
          shortName: r['name'] ?? '',
          lat: geometry['lat']?.toDouble() ?? 0.0,
          lng: geometry['lng']?.toDouble() ?? 0.0,
        );
      }).toList();
    } catch (e) {
      debugPrint('Error searching location: $e');
      return [];
    }
  }

  static Future<LocationResult?> reverseGeocode(double lat, double lng) async {
    if (_apiKey.isEmpty) {
      debugPrint('[GoogleMapsService] API key is empty! Check .env file.');
      return null;
    }

    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lng&key=$_apiKey',
      );
      final res = await http.get(uri);
      if (res.statusCode != 200) {
        debugPrint('[GoogleMapsService] Geocoding API HTTP ${res.statusCode}: ${res.body}');
        return null;
      }
      
      final data = jsonDecode(res.body);
      if (data['status'] != 'OK' || (data['results'] as List).isEmpty) {
        debugPrint('[GoogleMapsService] Geocoding API error: ${data['status']} - ${data['error_message'] ?? 'no message'}');
        return null;
      }
      
      final r = data['results'][0];
      final geometry = r['geometry']['location'];
      
      // Extract a meaningful short name (skip Plus Codes)
      String shortName = '';
      if (r['address_components'] != null) {
        final components = r['address_components'] as List;
        // Priority order for a readable short name
        const priorityTypes = [
          'point_of_interest',
          'establishment',
          'premise',
          'neighborhood',
          'sublocality_level_2',
          'sublocality_level_1',
          'sublocality',
          'route',
          'locality',
        ];

        for (final type in priorityTypes) {
          for (final comp in components) {
            final types = (comp['types'] as List).cast<String>();
            if (types.contains(type) && !types.contains('plus_code')) {
              shortName = comp['long_name'] ?? comp['short_name'] ?? '';
              break;
            }
          }
          if (shortName.isNotEmpty) break;
        }
      }

      // Fallback: use a truncated formatted address
      if (shortName.isEmpty) {
        final formatted = r['formatted_address'] ?? '';
        // Take the first meaningful part before the comma
        shortName = formatted.split(',').first.trim();
        if (shortName.isEmpty) shortName = 'Unknown location';
      }

      return LocationResult(
        placeId: r['place_id']?.toString() ?? '',
        displayName: r['formatted_address'] ?? '',
        shortName: shortName,
        lat: geometry['lat']?.toDouble() ?? lat,
        lng: geometry['lng']?.toDouble() ?? lng,
      );
    } catch (e) {
      debugPrint('Error reverse geocoding: $e');
      return null;
    }
  }

  static Future<RouteInfo?> getRoute(
    double fromLat,
    double fromLng,
    double toLat,
    double toLng,
  ) async {
    if (_apiKey.isEmpty) {
      debugPrint('[GoogleMapsService] API key is empty! Check .env file.');
      return null;
    }

    try {
      // Use Routes API (New) — POST request
      final uri = Uri.parse(
        'https://routes.googleapis.com/directions/v2:computeRoutes',
      );

      final body = jsonEncode({
        'origin': {
          'location': {
            'latLng': {'latitude': fromLat, 'longitude': fromLng}
          }
        },
        'destination': {
          'location': {
            'latLng': {'latitude': toLat, 'longitude': toLng}
          }
        },
        'travelMode': 'DRIVE',
        'computeAlternativeRoutes': false,
        'routeModifiers': {
          'avoidTolls': false,
          'avoidHighways': false,
          'avoidFerries': false,
        },
      });

      final res = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': _apiKey,
          'X-Goog-FieldMask': 'routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline',
        },
        body: body,
      );

      if (res.statusCode != 200) {
        debugPrint('[GoogleMapsService] Routes API HTTP ${res.statusCode}: ${res.body}');
        return null;
      }

      final data = jsonDecode(res.body);
      
      if (data['routes'] == null || (data['routes'] as List).isEmpty) {
        debugPrint('[GoogleMapsService] Routes API returned no routes: ${res.body}');
        return null;
      }

      final route = data['routes'][0];

      // distanceMeters is an int
      final distanceMeters = route['distanceMeters'] as num;
      final distanceKm = distanceMeters / 1000.0;

      // duration is a string like "1234s"
      final durationStr = route['duration'] as String; // e.g. "600s"
      final durationSeconds = int.parse(durationStr.replaceAll('s', ''));
      final durationMin = (durationSeconds / 60.0).ceil();

      final encodedPolyline = route['polyline']['encodedPolyline'] as String;
      final polylinePoints = _decodePolyline(encodedPolyline);

      return RouteInfo(
        distanceKm: distanceKm,
        durationMin: durationMin,
        coordinates: polylinePoints,
      );
    } catch (e) {
      debugPrint('[GoogleMapsService] Error getting route: $e');
      return null;
    }
  }

  // Helper method to decode Google Maps polyline string
  static List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> poly = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      poly.add(LatLng((lat / 1E5).toDouble(), (lng / 1E5).toDouble()));
    }
    return poly;
  }
}
