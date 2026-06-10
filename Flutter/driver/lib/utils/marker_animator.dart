import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MarkerAnimator {
  final TickerProvider vsync;
  AnimationController? _controller;
  LatLng? _startPos;
  LatLng? _endPos;
  double _startHeading = 0;
  double _endHeading = 0;
  LatLng? _currentPos;
  double _currentHeading = 0;
  
  MarkerAnimator({required this.vsync});
  
  LatLng? get currentPos => _currentPos;
  double get currentHeading => _currentHeading;
  
  void animate({
    required LatLng newPos,
    required double newHeading,
    required VoidCallback onUpdate,
  }) {
    if (_currentPos == null) {
      _currentPos = newPos;
      _currentHeading = newHeading;
      onUpdate();
      return;
    }
    
    _startPos = _currentPos;
    _endPos = newPos;
    _startHeading = _currentHeading;
    _endHeading = newHeading;
    
    // Calculate shortest rotation path
    double diff = (_endHeading - _startHeading) % 360;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    _endHeading = _startHeading + diff;
    
    _controller?.dispose();
    _controller = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 3000), // 3 seconds interpolation
    )..addListener(() {
        final t = _controller!.value;
        final lat = lerpDouble(_startPos!.latitude, _endPos!.latitude, t)!;
        final lng = lerpDouble(_startPos!.longitude, _endPos!.longitude, t)!;
        _currentPos = LatLng(lat, lng);
        _currentHeading = lerpDouble(_startHeading, _endHeading, t)!;
        onUpdate();
      });
      
    _controller!.forward();
  }
  
  void dispose() {
    _controller?.dispose();
  }
}
