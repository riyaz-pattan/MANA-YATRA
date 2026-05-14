// lib/widgets/connectivity_banner.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/connectivity_provider.dart';

/// Wraps any child widget with a slim, animated offline/online banner.
/// Drop this at the top level in main.dart around your MaterialApp's home.
class ConnectivityBanner extends StatefulWidget {
  final Widget child;
  const ConnectivityBanner({super.key, required this.child});

  @override
  State<ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends State<ConnectivityBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _heightAnim;

  // Track previous offline state to show the "Back Online" flash
  bool _wasOffline = false;
  bool _showBackOnline = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _heightAnim = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleConnectivityChange(bool isOffline) {
    if (isOffline) {
      _wasOffline = true;
      _showBackOnline = false;
      _controller.forward();
    } else {
      if (_wasOffline) {
        // Briefly show "Back Online" then slide up
        setState(() => _showBackOnline = true);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            _controller.reverse();
            setState(() {
              _showBackOnline = false;
              _wasOffline = false;
            });
          }
        });
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectivityProvider>(
      builder: (context, connectivity, _) {
        // Trigger animation whenever status changes
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handleConnectivityChange(connectivity.isOffline);
        });

        return Column(
          children: [
            SizeTransition(
              sizeFactor: _heightAnim,
              axisAlignment: -1,
              child: _showBackOnline
                  ? _OnlineBanner()
                  : _OfflineBanner(),
            ),
            Expanded(child: widget.child),
          ],
        );
      },
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFEF4444),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      child: SafeArea(
        bottom: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.wifi_off_rounded, color: Colors.white, size: 15),
            SizedBox(width: 8),
            Text(
              'No Internet Connection',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnlineBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFF10B981),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      child: SafeArea(
        bottom: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.wifi_rounded, color: Colors.white, size: 15),
            SizedBox(width: 8),
            Text(
              'Back Online',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
