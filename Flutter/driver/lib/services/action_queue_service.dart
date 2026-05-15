// lib/services/action_queue_service.dart
import 'package:hive/hive.dart';
import '../models/queue_item.dart';

/// Persistent action queue backed by Hive.
/// Stores QueueItems as Maps in a single Hive box.
/// Thread-safe via Hive's built-in synchronization.
class ActionQueueService {
  static const String _boxName = 'action_queue';
  Box? _box;

  /// Open the Hive box. Must be called after Hive.initFlutter().
  Future<void> init() async {
    _box = await Hive.openBox(_boxName);
  }

  /// Enqueue a new action. Returns immediately — SyncEngine will process it.
  Future<void> enqueue(QueueItem item) async {
    await _box?.put(item.id, item.toMap());
  }

  /// Get all pending or failed items (sorted by creation time).
  List<QueueItem> getPendingItems() {
    if (_box == null) return [];
    final items = <QueueItem>[];
    for (final key in _box!.keys) {
      final raw = _box!.get(key);
      if (raw == null) continue;
      final item = QueueItem.fromMap(Map<dynamic, dynamic>.from(raw as Map));
      if (item.status == 'pending' || item.status == 'failed') {
        items.add(item);
      }
    }
    items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return items;
  }

  /// Update an existing item (e.g., increment retry count, change status).
  Future<void> update(QueueItem item) async {
    await _box?.put(item.id, item.toMap());
  }

  /// Remove an item from the queue (e.g., after successful delivery).
  Future<void> remove(String id) async {
    await _box?.delete(id);
  }

  /// Get a specific item by ID.
  QueueItem? getItem(String id) {
    final raw = _box?.get(id);
    if (raw == null) return null;
    return QueueItem.fromMap(Map<dynamic, dynamic>.from(raw as Map));
  }

  /// Number of items still waiting to be synced.
  int get pendingCount {
    if (_box == null) return 0;
    int count = 0;
    for (final key in _box!.keys) {
      final raw = _box!.get(key);
      if (raw == null) continue;
      final status = (raw as Map)['status'] as String?;
      if (status == 'pending' || status == 'failed') count++;
    }
    return count;
  }

  /// Wipe the entire queue (e.g. on logout).
  Future<void> clear() async {
    await _box?.clear();
  }
}
