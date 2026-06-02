// lib/screens/support_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/theme.dart';

import 'report_issue_screen.dart';
import 'my_tickets_screen.dart';

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Support',
          style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 24, letterSpacing: -0.5, color: AppTheme.text),
        ),
        backgroundColor: AppTheme.bg,
        elevation: 0,
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(Icons.support_agent, size: 64, color: AppTheme.primary),
          const SizedBox(height: 16),
          _buildContactCard(
            icon: Icons.email,
            title: 'Email Us',
            subtitle: 'support@wetechspire.com',
            onTap: () async {
              final Uri launchUri = Uri(
                scheme: 'mailto',
                path: 'support@wetechspire.com',
              );
              if (await canLaunchUrl(launchUri)) {
                await launchUrl(launchUri);
              }
            },
          ),
          const SizedBox(height: 16),
          _buildContactCard(
            icon: Icons.report_problem_outlined,
            title: 'Report an Issue',
            subtitle: 'Raise a support ticket',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ReportIssueScreen()),
              );
            },
          ),
          const SizedBox(height: 16),
          _buildContactCard(
            icon: Icons.history,
            title: 'My Tickets',
            subtitle: 'View your support tickets',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MyTicketsScreen()),
              );
            },
          ),
          const SizedBox(height: 32),
          Text(
            'FAQS',
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.text3, letterSpacing: 1.5),
          ),
          const SizedBox(height: 16),
          _buildFaqItem(
            'How do I book a ride?',
            'Simply enter your destination on the home screen, select a vehicle, and confirm.',
          ),
          _buildFaqItem(
            'How do I pay the driver?',
            'You can pay the driver directly using cash or UPI at the end of the ride.',
          ),
        ],
      ),
    );
  }

  Widget _buildContactCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          onTap: onTap,
          leading: Icon(icon, color: AppTheme.text, size: 28),
          title: Text(
            title,
            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.text),
          ),
          subtitle: Text(
            subtitle,
            style: GoogleFonts.inter(fontSize: 13, color: AppTheme.text2),
          ),
          trailing: const Icon(Icons.chevron_right, color: AppTheme.text3, size: 20),
        ),
        Divider(height: 1, indent: 48, color: AppTheme.border.withValues(alpha: 0.5)),
      ],
    );
  }

  Widget _buildFaqItem(String question, String answer) {
    return Column(
      children: [
        ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 4),
          title: Text(
            question,
            style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.text),
          ),
          childrenPadding: const EdgeInsets.only(left: 4, right: 16, bottom: 16),
          children: [
            Text(
              answer,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: AppTheme.text2,
                height: 1.5,
              ),
            ),
          ],
        ),
        Divider(height: 1, color: AppTheme.border.withValues(alpha: 0.5)),
      ],
    );
  }
}
