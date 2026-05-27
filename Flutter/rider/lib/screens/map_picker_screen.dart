// lib/screens/map_picker_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../config/theme.dart';
import '../services/google_maps_service.dart';
import '../utils/map_style.dart';

/// Full-screen map picker for selecting a location by dragging.
/// Returns a [LocationResult] via Navigator.pop when confirmed.
class MapPickerScreen extends StatefulWidget {
  /// Optional initial position to center the map on.
  final LatLng? initialPosition;

  /// Label shown at the top — "Select Pickup" or "Select Drop-off".
  final String title;

  const MapPickerScreen({
    super.key,
    this.initialPosition,
    this.title = 'Select location',
  });

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  GoogleMapController? _mapController;
  LatLng? _center;
  LocationResult? _currentResult;
  bool _geocoding = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _center = widget.initialPosition ?? const LatLng(17.385, 78.487);
    // Geocode the initial position
    _geocodeCenter();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onCameraMove(CameraPosition pos) {
    _center = pos.target;
  }

  void _onCameraIdle() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      _geocodeCenter();
    });
  }

  Future<void> _geocodeCenter() async {
    if (_center == null) return;
    setState(() => _geocoding = true);
    final result = await GoogleMapsService.reverseGeocode(
      _center!.latitude,
      _center!.longitude,
    );
    if (mounted) {
      setState(() {
        _currentResult = result;
        _geocoding = false;
      });
    }
  }

  Future<void> _goToCurrentLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      final target = LatLng(pos.latitude, pos.longitude);
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(target, 16));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // ── Map ──
          GoogleMap(
            style: lightMapStyle,
            onMapCreated: (c) => _mapController = c,
            initialCameraPosition: CameraPosition(
              target: _center!,
              zoom: 16,
            ),
            onCameraMove: _onCameraMove,
            onCameraIdle: _onCameraIdle,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: true,
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 260, top: 40),
          ),

          // ── Center Pin ──
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 36),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Address label bubble
                  if (_currentResult != null && !_geocoding)
                    Container(
                      constraints: const BoxConstraints(maxWidth: 220),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 8),
                        ],
                      ),
                      child: Text(
                        _currentResult!.shortName,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: AppTheme.text,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (_geocoding)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 8),
                        ],
                      ),
                      child: const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
                      ),
                    ),
                  const SizedBox(height: 2),
                  // Custom styled pin
                  _buildCustomPin(),
                ],
              ),
            ),
          ),

          // ── Back button ──
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(left: 16, top: 12),
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.bg,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.arrow_back, color: AppTheme.text, size: 22),
                ),
              ),
            ),
          ),

          // ── My Location FAB ──
          Positioned(
            right: 16,
            bottom: MediaQuery.of(context).padding.bottom + 360,
            child: GestureDetector(
              onTap: _goToCurrentLocation,
              child: Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.bg,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: const Icon(Icons.my_location, color: AppTheme.info, size: 22),
              ),
            ),
          ),

          // ── Bottom Sheet ──
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                20, 24, 20, MediaQuery.of(context).padding.bottom + 16,
              ),
              decoration: BoxDecoration(
                color: AppTheme.bg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        widget.title,
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.text,
                        ),
                      ),
                      if (_currentResult != null)
                        GestureDetector(
                          onTap: _goToCurrentLocation,
                          child: Text(
                            'Reset',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.info,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Address card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.bg2,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            color: AppTheme.info.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.location_on_rounded, color: AppTheme.info, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _geocoding
                              ? Text(
                                  'Detecting location...',
                                  style: GoogleFonts.inter(color: AppTheme.text3, fontSize: 14),
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _currentResult?.shortName ?? 'Move the map to select',
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                        color: AppTheme.text,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (_currentResult?.displayName != null) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        _currentResult!.displayName,
                                        style: GoogleFonts.inter(
                                          color: AppTheme.text3,
                                          fontSize: 12,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ],
                                ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Confirm button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _currentResult == null || _geocoding
                          ? null
                          : () => Navigator.pop(context, _currentResult),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: AppTheme.surface2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'Confirm Location',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
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

  /// Custom blue location pin widget.
  Widget _buildCustomPin() {
    return SizedBox(
      width: 40,
      height: 50,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          // Pin body
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: AppTheme.info,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.info.withValues(alpha: 0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(Icons.location_on, color: Colors.white, size: 16),
          ),
          // Pin tail
          Positioned(
            bottom: 4,
            child: CustomPaint(
              size: const Size(12, 14),
              painter: _PinTailPainter(color: AppTheme.info),
            ),
          ),
        ],
      ),
    );
  }
}

/// Paints the triangular tail of the map pin.
class _PinTailPainter extends CustomPainter {
  final Color color;
  _PinTailPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
