import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mana_yatra_rider/services/sync_engine.dart';
import 'package:mana_yatra_rider/services/action_queue_service.dart';
import 'package:mana_yatra_rider/models/queue_item.dart';

class MockActionQueueService extends Mock implements ActionQueueService {}

class FakeQueueItem extends Fake implements QueueItem {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeQueueItem());
  });

  group('SyncEngine', () {
    late SyncEngine engine;
    late MockActionQueueService mockQueue;

    setUp(() {
      mockQueue = MockActionQueueService();
      engine = SyncEngine(mockQueue);
    });

    test('enqueue calls queue.enqueue', () async {
      // Arrange
      final item = QueueItem(id: 'op_1', type: 'TEST', payload: {});
      when(() => mockQueue.enqueue(any())).thenAnswer((_) async {});
      when(() => mockQueue.getPendingItems()).thenReturn([]);

      // Act
      await engine.enqueue(item);

      // Assert
      verify(() => mockQueue.enqueue(item)).called(1);
    });
    
    test('pendingCount returns value from queue', () {
      // Arrange
      when(() => mockQueue.pendingCount).thenReturn(3);

      // Act
      final count = engine.pendingCount;

      // Assert
      expect(count, 3);
    });
  });
}
