// lib/data/models/admin_user.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/rbac.dart';

/// Represents an admin user in the system.
class AdminUser {
  final String uid;
  final String email;
  final String displayName;
  final AdminRole role;
  final List<String> permissions;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? lastLogin;
  final bool isActive;

  const AdminUser({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.role,
    this.permissions = const [],
    this.createdBy,
    this.createdAt,
    this.lastLogin,
    this.isActive = true,
  });

  factory AdminUser.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return AdminUser(
      uid: doc.id,
      email: data['email'] as String? ?? '',
      displayName: (data['displayName'] as String?)?.isNotEmpty == true ? data['displayName'] as String : 'Admin',
      role: AdminRole.fromString(data['role'] as String? ?? 'viewer'),
      permissions: List<String>.from(data['permissions'] ?? []),
      createdBy: data['createdBy'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      lastLogin: (data['lastLogin'] as Timestamp?)?.toDate(),
      isActive: data['isActive'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'email': email,
      'displayName': displayName,
      'role': role.value,
      'permissions': permissions,
      'createdBy': createdBy,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      'lastLogin': lastLogin != null ? Timestamp.fromDate(lastLogin!) : null,
      'isActive': isActive,
    };
  }

  AdminUser copyWith({
    String? uid,
    String? email,
    String? displayName,
    AdminRole? role,
    List<String>? permissions,
    String? createdBy,
    DateTime? createdAt,
    DateTime? lastLogin,
    bool? isActive,
  }) {
    return AdminUser(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      role: role ?? this.role,
      permissions: permissions ?? this.permissions,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      lastLogin: lastLogin ?? this.lastLogin,
      isActive: isActive ?? this.isActive,
    );
  }

  /// Check if this admin has a specific permission.
  bool hasPermission(Permission permission) {
    return RBACConfig.hasPermission(role, permission);
  }
}
