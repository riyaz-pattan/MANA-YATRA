// lib/screens/users_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/theme.dart';

class UsersScreen extends StatelessWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .orderBy('updatedAt', descending: true)
          .limit(100)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: AppTheme.primary),
          );
        }

        final users = snap.data!.docs.map((d) {
          final data = d.data() as Map<String, dynamic>;
          data['id'] = d.id;
          return data;
        }).toList();

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('👤 Users',
                  style: GoogleFonts.inter(
                      fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('Manage rider accounts · ${users.length} total',
                  style: GoogleFonts.inter(
                      fontSize: 14, color: AppTheme.text3)),
              const SizedBox(height: 24),

              ...users.map((user) => Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(user['phone'] ?? 'Unknown',
                                  style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15)),
                              const SizedBox(height: 4),
                              Text(
                                user['id'].toString().substring(0, 12),
                                style: const TextStyle(
                                  color: AppTheme.text3,
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: user['isBlocked'] == true
                                ? AppTheme.danger.withValues(alpha: 0.15)
                                : AppTheme.success.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            user['isBlocked'] == true
                                ? 'Blocked'
                                : 'Active',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: user['isBlocked'] == true
                                  ? AppTheme.danger
                                  : AppTheme.success,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: () async {
                            await FirebaseFirestore.instance
                                .collection('users')
                                .doc(user['id'])
                                .update({
                              'isBlocked': !(user['isBlocked'] == true),
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: user['isBlocked'] == true
                                  ? AppTheme.success.withValues(alpha: 0.15)
                                  : AppTheme.danger.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              user['isBlocked'] == true
                                  ? 'Unblock'
                                  : 'Block',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: user['isBlocked'] == true
                                    ? AppTheme.success
                                    : AppTheme.danger,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),

              if (users.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Text('No users found',
                        style: GoogleFonts.inter(color: AppTheme.text3)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
