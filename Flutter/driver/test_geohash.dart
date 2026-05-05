import 'package:dart_geohash/dart_geohash.dart';

void main() {
  final hasher = GeoHasher();
  // Usually Hyderabad is ~ 17.385, 78.487
  print('lat, lng -> ${hasher.encode(17.385, 78.487)}');
  print('lng, lat -> ${hasher.encode(78.487, 17.385)}');
}
