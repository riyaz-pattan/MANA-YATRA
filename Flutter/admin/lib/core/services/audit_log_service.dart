import 'package:cloud_firestore/cloud_firestore.dart';
import '../../data/models/admin_user.dart';

import 'package:firebase_auth/firebase_auth.dart';

class AuditLogService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Future<void> logAction({
    required String action,
    required String targetId,
    AdminUser? admin,
    String? details,
  }) async {
    try {
      String adminName = 'System';
      String adminUid = 'unknown';
      String adminRole = 'admin';

      if (admin != null) {
        adminName = admin.displayName.isNotEmpty ? admin.displayName : admin.email;
        adminUid = admin.uid;
        adminRole = admin.role;
      } else {
        // Fallback if provider was not ready
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          adminUid = user.uid;
          adminName = user.email ?? 'Unknown Admin';
          // Optionally fetch from Firestore
          final doc = await _db.collection('admin_users').doc(user.uid).get();
          if (doc.exists) {
            final data = doc.data()!;
            if (data['displayName'] != null && data['displayName'].toString().isNotEmpty) {
              adminName = data['displayName'];
            }
            if (data['role'] != null) {
              adminRole = data['role'];
            }
          }
        }
      }

      await _db.collection('audit_logs').add({
        'action': action,
        'targetId': targetId,
        'targetUid': targetId,
        'performedBy': adminName,
        'performedByUid': adminUid,
        'performedByRole': adminRole,
        'details': details ?? '',
        'timestamp': Timestamp.now(),
      });
    } catch (e) {
      print('Failed to write audit log: $e');
    }
  }
}
