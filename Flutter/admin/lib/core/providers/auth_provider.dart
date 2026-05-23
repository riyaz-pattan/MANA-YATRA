import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../data/models/admin_user.dart';
import '../constants/rbac.dart';

/// Provides the current Firebase Auth user stream.
final firebaseAuthProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

/// Provides the current admin user's profile from Firestore.
/// This includes their role and permissions.
final adminUserProvider = StreamProvider<AdminUser?>((ref) {
  final authAsync = ref.watch(firebaseAuthProvider);
  return authAsync.when(
    data: (user) {
      if (user == null) return Stream.value(null);
      return FirebaseFirestore.instance
          .collection('admin_users')
          .doc(user.uid)
          .snapshots()
          .map((doc) {
        if (!doc.exists) {
          // If no admin_users doc exists, create a basic one from auth claims
          // The Super Admin should set up the initial admin_users doc
          return AdminUser(
            uid: user.uid,
            email: user.email ?? '',
            displayName: user.displayName ?? user.email?.split('@').first ?? 'Admin',
            role: AdminRole.superAdmin, // Default for first admin
          );
        }
        return AdminUser.fromFirestore(doc);
      });
    },
    loading: () => Stream.value(null),
    error: (_, __) => Stream.value(null),
  );
});

/// Provides just the current admin's role.
final adminRoleProvider = Provider<AdminRole>((ref) {
  final adminUser = ref.watch(adminUserProvider).valueOrNull;
  return adminUser?.role ?? AdminRole.viewer;
});

/// Check if the current admin has a specific permission.
final hasPermissionProvider = Provider.family<bool, Permission>((ref, permission) {
  final role = ref.watch(adminRoleProvider);
  return RBACConfig.hasPermission(role, permission);
});

/// Theme mode state (dark/light).
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.dark);

/// Sidebar collapsed state.
final sidebarCollapsedProvider = StateProvider<bool>((ref) => false);
