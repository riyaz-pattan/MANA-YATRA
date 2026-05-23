// lib/data/models/audit_log.dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents an entry in the audit log.
class AuditLog {
  final String id;
  final String action;
  final String performedBy; // admin UID
  final String performedByEmail;
  final String performedByRole;
  final String targetCollection;
  final String? targetDocId;
  final Map<String, dynamic>? previousData;
  final Map<String, dynamic>? newData;
  final String? description;
  final DateTime timestamp;

  const AuditLog({
    required this.id,
    required this.action,
    required this.performedBy,
    required this.performedByEmail,
    required this.performedByRole,
    required this.targetCollection,
    this.targetDocId,
    this.previousData,
    this.newData,
    this.description,
    required this.timestamp,
  });

  factory AuditLog.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return AuditLog(
      id: doc.id,
      action: data['action'] as String? ?? '',
      performedBy: data['performedBy'] as String? ?? '',
      performedByEmail: data['performedByEmail'] as String? ?? '',
      performedByRole: data['performedByRole'] as String? ?? '',
      targetCollection: data['targetCollection'] as String? ?? '',
      targetDocId: data['targetDocId'] as String?,
      previousData: data['previousData'] as Map<String, dynamic>?,
      newData: data['newData'] as Map<String, dynamic>?,
      description: data['description'] as String?,
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'action': action,
      'performedBy': performedBy,
      'performedByEmail': performedByEmail,
      'performedByRole': performedByRole,
      'targetCollection': targetCollection,
      'targetDocId': targetDocId,
      'previousData': previousData,
      'newData': newData,
      'description': description,
      'timestamp': FieldValue.serverTimestamp(),
    };
  }
}
