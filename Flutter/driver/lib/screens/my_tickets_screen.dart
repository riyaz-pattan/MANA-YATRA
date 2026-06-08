import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';

class MyTicketsScreen extends StatefulWidget {
  const MyTicketsScreen({super.key});

  @override
  State<MyTicketsScreen> createState() => _MyTicketsScreenState();
}

class _MyTicketsScreenState extends State<MyTicketsScreen> {
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'My Tickets',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppTheme.bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.text),
      ),
      body: user == null
          ? Center(child: Text('Please log in to view tickets', style: GoogleFonts.inter(color: AppTheme.text2)))
          : FutureBuilder<QuerySnapshot>(
              future: FirebaseFirestore.instance
                  .collection('support_tickets')
                  .where('uid', isEqualTo: user.uid)
                  .orderBy('createdAt', descending: true)
                  .limit(20)
                  .get(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                if (snapshot.hasError) {
                  return Center(child: Text('Error loading tickets.', style: GoogleFonts.inter(color: AppTheme.danger)));
                }

                final docs = snapshot.data?.docs ?? [];
                
                if (docs.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.assignment_turned_in_outlined, size: 64, color: AppTheme.text3.withValues(alpha: 0.5)),
                          const SizedBox(height: 16),
                          Text('No support tickets', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.text)),
                          const SizedBox(height: 8),
                          Text('You have not reported any issues yet.', style: GoogleFonts.inter(fontSize: 14, color: AppTheme.text2), textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    return _buildTicketCard(data);
                  },
                );
              },
            ),
    );
  }

  Widget _buildTicketCard(Map<String, dynamic> data) {
    final category = data['category'] ?? 'General';
    final subject = data['subject'] ?? 'No Subject';
    final description = data['description'] ?? '';
    final status = data['status'] ?? 'open';
    final timestamp = data['createdAt'] as Timestamp?;
    final date = timestamp != null ? DateFormat.yMMMd().format(timestamp.toDate()) : 'Unknown date';
    
    Color statusBgColor;
    Color statusTextColor;
    String statusLabel = status.toUpperCase();

    switch (status) {
      case 'resolved':
      case 'closed':
        statusBgColor = AppTheme.success.withValues(alpha: 0.1);
        statusTextColor = AppTheme.success;
        break;
      case 'in_progress':
        statusBgColor = AppTheme.info.withValues(alpha: 0.1);
        statusTextColor = AppTheme.info;
        statusLabel = 'IN PROGRESS';
        break;
      case 'open':
      default:
        statusBgColor = AppTheme.warning.withValues(alpha: 0.1);
        statusTextColor = AppTheme.warning;
        break;
    }

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  category,
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.text2),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusBgColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusLabel,
                  style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: statusTextColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            subject,
            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.text),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: GoogleFonts.inter(fontSize: 14, color: AppTheme.text2, height: 1.5),
          ),
          const SizedBox(height: 16),
          Divider(color: AppTheme.border, height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.calendar_today, size: 14, color: AppTheme.text3),
              const SizedBox(width: 6),
              Text(date, style: GoogleFonts.inter(fontSize: 12, color: AppTheme.text3)),
            ],
          ),
        ],
      ),
    );
  }
}
