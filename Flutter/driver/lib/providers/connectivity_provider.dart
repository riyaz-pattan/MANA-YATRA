// lib/providers/connectivity_provider.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityProvider extends ChangeNotifier {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  List<ConnectivityResult> _results = [ConnectivityResult.none];

  bool get isOffline =>
      _results.isEmpty || _results.every((r) => r == ConnectivityResult.none);

  ConnectivityProvider() {
    _init();
  }

  Future<void> _init() async {
    // Get the initial state
    _results = await _connectivity.checkConnectivity();
    notifyListeners();

    // Subscribe to changes
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      _results = results;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
