import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mana_yatra_rider/repositories/ride_repository.dart';
import 'package:mana_yatra_rider/services/sync_engine.dart';
import 'package:mana_yatra_rider/models/queue_item.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MockSyncEngine extends Mock implements SyncEngine {}
class MockFirebaseFirestore extends Mock implements FirebaseFirestore {}

class FakeQueueItem extends Fake implements QueueItem {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeQueueItem());
  });

  group('FirestoreRideRepository (Rider)', () {
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

    test('acceptBid enqueues correct QueueItem', () async {
      // Arrange
      when(() => mockSyncEngine.enqueue(any())).thenAnswer((_) async {});

      // Act
      await repository.acceptBid('ride_123', 'bid_456', 'op_789');

      // Assert
      final captured = verify(() => mockSyncEngine.enqueue(captureAny())).captured;
      expect(captured.length, 1);
      final item = captured.first as QueueItem;
      
      expect(item.id, 'op_789');
      expect(item.type, 'ACCEPT_BID');
      expect(item.payload, {
        'rideId': 'ride_123',
        'bidId': 'bid_456',
        'operationId': 'op_789',
      });
    });

    test('cancelRide enqueues correct QueueItem', () async {
      // Arrange
      when(() => mockSyncEngine.enqueue(any())).thenAnswer((_) async {});

      // Act
      await repository.cancelRide('ride_123', 'op_789', reason: 'test_reason');

      // Assert
      final captured = verify(() => mockSyncEngine.enqueue(captureAny())).captured;
      expect(captured.length, 1);
      final item = captured.first as QueueItem;
      
      expect(item.id, 'op_789');
      expect(item.type, 'CANCEL_RIDE');
      expect(item.payload, {
        'rideId': 'ride_123',
        'reason': 'test_reason',
        'operationId': 'op_789',
      });
    });
  });
}
