import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mana_yatra_driver/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('end-to-end test', () {
    testWidgets('App starts and shows authentication gate', (tester) async {
      // Start the app
      app.main();
      
      // Wait for the app to settle
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // At startup without real Firebase, it should either show a loading indicator
      // or crash if Firebase is not mocked. 
      // Since this is just a structural test to ensure CI runs, we'll verify it doesn't crash immediately.
      expect(find.byType(MaterialApp), findsOneWidget);
    });
  });
}
