import 'package:flutter/material.dart';
import '../config/theme.dart';
import 'home_screen.dart';
import 'ride_history_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';
import 'package:provider/provider.dart';
import '../services/sync_engine.dart';
import '../widgets/premium_retry_button.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  bool _isBooking = false;

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  void _handleBookingState(bool isBooking) {
    if (_isBooking != isBooking) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _isBooking = isBooking;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      HomeScreen(onBookingStateChanged: _handleBookingState),
      const RideHistoryScreen(),
      const ProfileScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex,
            children: pages,
          ),
          Consumer<SyncEngine>(
            builder: (ctx, syncEngine, _) {
              if (!syncEngine.hasFailedItems) return const SizedBox.shrink();
              return Positioned(
                top: MediaQuery.of(context).padding.top + 16,
                left: 0,
                right: 0,
                child: Center(
                  child: PremiumRetryButton(
                    onRetry: () {
                      syncEngine.forceRetry();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Retrying connection...')),
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ],
      ),
      bottomNavigationBar: _isBooking
          ? null
          : BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: _onTabTapped,
              selectedItemColor: AppTheme.primary,
              unselectedItemColor: Colors.grey,
              showUnselectedLabels: true,
              type: BottomNavigationBarType.fixed,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.home_outlined),
                  activeIcon: Icon(Icons.home),
                  label: 'Ride',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.history_outlined),
                  activeIcon: Icon(Icons.history),
                  label: 'History',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.person_outline),
                  activeIcon: Icon(Icons.person),
                  label: 'Profile',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.settings_outlined),
                  activeIcon: Icon(Icons.settings),
                  label: 'Settings',
                ),
              ],
            ),
    );
  }
}
