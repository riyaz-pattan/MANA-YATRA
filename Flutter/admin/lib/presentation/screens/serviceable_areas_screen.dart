// lib/presentation/screens/serviceable_areas_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../core/theme/app_theme.dart';

class ServiceableAreasScreen extends StatefulWidget {
  const ServiceableAreasScreen({super.key});
  @override
  State<ServiceableAreasScreen> createState() => _ServiceableAreasScreenState();
}

class _ServiceableAreasScreenState extends State<ServiceableAreasScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _areas = [];

  @override
  void initState() {
    super.initState();
    _loadAreas();
  }

  Future<void> _loadAreas() async {
    setState(() => _isLoading = true);
    try {
      final rc = FirebaseRemoteConfig.instance;
      await rc.ensureInitialized();
      // force fetch bypass cache
      await rc.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(minutes: 1),
        minimumFetchInterval: const Duration(seconds: 0),
      ));
      await rc.fetchAndActivate();
      final jsonStr = rc.getString('serviceable_areas');
      if (jsonStr.isNotEmpty) {
        final List<dynamic> parsed = json.decode(jsonStr);
        _areas = parsed.map((e) => e as Map<String, dynamic>).toList();
      } else {
        _areas = [];
      }
    } catch (e) {
      debugPrint("Error loading remote config: $e");
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _saveAreas() async {
    setState(() => _isLoading = true);
    try {
      final newJson = json.encode(_areas);
      await FirebaseFunctions.instance.httpsCallable('updateServiceableAreas').call({
        'areasJson': newJson,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Serviceable areas updated successfully!')),
        );
      }
      // Wait a moment and refresh
      await Future.delayed(const Duration(seconds: 2));
      await _loadAreas();
    } catch (e) {
      debugPrint("Error saving areas: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating areas: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  void _addArea() {
    setState(() {
      _areas.add({
        'name': 'New Region',
        'lat': 17.3850,
        'lng': 78.4867,
        'radiusKm': 15.0,
      });
    });
  }

  void _removeArea(int index) {
    setState(() {
      _areas.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Manage Serviceable Regions',
                style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _addArea,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Region'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _saveAreas,
                    icon: const Icon(Icons.save),
                    label: const Text('Save & Publish'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.brandBlue, foregroundColor: Colors.white),
                  ),
                ],
              )
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: _areas.length,
              itemBuilder: (context, index) {
                final area = _areas[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                initialValue: area['name'] as String,
                                decoration: const InputDecoration(labelText: 'Region Name'),
                                onChanged: (v) => area['name'] = v,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _removeArea(index),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                initialValue: area['lat'].toString(),
                                decoration: const InputDecoration(labelText: 'Latitude'),
                                keyboardType: TextInputType.number,
                                onChanged: (v) => area['lat'] = double.tryParse(v) ?? 0.0,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                initialValue: area['lng'].toString(),
                                decoration: const InputDecoration(labelText: 'Longitude'),
                                keyboardType: TextInputType.number,
                                onChanged: (v) => area['lng'] = double.tryParse(v) ?? 0.0,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                initialValue: area['radiusKm'].toString(),
                                decoration: const InputDecoration(labelText: 'Radius (Km)'),
                                keyboardType: TextInputType.number,
                                onChanged: (v) => area['radiusKm'] = double.tryParse(v) ?? 0.0,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
