import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mana_yatra_driver/repositories/ride_repository.dart';
import 'package:mana_yatra_driver/services/sync_engine.dart';
import 'package:mana_yatra_driver/models/queue_item.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MockSyncEngine extends Mock implements SyncEngine {}
class MockFirebaseFirestore extends Mock implements FirebaseFirestore {}

class FakeQueueItem extends Fake implements QueueItem {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeQueueItem());
  });

  group('FirestoreRideRepository (Driver)', () {
    late FirestoreRideRepository repository;
    late MockSyncEngine mockSyncEngine;
    late MockFirebaseFirestore mockFirestore;

    setUp(() {
      mockSyncEngine = MockSyncEngine();
      mockFirestore = MockFirebaseFirestore();
      repository = FirestoreRideRepository(
        syncEngine: mockSyncEngine,
        firestore: mockFirestore,
      );
    });

    test('placeBid enqueues correct QueueItem', () async {
      // Arrange
      when(() => mockSyncEngine.enqueue(any())).thenAnswer((_) async {});
      final payload = {'rideId': 'r1', 'driverId': 'd1', 'amount': 150.0};

      // Act
      await repository.placeBid(payload, 'op_111');

      // Assert
      final captured = verify(() => mockSyncEngine.enqueue(captureAny())).captured;
      expect(captured.length, 1);
      final item = captured.first as QueueItem;
      
      expect(item.id, 'op_111');
      expect(item.type, 'PLACE_BID');
      expect(item.payload, payload);
    });

    test('completeRide enqueues correct QueueItem', () async {
      // Arrange
      when(() => mockSyncEngine.enqueue(any())).thenAnswer((_) async {});

      // Act
      await repository.completeRide('r1', 'op_222');

      // Assert
      final captured = verify(() => mockSyncEngine.enqueue(captureAny())).captured;
      expect(captured.length, 1);
      final item = captured.first as QueueItem;
      
      expect(item.id, 'op_222');
      expect(item.type, 'COMPLETE_RIDE');
      expect(item.payload, {'rideId': 'r1'});
    });
  });
}
