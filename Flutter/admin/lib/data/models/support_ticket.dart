// lib/data/models/support_ticket.dart
import 'package:cloud_firestore/cloud_firestore.dart';

enum TicketStatus {
  open('open', 'Open'),
  inProgress('in_progress', 'In Progress'),
  resolved('resolved', 'Resolved'),
  closed('closed', 'Closed');

  const TicketStatus(this.value, this.displayName);
  final String value;
  final String displayName;

  static TicketStatus fromString(String value) {
    return TicketStatus.values.firstWhere(
      (s) => s.value == value,
      orElse: () => TicketStatus.open,
    );
  }
}

enum TicketPriority {
  low('low', 'Low'),
  medium('medium', 'Medium'),
  high('high', 'High'),
  critical('critical', 'Critical');

  const TicketPriority(this.value, this.displayName);
  final String value;
  final String displayName;

  static TicketPriority fromString(String value) {
    return TicketPriority.values.firstWhere(
      (p) => p.value == value,
      orElse: () => TicketPriority.medium,
    );
  }
}

enum TicketCategory {
  rideIssue('ride_issue', 'Ride Issue'),
  paymentDispute('payment_dispute', 'Payment Dispute'),
  driverComplaint('driver_complaint', 'Driver Complaint'),
  riderComplaint('rider_complaint', 'Rider Complaint'),
  accountIssue('account_issue', 'Account Issue'),
  appBug('app_bug', 'App Bug'),
  other('other', 'Other');

  const TicketCategory(this.value, this.displayName);
  final String value;
  final String displayName;

  static TicketCategory fromString(String value) {
    return TicketCategory.values.firstWhere(
      (c) => c.value == value,
      orElse: () => TicketCategory.other,
    );
  }
}

class SupportTicket {
  final String id;
  final String title;
  final String description;
  final TicketStatus status;
  final TicketPriority priority;
  final TicketCategory category;
  final String reportedBy; // UID of rider/driver
  final String reportedByName;
  final String reportedByRole; // 'rider' or 'driver'
  final String? assignedTo; // admin UID
  final String? assignedToName;
  final String? rideId;
  final List<String> attachments;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? resolvedAt;
  final String? resolution;

  const SupportTicket({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.priority,
    required this.category,
    required this.reportedBy,
    required this.reportedByName,
    required this.reportedByRole,
    this.assignedTo,
    this.assignedToName,
    this.rideId,
    this.attachments = const [],
    required this.createdAt,
    this.updatedAt,
    this.resolvedAt,
    this.resolution,
  });

  factory SupportTicket.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return SupportTicket(
      id: doc.id,
      title: data['title'] as String? ?? '',
      description: data['description'] as String? ?? '',
      status: TicketStatus.fromString(data['status'] as String? ?? ''),
      priority: TicketPriority.fromString(data['priority'] as String? ?? ''),
      category: TicketCategory.fromString(data['category'] as String? ?? ''),
      reportedBy: data['reportedBy'] as String? ?? '',
      reportedByName: data['reportedByName'] as String? ?? '',
      reportedByRole: data['reportedByRole'] as String? ?? '',
      assignedTo: data['assignedTo'] as String?,
      assignedToName: data['assignedToName'] as String?,
      rideId: data['rideId'] as String?,
      attachments: List<String>.from(data['attachments'] ?? []),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      resolvedAt: (data['resolvedAt'] as Timestamp?)?.toDate(),
      resolution: data['resolution'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'description': description,
      'status': status.value,
      'priority': priority.value,
      'category': category.value,
      'reportedBy': reportedBy,
      'reportedByName': reportedByName,
      'reportedByRole': reportedByRole,
      'assignedTo': assignedTo,
      'assignedToName': assignedToName,
      'rideId': rideId,
      'attachments': attachments,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'resolvedAt': resolvedAt != null ? Timestamp.fromDate(resolvedAt!) : null,
      'resolution': resolution,
    };
  }
}
