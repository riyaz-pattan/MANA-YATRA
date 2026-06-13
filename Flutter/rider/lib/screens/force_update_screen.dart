import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/theme.dart';

class ForceUpdateScreen extends StatelessWidget {
  const ForceUpdateScreen({super.key});

  Future<void> _launchStore() async {
    final String url = Platform.isIOS
        ? 'https://apps.apple.com/app/idYOUR_APP_ID' // Replace with actual iOS App ID
        : 'https://play.google.com/store/apps/details?id=com.manayatra.rider';
        
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              
              // Icon
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.system_update,
                  size: 80,
                  color: AppTheme.primary,
                ),
              ),
              
              const SizedBox(height: 32),
              
              // Title
              Text(
                'Update Required',
                style: GoogleFonts.inter(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.text,
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 16),
              
              // Description
              Text(
                'We have added new features and fixed some bugs to make your experience seamless. Please update the app to continue.',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  color: AppTheme.text3,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              
              const Spacer(),
              
              // Update Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _launchStore,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Update Now',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
