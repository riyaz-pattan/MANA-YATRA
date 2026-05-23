// lib/presentation/screens/notification_settings_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../../core/theme/app_theme.dart';
import '../../core/providers/auth_provider.dart';

class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends ConsumerState<NotificationSettingsScreen> {
  String _targetAudience = 'users';
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  bool _alertNewDriver = true;
  bool _alertDailyEarnings = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadAlertSettings();
  }

  Future<void> _loadAlertSettings() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('admin_settings').doc('alerts').get();
      if (doc.exists) {
        final data = doc.data()!;
        if (mounted) {
          setState(() {
            _alertNewDriver = data['newDriverRegistration'] ?? true;
            _alertDailyEarnings = data['dailyEarningsSummary'] ?? false;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _saveAlertSettings() async {
    try {
      await FirebaseFirestore.instance.collection('admin_settings').doc('alerts').set({
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
      final response = await http.post(
        Uri.parse('https://us-central1-mana-yatra.cloudfunctions.net/sendBroadcastNotification'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'title': title, 'body': body, 'target': _targetAudience}),
      );

      if (response.statusCode == 200) {
        _titleController.clear();
        _bodyController.clear();
        if (mounted) _showSnackBar('Notification sent to all ${_targetAudience == 'users' ? 'riders' : 'drivers'}!');
      } else {
        if (mounted) _showSnackBar('Failed to send notification.', isError: true);
      }
    } catch (e) {
      if (mounted) _showSnackBar('Network error. Make sure Cloud Function is deployed.', isError: true);
    }
    if (mounted) setState(() => _sending = false);
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.inter(fontSize: 13, color: Colors.white)),
        backgroundColor: isError ? AppTheme.danger : AppTheme.success,
        behavior: SnackBarBehavior.floating,
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
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 1024;
    
    final bg = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final border = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;
    final text2Color = isDark ? AppTheme.darkText2 : AppTheme.lightText2;
    final text3Color = isDark ? AppTheme.darkText3 : AppTheme.lightText3;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isDesktop ? 32 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Push Notifications', style: GoogleFonts.inter(fontSize: isDesktop ? 24 : 20, fontWeight: FontWeight.w700, color: textColor)),
          const SizedBox(height: 8),
          Text('Broadcast messages to drivers or riders.', style: GoogleFonts.inter(fontSize: 14, color: text3Color)),
          const SizedBox(height: 32),

          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: border)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Target Audience', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14, color: textColor)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _targetChip('All Riders', 'users', isDark),
                    const SizedBox(width: 12),
                    _targetChip('All Drivers', 'drivers', isDark),
                  ],
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _titleController,
                  style: GoogleFonts.inter(color: textColor),
                  decoration: InputDecoration(
                    labelText: 'Notification Title',
                    hintText: 'e.g. Service Update',
                    labelStyle: GoogleFonts.inter(color: text2Color),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: border), borderRadius: BorderRadius.circular(8)),
                    focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: AppTheme.brandBlue), borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _bodyController,
                  maxLines: 4,
                  style: GoogleFonts.inter(color: textColor),
                  decoration: InputDecoration(
                    labelText: 'Message Body',
                    hintText: 'Type your message here...',
                    alignLabelWithHint: true,
                    labelStyle: GoogleFonts.inter(color: text2Color),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: border), borderRadius: BorderRadius.circular(8)),
                    focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: AppTheme.brandBlue), borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _sending ? null : _sendBroadcast,
                    icon: _sending ? const SizedBox.shrink() : const Icon(Icons.send, size: 18),
                    label: _sending ? const CircularProgressIndicator(color: Colors.white) : const Text('Send Broadcast'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.brandBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),

          Text('Automated Alerts', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: textColor)),
          const SizedBox(height: 8),
          Text('Configure internal alerts for admins.', style: GoogleFonts.inter(fontSize: 14, color: text3Color)),
          const SizedBox(height: 24),

          _settingToggle('New Driver Registrations', 'Receive an alert when a driver uploads KYC documents.', _alertNewDriver, (v) {
            setState(() => _alertNewDriver = v);
            _saveAlertSettings();
          }, isDark, bg, border, textColor, text3Color),
          _settingToggle('Daily Earnings Summary', 'Receive a daily report of total platform earnings.', _alertDailyEarnings, (v) {
            setState(() => _alertDailyEarnings = v);
            _saveAlertSettings();
          }, isDark, bg, border, textColor, text3Color),
        ],
      ),
    );
  }

  Widget _targetChip(String label, String value, bool isDark) {
    final isSelected = _targetAudience == value;
    return GestureDetector(
      onTap: () => setState(() => _targetAudience = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.brandBlue : (isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? AppTheme.brandBlue : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder)),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : (isDark ? AppTheme.darkText2 : AppTheme.lightText2),
          ),
        ),
      ),
    );
  }

  Widget _settingToggle(String title, String subtitle, bool value, ValueChanged<bool> onChanged, bool isDark, Color bg, Color border, Color textColor, Color text3Color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15, color: textColor)),
                const SizedBox(height: 4),
                Text(subtitle, style: GoogleFonts.inter(color: text3Color, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Switch(value: value, onChanged: onChanged, activeColor: AppTheme.brandBlue),
        ],
      ),
    );
  }
}
