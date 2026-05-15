// lib/models/queue_item.dart
/// A persistent action queue item stored in Hive.
/// Each item represents a critical operation (accept_bid, create_ride, etc.)
/// that must be delivered to Firebase, even across app restarts.
class QueueItem {
  final String id; // UUID — also used as operationId for backend idempotency
  final String type; // e.g. 'CREATE_RIDE', 'ACCEPT_BID', 'CANCEL_RIDE', etc.
  final Map<String, dynamic> payload; // Arguments to send to the Cloud Function
  int retryCount;
  String status; // 'pending', 'in_progress', 'failed', 'completed'
  final DateTime createdAt;
  DateTime? lastAttemptAt;
  String? lastError;

  QueueItem({
    required this.id,
    required this.type,
    required this.payload,
    this.retryCount = 0,
    this.status = 'pending',
    DateTime? createdAt,
    this.lastAttemptAt,
    this.lastError,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Convert to a Map for Hive storage.
  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type,
        'payload': payload,
        'retryCount': retryCount,
        'status': status,
        'createdAt': createdAt.toIso8601String(),
        'lastAttemptAt': lastAttemptAt?.toIso8601String(),
        'lastError': lastError,
      };

  /// Restore from a Hive-stored Map.
  factory QueueItem.fromMap(Map<dynamic, dynamic> map) {
    return QueueItem(
      id: map['id'] as String,
      type: map['type'] as String,
      payload: Map<String, dynamic>.from(map['payload'] as Map),
      retryCount: (map['retryCount'] as num?)?.toInt() ?? 0,
      status: (map['status'] as String?) ?? 'pending',
      createdAt: DateTime.parse(map['createdAt'] as String),
      lastAttemptAt: map['lastAttemptAt'] != null
          ? DateTime.parse(map['lastAttemptAt'] as String)
          : null,
      lastError: map['lastError'] as String?,
    );
  }
}
