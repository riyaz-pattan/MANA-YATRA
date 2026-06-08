// lib/presentation/screens/notification_settings_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart' as fmap;
import 'package:latlong2/latlong.dart' as latlong2;
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
  DateTime? _scheduledTime;
  
  bool _useGeofence = false;
  double _geofenceLat = 17.3850;
  double _geofenceLng = 78.4867;
  double _geofenceRadiusKm = 5.0;

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

    if (_scheduledTime != null) {
      final minTime = DateTime.now().add(const Duration(minutes: 5));
      if (_scheduledTime!.isBefore(minTime)) {
        _showSnackBar('Scheduled time must be at least 5 minutes in the future.', isError: true);
        return;
      }
    }

    setState(() => _sending = true);

    try {
      final Map<String, dynamic> payload = {
        'title': title, 
        'body': body, 
        'target': _targetAudience,
      };
      
      if (_scheduledTime != null) {
        payload['scheduledTime'] = _scheduledTime!.toIso8601String();
      }
      
      if (_useGeofence && _targetAudience != 'users') {
        payload['geofenceLat'] = _geofenceLat;
        payload['geofenceLng'] = _geofenceLng;
        payload['geofenceRadius'] = _geofenceRadiusKm;
      }

      final response = await http.post(
        Uri.parse('https://us-central1-mana-yatra.cloudfunctions.net/sendBroadcastNotification'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
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
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _targetChip('All Riders', 'users', isDark),
                    _targetChip('All Drivers', 'drivers', isDark),
                    _targetChip('Active Drivers', 'active_drivers', isDark),
                    _targetChip('Offline Drivers', 'offline_drivers', isDark),
                    _targetChip('Unapproved Drivers', 'unapproved_drivers', isDark),
                  ],
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: Text('Limit to Geographic Area (Geofence)', style: GoogleFonts.inter(fontWeight: FontWeight.w500, color: textColor)),
                  subtitle: Text('Only send to drivers within the selected area', style: GoogleFonts.inter(fontSize: 12, color: text3Color)),
                  value: _useGeofence,
                  activeColor: AppTheme.brandBlue,
                  contentPadding: EdgeInsets.zero,
                  onChanged: _targetAudience == 'users' ? null : (val) {
                    setState(() => _useGeofence = val);
                  },
                ),
                if (_useGeofence) ...[
                  const SizedBox(height: 16),
                  Text('Radius: ${_geofenceRadiusKm.toInt()} km', style: GoogleFonts.inter(fontWeight: FontWeight.w500, color: textColor)),
                  Slider(
                    value: _geofenceRadiusKm,
                    min: 1,
                    max: 50,
                    divisions: 49,
                    activeColor: AppTheme.brandBlue,
                    onChanged: (val) => setState(() => _geofenceRadiusKm = val),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 250,
                    width: double.infinity,
                    decoration: BoxDecoration(border: Border.all(color: border), borderRadius: BorderRadius.circular(12)),
                    clipBehavior: Clip.hardEdge,
                    child: fmap.FlutterMap(
                      options: fmap.MapOptions(
                        initialCenter: latlong2.LatLng(_geofenceLat, _geofenceLng),
                        initialZoom: 11,
                        onTap: (tapPosition, point) {
                          setState(() {
                            _geofenceLat = point.latitude;
                            _geofenceLng = point.longitude;
                          });
                        },
                      ),
                      children: [
                        fmap.TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.gaman.admin',
                        ),
                        fmap.CircleLayer(
                          circles: [
                            fmap.CircleMarker(
                              point: latlong2.LatLng(_geofenceLat, _geofenceLng),
                              color: AppTheme.brandBlue.withValues(alpha: 0.2),
                              borderColor: AppTheme.brandBlue,
                              borderStrokeWidth: 2,
                              useRadiusInMeter: true,
                              radius: _geofenceRadiusKm * 1000,
                            ),
                          ],
                        ),
                        fmap.MarkerLayer(
                          markers: [
                            fmap.Marker(
                              point: latlong2.LatLng(_geofenceLat, _geofenceLng),
                              width: 40,
                              height: 40,
                              child: const Icon(Icons.location_on, color: AppTheme.danger, size: 40),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Tap on the map to set the center point.', style: GoogleFonts.inter(fontSize: 12, color: text3Color, fontStyle: FontStyle.italic)),
                ],
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
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 30)),
                          );
                          if (date != null) {
                            if (!mounted) return;
                            final time = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.now(),
                            );
                            if (time != null) {
                              setState(() {
                                _scheduledTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
                              });
                            }
                          }
                        },
                        icon: const Icon(Icons.schedule, size: 18),
                        label: Text(_scheduledTime == null 
                            ? 'Schedule for Later' 
                            : 'Scheduled: ${_scheduledTime!.month}/${_scheduledTime!.day} ${_scheduledTime!.hour}:${_scheduledTime!.minute.toString().padLeft(2, '0')}'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          foregroundColor: textColor,
                          side: BorderSide(color: _scheduledTime != null ? AppTheme.brandBlue : border),
                        ),
                      ),
                    ),
                    if (_scheduledTime != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () => setState(() => _scheduledTime = null),
                        icon: const Icon(Icons.clear, color: AppTheme.danger),
                        tooltip: 'Clear Schedule',
                      ),
                    ],
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 3,
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: _sending ? null : _sendBroadcast,
                          icon: _sending ? const SizedBox.shrink() : const Icon(Icons.send, size: 18),
                          label: _sending 
                              ? const CircularProgressIndicator(color: Colors.white) 
                              : Text(_scheduledTime == null ? 'Send Now' : 'Schedule Broadcast'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.brandBlue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ),
                  ],
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
