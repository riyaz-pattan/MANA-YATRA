// lib/presentation/screens/pricing_config_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/auth_provider.dart';

class PricingConfigScreen extends ConsumerStatefulWidget {
  const PricingConfigScreen({super.key});

  @override
  ConsumerState<PricingConfigScreen> createState() => _PricingConfigScreenState();
}

class _PricingConfigScreenState extends ConsumerState<PricingConfigScreen> {
  final _autoBaseFareCtrl = TextEditingController();
  final _autoPerKmCtrl = TextEditingController();
  final _bikeBaseFareCtrl = TextEditingController();
  final _bikePerKmCtrl = TextEditingController();
  final _platformFeeCtrl = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('config').doc('pricing').get();
      if (doc.exists) {
        final data = doc.data()!;
        _autoBaseFareCtrl.text = data['autoBaseFare']?.toString() ?? '30';
        _autoPerKmCtrl.text = data['autoPerKm']?.toString() ?? '15';
        _bikeBaseFareCtrl.text = data['bikeBaseFare']?.toString() ?? '20';
        _bikePerKmCtrl.text = data['bikePerKm']?.toString() ?? '10';
      }
    } catch (e) {
      debugPrint("Error loading config: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveConfig() async {
    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance.collection('config').doc('pricing').set({
        'autoBaseFare': double.tryParse(_autoBaseFareCtrl.text) ?? 30.0,
        'autoPerKm': double.tryParse(_autoPerKmCtrl.text) ?? 15.0,
        'bikeBaseFare': double.tryParse(_bikeBaseFareCtrl.text) ?? 20.0,
        'bikePerKm': double.tryParse(_bikePerKmCtrl.text) ?? 10.0,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pricing configuration saved successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save config: $e'), backgroundColor: AppTheme.danger),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final bg = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final border = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Container(
          width: 600,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Global Pricing & Commission', style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, color: textColor)),
              const SizedBox(height: 32),
              
              Text('Auto Pricing (₹)', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600, color: textColor)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _buildTextField('Base Fare', _autoBaseFareCtrl, textColor)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildTextField('Per Km Rate', _autoPerKmCtrl, textColor)),
                ],
              ),
              const SizedBox(height: 32),
              
              Text('Bike Pricing (₹)', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600, color: textColor)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _buildTextField('Base Fare', _bikeBaseFareCtrl, textColor)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildTextField('Per Km Rate', _bikePerKmCtrl, textColor)),
                ],
              ),
              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveConfig,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.brandBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isSaving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('Save Configuration', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, Color textColor) {
    return TextField(
      controller: controller,
      style: TextStyle(color: textColor),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: textColor.withValues(alpha: 0.7)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
