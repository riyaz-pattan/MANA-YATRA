import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mocktail/mocktail.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:mana_yatra_rider/providers/ride_provider.dart';
import 'package:mana_yatra_rider/providers/connectivity_provider.dart';
import 'package:mana_yatra_rider/screens/home_screen.dart';
import 'package:mana_yatra_rider/config/theme.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'mock_firebase.dart';

class MockRideProvider extends Mock implements RideProvider {}
class MockConnectivityProvider extends Mock implements ConnectivityProvider {}

void main() {
  setupFirebaseAuthMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  testWidgets('HomeScreen mounts correctly and displays location text', (WidgetTester tester) async {
    final mockRideProvider = MockRideProvider();
    final mockConnectivityProvider = MockConnectivityProvider();
    
    when(() => mockRideProvider.pickup).thenReturn(null);
    when(() => mockRideProvider.drop).thenReturn(null);
    when(() => mockRideProvider.route).thenReturn(null);
    when(() => mockRideProvider.vehicleType).thenReturn('auto');
    when(() => mockRideProvider.activeRide).thenReturn(null);
    when(() => mockRideProvider.user).thenReturn(null);
    when(() => mockRideProvider.authLoading).thenReturn(false);

    when(() => mockConnectivityProvider.isOffline).thenReturn(false);
    when(() => mockConnectivityProvider.isFirebaseReachable).thenReturn(true);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<RideProvider>.value(value: mockRideProvider),
          ChangeNotifierProvider<ConnectivityProvider>.value(value: mockConnectivityProvider),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: HomeScreen(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    
    expect(find.text('Where are you going?'), findsWidgets);
  });
}
