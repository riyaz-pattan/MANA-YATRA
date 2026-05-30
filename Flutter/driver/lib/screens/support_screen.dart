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
            subtitle: '+91 8000 000 000',
            onTap: () async {
              final Uri launchUri = Uri(scheme: 'tel', path: '+918000000000');
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
          const SizedBox(height: 32),
          Text(
            'Smart Help Topics',
            style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.1,
            children: [
              _buildSmartFaqCard(context, Icons.account_balance_wallet_outlined, 'Earnings & Payments', 'Learn about 0% commission'),
              _buildSmartFaqCard(context, Icons.electric_rickshaw_outlined, 'Ride Issues', 'Disputes, cancellations'),
              _buildSmartFaqCard(context, Icons.person_outline, 'Account Details', 'Update phone or vehicle'),
              _buildSmartFaqCard(context, Icons.security_outlined, 'Safety & Rules', 'Community guidelines'),
            ],
          ),
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

  Widget _buildSmartFaqCard(BuildContext context, IconData icon, String title, String subtitle) {
    return InkWell(
      onTap: () {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppTheme.surface,
            title: Row(
              children: [
                Icon(icon, color: AppTheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16))),
              ],
            ),
            content: Text(
              'Detailed help articles and guided flows for "$title" will be integrated here.',
              style: GoogleFonts.inter(color: AppTheme.text2),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Close', style: GoogleFonts.inter(color: AppTheme.primary, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.bg2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(icon, color: AppTheme.primary, size: 20),
            ),
            const SizedBox(height: 12),
            Text(title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.text), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(subtitle, style: GoogleFonts.inter(fontSize: 11, color: AppTheme.text3), maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}
