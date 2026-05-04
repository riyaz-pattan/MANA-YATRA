// lib/screens/notification_settings_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../config/theme.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  // ── Target Audience ──
  String _targetAudience = 'users'; // 'users' or 'drivers'

  // ── Form Controllers ──
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();

  // ── Toggle States ──
  bool _alertNewDriver = true;
  bool _alertDailyEarnings = false;

  // ── Loading / Status ──
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadAlertSettings();
  }

  Future<void> _loadAlertSettings() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('admin_settings')
          .doc('alerts')
          .get();
      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          _alertNewDriver = data['newDriverRegistration'] ?? true;
          _alertDailyEarnings = data['dailyEarningsSummary'] ?? false;
        });
      }
    } catch (_) {
      // Use defaults
    }
  }

  Future<void> _saveAlertSettings() async {
    try {
      await FirebaseFirestore.instance
          .collection('admin_settings')
          .doc('alerts')
          .set({
        'newDriverRegistration': _alertNewDriver,
        'dailyEarningsSummary': _alertDailyEarnings,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _sendBroadcast() async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();

    if (title.isEmpty || body.isEmpty) {
      _showSnackBar('Please fill in both title and message.', isError: true);
      return;
    }

    setState(() => _sending = true);

    try {
      // Call the Firebase Cloud Function
      final response = await http.post(
        Uri.parse(
          'https://us-central1-mana-yatra.cloudfunctions.net/sendBroadcastNotification',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'title': title,
          'body': body,
          'target': _targetAudience,
        }),
      );

      if (response.statusCode == 200) {
        _titleController.clear();
        _bodyController.clear();
        if (mounted) {
          _showSnackBar(
            'Notification sent to all ${_targetAudience == 'users' ? 'riders' : 'drivers'}!',
          );
        }
      } else {
        if (mounted) {
          _showSnackBar('Failed to send notification.', isError: true);
        }
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar(
          'Network error. Make sure Cloud Function is deployed.',
          isError: true,
        );
      }
    }

    if (mounted) setState(() => _sending = false);
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.inter(fontSize: 13)),
        backgroundColor: isError ? AppTheme.danger : AppTheme.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Section: Send Push Notification ──
          Text(
            'Send Push Notification',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Broadcast a message to all users or drivers.',
            style: GoogleFonts.inter(fontSize: 13, color: AppTheme.text3),
          ),
          const SizedBox(height: 20),

          // ── Broadcast Card ──
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.bg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Target Audience',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: AppTheme.text,
                  ),
                ),
                const SizedBox(height: 12),

                // Target chips
                Row(
                  children: [
                    _targetChip('All Riders', 'users'),
                    const SizedBox(width: 10),
                    _targetChip('All Drivers', 'drivers'),
                  ],
                ),
                const SizedBox(height: 20),

                // Title field
                TextField(
                  controller: _titleController,
                  style: GoogleFonts.inter(fontSize: 14, color: AppTheme.text),
                  decoration: const InputDecoration(
                    labelText: 'Notification Title',
                    hintText: 'e.g. Service Update',
                  ),
                ),
                const SizedBox(height: 14),

                // Body field
                TextField(
                  controller: _bodyController,
                  maxLines: 4,
                  style: GoogleFonts.inter(fontSize: 14, color: AppTheme.text),
                  decoration: const InputDecoration(
                    labelText: 'Message Body',
                    hintText: 'Type your message here...',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 20),

                // Send button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _sending ? null : _sendBroadcast,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          AppTheme.accent.withValues(alpha: 0.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: _sending
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.send_rounded, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                'Send Broadcast',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 36),

          // ── Section: Automated Alerts ──
          Text(
            'Automated Alerts',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Configure which alerts you receive.',
            style: GoogleFonts.inter(fontSize: 13, color: AppTheme.text3),
          ),
          const SizedBox(height: 16),

          _settingToggle(
            'New Driver Registrations',
            'Receive an alert when a driver uploads KYC documents.',
            _alertNewDriver,
            (v) {
              setState(() => _alertNewDriver = v);
              _saveAlertSettings();
            },
          ),
          _settingToggle(
            'Daily Earnings Summary',
            'Receive a daily report of total platform earnings.',
            _alertDailyEarnings,
            (v) {
              setState(() => _alertDailyEarnings = v);
              _saveAlertSettings();
            },
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _targetChip(String label, String value) {
    final isSelected = _targetAudience == value;
    return GestureDetector(
      onTap: () => setState(() => _targetAudience = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary : AppTheme.bg2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppTheme.primary : AppTheme.border,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : AppTheme.text2,
          ),
        ),
      ),
    );
  }

  Widget _settingToggle(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: AppTheme.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    color: AppTheme.text3,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppTheme.success,
          ),
        ],
      ),
    );
  }
}
