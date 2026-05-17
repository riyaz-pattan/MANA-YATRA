// lib/services/sync_engine.dart
import 'dart:async';
import 'dart:math';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'action_queue_service.dart';
import '../models/queue_item.dart';

/// SyncEngine processes the ActionQueueService with exponential backoff.
///
/// It runs a periodic loop while the app is in the foreground.
/// When connectivity is restored (detected via RTDB /.info/connected),
/// it immediately processes pending items.
///
/// Max retries: 10 (after that, item is marked 'dead' and skipped).
/// Backoff: 2s → 4s → 8s → 16s → 32s → 60s (capped).
class SyncEngine extends ChangeNotifier {
  final ActionQueueService _queue;
  Timer? _processTimer;
  bool _processing = false;
  bool _isFirebaseReachable = false;
  StreamSubscription? _connectedSub;

  static const int _maxRetries = 10;
  static const Duration _processInterval = Duration(seconds: 5);

  SyncEngine(this._queue);

  /// Number of pending items (for UI badge display).
  int get pendingCount => _queue.pendingCount;

  /// Returns true if there are any items that have failed and are waiting for retry.
  bool get hasFailedItems => _queue.getPendingItems().any((item) => item.status == 'failed' || item.status == 'dead');

  /// Force an immediate retry of the queue, ignoring backoff.
  Future<void> forceRetry() async {
    final items = _queue.getPendingItems();
    for (final item in items) {
      if (item.status == 'failed' || item.status == 'dead') {
        item.status = 'pending';
        item.retryCount = 0;
        await _queue.update(item);
      }
    }
    await _processQueue(ignoreBackoff: true);
  }

  /// Whether the engine believes Firebase is reachable.
  bool get isFirebaseReachable => _isFirebaseReachable;

  /// Start the engine. Call once after Hive + Firebase are initialized.
  void start() {
    // Listen to Firebase RTDB /.info/connected for real connectivity check
    _connectedSub = FirebaseDatabase.instance
        .ref('.info/connected')
        .onValue
        .listen((event) {
      final connected = event.snapshot.value as bool? ?? false;
      final wasOffline = !_isFirebaseReachable;
      _isFirebaseReachable = connected;

      // If we just came online, immediately process the queue
      if (connected && wasOffline) {
        debugPrint('SyncEngine: Firebase reachable — flushing queue');
        _processQueue();
      }
      notifyListeners();
    });

    // Also run a periodic timer as a fallback
    _processTimer = Timer.periodic(_processInterval, (_) => _processQueue());

    // Process anything left over from a previous session immediately
    _processQueue();
  }

  /// Stop the engine (e.g. on logout).
  void stop() {
    _processTimer?.cancel();
    _processTimer = null;
    _connectedSub?.cancel();
    _connectedSub = null;
  }

  /// Enqueue a new action and immediately try to process it.
  Future<void> enqueue(QueueItem item) async {
    await _queue.enqueue(item);
    notifyListeners();
    // Try to send immediately if we have connectivity
    if (_isFirebaseReachable) {
      _processQueue();
    }
  }

  /// Core processing loop. Processes items one at a time, FIFO order.
  Future<void> _processQueue({bool ignoreBackoff = false}) async {
    if (_processing) return;
    _processing = true;

    try {
      final items = _queue.getPendingItems();
      for (final item in items) {
        // Check if item has exceeded max retries
        if (item.retryCount >= _maxRetries) {
          item.status = 'dead';
          await _queue.update(item);
          continue;
        }

        // Check backoff: don't retry too quickly
        if (!ignoreBackoff && item.lastAttemptAt != null) {
          final backoff = _getBackoff(item.retryCount);
          final elapsed = DateTime.now().difference(item.lastAttemptAt!);
          if (elapsed < backoff) continue; // Not time yet
        }

        // Attempt delivery
        item.status = 'in_progress';
        item.lastAttemptAt = DateTime.now();
        await _queue.update(item);

        try {
          await _executeAction(item);

          // Success! Remove from queue
          await _queue.remove(item.id);
          debugPrint('SyncEngine: ✅ ${item.type} delivered (id: ${item.id})');
        } on FirebaseFunctionsException catch (e) {
          // If the backend says "already processed" or returns a non-retryable error,
          // treat it as success (idempotency hit)
          if (_isIdempotencyHit(e)) {
            await _queue.remove(item.id);
            debugPrint('SyncEngine: ✅ ${item.type} already processed (idempotent, id: ${item.id})');
          } else if (_isNonRetryable(e)) {
            // Permanent failure (e.g., ride expired, bid rejected)
            item.status = 'dead';
            item.lastError = e.message;
            await _queue.update(item);
            debugPrint('SyncEngine: ❌ ${item.type} permanently failed: ${e.message}');
          } else {
            // Transient error — retry later
            item.status = 'failed';
            item.retryCount++;
            item.lastError = e.message;
            await _queue.update(item);
            debugPrint('SyncEngine: ⚠️ ${item.type} failed (retry ${item.retryCount}): ${e.message}');
          }
        } catch (e) {
          // Network error or unknown — retry later
          item.status = 'failed';
          item.retryCount++;
          item.lastError = e.toString();
          await _queue.update(item);
          debugPrint('SyncEngine: ⚠️ ${item.type} error (retry ${item.retryCount}): $e');
        }

        notifyListeners();
      }
    } finally {
      _processing = false;
    }
  }

  /// Execute a single action based on its type.
  Future<void> _executeAction(QueueItem item) async {
    final callable = FirebaseFunctions.instance.httpsCallable(
      _getFunctionName(item.type),
    );

    // Inject the operationId into the payload for backend idempotency
    final payload = Map<String, dynamic>.from(item.payload);
    payload['operationId'] = item.id;

    await callable.call<dynamic>(payload);
  }

  /// Map queue item types to Cloud Function names.
  String _getFunctionName(String type) {
    switch (type) {
      case 'PLACE_BID':
        return 'placeBid';
      case 'START_RIDE':
        return 'startRide';
      case 'COMPLETE_RIDE':
        return 'completeRide';
      case 'CANCEL_RIDE':
        return 'cancelRide';
      default:
        throw Exception('Unknown action type: $type');
    }
  }

  /// Calculate exponential backoff delay for a given retry count.
  /// 2s → 4s → 8s → 16s → 32s → 60s (capped)
  Duration _getBackoff(int retryCount) {
    final seconds = min(pow(2, retryCount + 1).toInt(), 60);
    return Duration(seconds: seconds);
  }

  /// Check if a FirebaseFunctionsException indicates the operation was
  /// already processed successfully (idempotency cache hit).
  bool _isIdempotencyHit(FirebaseFunctionsException e) {
    return e.code == 'already-exists';
  }

  /// Check if an error is non-retryable (permanent business logic failure).
  bool _isNonRetryable(FirebaseFunctionsException e) {
    return e.code == 'not-found' ||
        e.code == 'permission-denied' ||
        e.code == 'invalid-argument' ||
        e.code == 'failed-precondition';
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
