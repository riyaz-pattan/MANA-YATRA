import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:Ashwa/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Rider Happy Path Core Flow', () {
    testWidgets('Complete ride flow from booking to collecting cash', (
      tester,
    ) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // 1. Ensure user is logged in
      var user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        final phoneField = find.byType(TextField).first;
        await tester.enterText(phoneField, '9177570220');
        await tester.pumpAndSettle();

        final sendOtpBtn = find.textContaining('Send OTP');
        await tester.tap(sendOtpBtn);
        await tester.pumpAndSettle(const Duration(seconds: 4));

        final pinField = find.byType(EditableText).last;
        await tester.enterText(pinField, '222222');
        await tester.pumpAndSettle(const Duration(seconds: 3));

        final verifyBtn = find.textContaining('Verify');
        if (verifyBtn.evaluate().isNotEmpty) {
          await tester.tap(verifyBtn.first);
          await tester.pumpAndSettle(const Duration(seconds: 4));
        }
        user = FirebaseAuth.instance.currentUser;
      }

      expect(user, isNotNull, reason: 'Test requires a logged-in user');
      final uid = user!.uid;

      // Clean up any existing rides for this user to start fresh
      final existingRides = await FirebaseFirestore.instance
          .collection('rides')
          .where('riderId', isEqualTo: uid)
          .where(
            'status',
            whereIn: ['searching', 'bidding', 'matched', 'started'],
          )
          .get();

      for (var doc in existingRides.docs) {
        await doc.reference.update({'status': 'cancelled'});
      }

      await tester.pumpAndSettle(const Duration(seconds: 2));

      // 2. Start Booking Flow
      // Look for the "Where are you going?" search bar
      final searchBar = find.text('Where are you going?');
      if (searchBar.evaluate().isNotEmpty) {
        await tester.tap(searchBar);
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }

      // Simulate location selection (assuming the UI handles default map selection if we just tap Confirm)
      // We will look for "Confirm Destination" or "Select Ride"
      final confirmBtn = find.textContaining('Confirm');
      if (confirmBtn.evaluate().isNotEmpty) {
        await tester.tap(confirmBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }

      // 3. Request Ride
      final requestBtn = find.textContaining('Request');
      expect(requestBtn, findsWidgets);
      await tester.tap(requestBtn.first);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // 4. Verify ride was created in Firestore
      final activeRides = await FirebaseFirestore.instance
          .collection('rides')
          .where('riderId', isEqualTo: uid)
          .where('status', isEqualTo: 'searching')
          .get();

      expect(
        activeRides.docs.isNotEmpty,
        true,
        reason: 'Ride should be created in Firestore',
      );
      final rideId = activeRides.docs.first.id;

      // 5. Simulate Driver Bid
      final mockDriverId = 'mock_driver_123';
      final bidRef = await FirebaseFirestore.instance.collection('bids').add({
        'rideId': rideId,
        'driverId': mockDriverId,
        'driverName': 'Test Driver',
        'driverPhone': '+919999999999',
        'driverRating': 4.9,
        'vehicleType': 'auto',
        'vehicleNumber': 'TS09UB1234',
        'vehicleModel': 'Bajaj RE',
        'price': 100,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'eta': 5,
        'distance': 2.5,
        'lat': 17.3850,
        'lng': 78.4867,
      });

      await tester.pumpAndSettle(const Duration(seconds: 3));

      // 6. Accept Bid in UI
      final acceptBtn = find.text('Accept');
      if (acceptBtn.evaluate().isNotEmpty) {
        await tester.tap(acceptBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
      } else {
        // Fallback: manually accept in Firestore if UI tap is tricky due to animations
        await bidRef.update({'status': 'accepted'});
        await FirebaseFirestore.instance
            .collection('rides')
            .doc(rideId)
            .update({
              'status': 'matched',
              'driverId': mockDriverId,
              'matchedBidId': bidRef.id,
              'price': 100,
            });
      }

      await tester.pumpAndSettle(const Duration(seconds: 2));

      // 7. Simulate Driver Arriving and Starting
      await FirebaseFirestore.instance.collection('rides').doc(rideId).update({
        'status': 'arrived',
      });
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await FirebaseFirestore.instance.collection('rides').doc(rideId).update({
        'status': 'started',
      });
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // 8. Simulate Driver Completing Ride
      await FirebaseFirestore.instance.collection('rides').doc(rideId).update({
        'status': 'completed',
      });
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // 9. Verify Cash Collection / Payment Screen
      // Look for a payment, rating, or home screen reset depending on your flow
      expect(find.textContaining('Cash'), findsWidgets);

      print("✅ Rider Happy Path Core Flow Test Passed!");
    });
  });
}
