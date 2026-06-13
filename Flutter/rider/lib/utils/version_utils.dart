import 'dart:math';

/// Helper to compare two semantic version strings (e.g., "1.0.5" vs "1.2.0")
/// Returns:
///   -1 if v1 < v2
///    1 if v1 > v2
///    0 if v1 == v2
int compareVersions(String v1, String v2) {
  final v1Parts = v1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  final v2Parts = v2.split('.').map((e) => int.tryParse(e) ?? 0).toList();

  final length = max(v1Parts.length, v2Parts.length);
  for (var i = 0; i < length; i++) {
    final p1 = i < v1Parts.length ? v1Parts[i] : 0;
    final p2 = i < v2Parts.length ? v2Parts[i] : 0;
    if (p1 < p2) return -1;
    if (p1 > p2) return 1;
  }
  return 0;
}
