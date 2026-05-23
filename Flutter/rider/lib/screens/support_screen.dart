// lib/screens/support_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/theme.dart';
import '../config/constants.dart';
import 'report_issue_screen.dart';

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Support', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        backgroundColor: AppTheme.surface,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(Icons.support_agent, size: 64, color: AppTheme.primary),
          const SizedBox(height: 16),
          Text(
            'How can we help you?',
            style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          _buildContactCard(
            icon: Icons.phone,
            title: 'Call Support',
            subtitle: AppConstants.supportNumber,
            onTap: () async {
              final Uri launchUri = Uri(scheme: 'tel', path: AppConstants.supportNumber.replaceAll(' ', ''));
              if (await canLaunchUrl(launchUri)) {
                await launchUrl(launchUri);
              }
            },
          ),
          const SizedBox(height: 16),
          _buildContactCard(
            icon: Icons.email,
            title: 'Email Us',
            subtitle: 'support@manayatra.com',
            onTap: () async {
              final Uri launchUri = Uri(scheme: 'mailto', path: 'support@manayatra.com');
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
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportIssueScreen()));
            },
          ),
          const SizedBox(height: 32),
          Text(
            'FAQs',
            style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          _buildFaqItem('How do I book a ride?', 'Simply enter your destination on the home screen, select a vehicle, and confirm.'),
          _buildFaqItem('How do I pay the driver?', 'You can pay the driver directly using cash or UPI at the end of the ride.'),
        ],
      ),
    );
  }

  Widget _buildContactCard({required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppTheme.primary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600)),
                  Text(subtitle, style: GoogleFonts.inter(fontSize: 14, color: AppTheme.text2)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppTheme.text3),
          ],
        ),
      ),
    );
  }

  Widget _buildFaqItem(String question, String answer) {
    return ExpansionTile(
      title: Text(question, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w500)),
      childrenPadding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
      children: [
        Text(answer, style: GoogleFonts.inter(fontSize: 14, color: AppTheme.text2, height: 1.5)),
      ],
    );
  }
}
