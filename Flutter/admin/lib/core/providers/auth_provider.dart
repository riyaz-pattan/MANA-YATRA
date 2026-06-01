import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../data/models/admin_user.dart';

/// Provides the current Firebase Auth user stream.
final firebaseAuthProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

/// Provides the current admin user's profile from Firestore.
/// Yields null if the user is not found in the admin_users collection.
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
          // Strict access control: If the user doesn't exist in the admin_users collection,
          // they have no access to the admin portal.
          return null;
        }
        return AdminUser.fromFirestore(doc);
      });
    },
    loading: () => Stream.value(null),
    error: (_, __) => Stream.value(null),
  );
});

/// Theme mode state (dark/light).
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.dark);

/// Sidebar collapsed state.
final sidebarCollapsedProvider = StateProvider<bool>((ref) => false);
