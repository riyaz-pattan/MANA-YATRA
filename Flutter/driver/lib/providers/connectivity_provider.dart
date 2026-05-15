// lib/providers/connectivity_provider.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_database/firebase_database.dart';

/// Monitors both device connectivity (WiFi/Cellular toggle) and actual
/// Firebase reachability via RTDB's /.info/connected node.
///
/// A device can report WiFi "on" but have no internet (e.g., connected to
/// a router with no WAN). This provider catches that case by checking
/// the real Firebase connection state.
class ConnectivityProvider extends ChangeNotifier {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  StreamSubscription? _firebaseSub;

  List<ConnectivityResult> _results = [ConnectivityResult.none];
  bool _isFirebaseConnected = false;

  /// True when the device reports no network adapter active.
  bool get isDeviceOffline =>
      _results.isEmpty || _results.every((r) => r == ConnectivityResult.none);

  /// True when Firebase RTDB confirms we cannot reach the backend,
  /// OR when the device itself has no network.
  bool get isOffline => isDeviceOffline || !_isFirebaseConnected;

  /// True only when Firebase RTDB confirms actual connectivity.
  bool get isFirebaseReachable => _isFirebaseConnected;

  ConnectivityProvider() {
    _init();
  }

  Future<void> _init() async {
    // Get the initial device connectivity state
    _results = await _connectivity.checkConnectivity();
    notifyListeners();

    // Subscribe to device connectivity changes
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      _results = results;
      notifyListeners();
    });

    // Subscribe to Firebase RTDB /.info/connected for real health check
    _firebaseSub = FirebaseDatabase.instance
        .ref('.info/connected')
        .onValue
        .listen((event) {
      _isFirebaseConnected = event.snapshot.value as bool? ?? false;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _firebaseSub?.cancel();
    super.dispose();
  }
}
