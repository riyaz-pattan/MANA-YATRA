// lib/presentation/screens/pricing_config_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/audit_log_service.dart';

// ─── Fare calculation using tiered pricing ───────────────────────────────────
double _calculateFare(double distanceKm, Map<String, double> c) {
  final minFare = c['minFare'] ?? 25;
  final baseFareShort = c['baseFareShort'] ?? 20;
  final baseFareMedium = c['baseFareMedium'] ?? 25;
  final baseFareLong = c['baseFareLong'] ?? 30;
  final tier1Rate = c['tier1Rate'] ?? 10;
  final tier1Cap = c['tier1Cap'] ?? 3;
  final tier2Rate = c['tier2Rate'] ?? 13;
  final tier2Cap = c['tier2Cap'] ?? 5;
  final tier3Rate = c['tier3Rate'] ?? 11;

  double baseFare;
  if (distanceKm <= tier1Cap) {
    baseFare = baseFareShort;
  } else if (distanceKm <= tier1Cap + tier2Cap) {
    baseFare = baseFareMedium;
  } else {
    baseFare = baseFareLong;
  }

  double fare = baseFare;
  double remaining = distanceKm;

  final t1 = remaining.clamp(0.0, tier1Cap);
  fare += tier1Rate * t1;
  remaining -= t1;

  final t2 = remaining.clamp(0.0, tier2Cap);
  fare += tier2Rate * t2;
  remaining -= t2;

  if (remaining > 0) fare += tier3Rate * remaining;

  return fare < minFare ? minFare : fare;
}

// ─── Parameter descriptor ────────────────────────────────────────────────────
class _PricingParam {
  final String key;
  final String label;
  final String hint;
  const _PricingParam(this.key, this.label, this.hint);
}

const _paramDefs = [
  _PricingParam('minFare', 'Min Fare', 'Minimum fare floor'),
  _PricingParam('baseFareShort', 'Base Fare (≤3 km)', 'Short-distance base'),
  _PricingParam('baseFareMedium', 'Base Fare (3-8 km)', 'Medium-distance base'),
  _PricingParam('baseFareLong', 'Base Fare (>8 km)', 'Long-distance base'),
  _PricingParam('tier1Rate', 'Tier 1 Rate (₹/km)', 'First tier per-km rate'),
  _PricingParam('tier1Cap', 'Tier 1 Cap (km)', 'Km limit for tier 1'),
  _PricingParam('tier2Rate', 'Tier 2 Rate (₹/km)', 'Second tier per-km rate'),
  _PricingParam('tier2Cap', 'Tier 2 Cap (km)', 'Km limit for tier 2'),
  _PricingParam('tier3Rate', 'Tier 3 Rate (₹/km)', 'Beyond tier 2 rate'),
];

const _previewDistances = [1.0, 2.0, 3.0, 5.0, 7.0, 10.0, 15.0, 20.0];

const _autoDefaults = <String, double>{
  'minFare': 25,
  'baseFareShort': 20,
  'baseFareMedium': 25,
  'baseFareLong': 30,
  'tier1Rate': 10,
  'tier1Cap': 3,
  'tier2Rate': 13,
  'tier2Cap': 5,
  'tier3Rate': 11,
};

const _bikeDefaults = <String, double>{
  'minFare': 18,
  'baseFareShort': 15,
  'baseFareMedium': 18,
  'baseFareLong': 22,
  'tier1Rate': 7,
  'tier1Cap': 3,
  'tier2Rate': 9,
  'tier2Cap': 5,
  'tier3Rate': 8,
};

// ═════════════════════════════════════════════════════════════════════════════
//  Main Screen Widget
// ═════════════════════════════════════════════════════════════════════════════
class PricingConfigScreen extends ConsumerStatefulWidget {
  const PricingConfigScreen({super.key});

  @override
  ConsumerState<PricingConfigScreen> createState() =>
      _PricingConfigScreenState();
}

class _PricingConfigScreenState extends ConsumerState<PricingConfigScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  // Controllers per vehicle type, keyed by param key
  final Map<String, TextEditingController> _autoCtrl = {};
  final Map<String, TextEditingController> _bikeCtrl = {};

  bool _isLoading = true;
  bool _isSavingAuto = false;
  bool _isSavingBike = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    for (final p in _paramDefs) {
      _autoCtrl[p.key] = TextEditingController(
        text: _autoDefaults[p.key]!.toStringAsFixed(0),
      );
      _bikeCtrl[p.key] = TextEditingController(
        text: _bikeDefaults[p.key]!.toStringAsFixed(0),
      );
    }
    _loadConfig();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    for (final c in _autoCtrl.values) {
      c.dispose();
    }
    for (final c in _bikeCtrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Load from Firestore ──────────────────────────────────────────────────
  Future<void> _loadConfig() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('config')
          .doc('pricing')
          .get();
      if (doc.exists) {
        final data = doc.data()!;
        _applyData(data['auto'], _autoCtrl, _autoDefaults);
        _applyData(data['bike'], _bikeCtrl, _bikeDefaults);
      }
    } catch (e) {
      debugPrint('Error loading pricing config: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyData(
    dynamic raw,
    Map<String, TextEditingController> ctrls,
    Map<String, double> defaults,
  ) {
    if (raw is! Map) return;
    final map = Map<String, dynamic>.from(raw);
    for (final p in _paramDefs) {
      final val = map[p.key];
      if (val != null) {
        final num v = val is num ? val : double.tryParse(val.toString()) ?? defaults[p.key]!;
        ctrls[p.key]!.text = v == v.roundToDouble()
            ? v.toInt().toString()
            : v.toStringAsFixed(1);
      }
    }
  }

  // ── Save per vehicle type ────────────────────────────────────────────────
  Future<void> _saveVehicle(String vehicleKey) async {
    final isAuto = vehicleKey == 'auto';
    final ctrls = isAuto ? _autoCtrl : _bikeCtrl;
    final defaults = isAuto ? _autoDefaults : _bikeDefaults;

    setState(() {
      if (isAuto) {
        _isSavingAuto = true;
      } else {
        _isSavingBike = true;
      }
    });

    try {
      final Map<String, dynamic> payload = {};
      for (final p in _paramDefs) {
        payload[p.key] =
            double.tryParse(ctrls[p.key]!.text) ?? defaults[p.key]!;
      }

      await FirebaseFirestore.instance
          .collection('config')
          .doc('pricing')
          .set(
        {
          vehicleKey: payload,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      final admin = ref.read(adminUserProvider).valueOrNull;
      AuditLogService.logAction(
        action: 'updated_pricing_config',
        targetId: vehicleKey,
        admin: admin,
        details: 'Updated pricing for ${isAuto ? "Auto" : "Bike"}',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${isAuto ? "Auto" : "Bike"} pricing saved successfully.',
              style: GoogleFonts.inter(),
            ),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e', style: GoogleFonts.inter()),
            backgroundColor: AppTheme.danger,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          if (isAuto) {
            _isSavingAuto = false;
          } else {
            _isSavingBike = false;
          }
        });
      }
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────
  Map<String, double> _currentValues(Map<String, TextEditingController> ctrls,
      Map<String, double> defaults) {
    return {
      for (final p in _paramDefs)
        p.key: double.tryParse(ctrls[p.key]!.text) ?? defaults[p.key]!,
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final bg = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final bg2 = isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2;
    final border = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;
    final text2 = isDark ? AppTheme.darkText2 : AppTheme.lightText2;
    final text3 = isDark ? AppTheme.darkText3 : AppTheme.lightText3;

    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppTheme.brandBlue),
            const SizedBox(height: 16),
            Text('Loading pricing…',
                style: GoogleFonts.inter(color: text3, fontSize: 14)),
          ],
        ),
      );
    }

    return Column(
      children: [
        // ── Vehicle type tab bar ──
        Container(
          margin: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          decoration: BoxDecoration(
            color: bg2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border),
          ),
          child: TabBar(
            controller: _tabCtrl,
            labelColor: Colors.white,
            unselectedLabelColor: text3,
            indicatorSize: TabBarIndicatorSize.tab,
            indicator: BoxDecoration(
              color: AppTheme.brandBlue,
              borderRadius: BorderRadius.circular(10),
            ),
            indicatorPadding: const EdgeInsets.all(3),
            dividerHeight: 0,
            splashBorderRadius: BorderRadius.circular(10),
            labelStyle:
                GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
            unselectedLabelStyle:
                GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 14),
            tabs: const [
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.local_taxi_rounded, size: 18),
                    SizedBox(width: 8),
                    Text('Auto Rickshaw'),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.two_wheeler_rounded, size: 18),
                    SizedBox(width: 8),
                    Text('Bike'),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── Tab views ──
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              _buildVehicleTab(
                vehicleKey: 'auto',
                label: 'Auto Rickshaw',
                icon: Icons.local_taxi_rounded,
                ctrls: _autoCtrl,
                defaults: _autoDefaults,
                isSaving: _isSavingAuto,
                isDark: isDark,
                bg: bg,
                bg2: bg2,
                border: border,
                textColor: textColor,
                text2: text2,
                text3: text3,
              ),
              _buildVehicleTab(
                vehicleKey: 'bike',
                label: 'Bike',
                icon: Icons.two_wheeler_rounded,
                ctrls: _bikeCtrl,
                defaults: _bikeDefaults,
                isSaving: _isSavingBike,
                isDark: isDark,
                bg: bg,
                bg2: bg2,
                border: border,
                textColor: textColor,
                text2: text2,
                text3: text3,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Vehicle Tab
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildVehicleTab({
    required String vehicleKey,
    required String label,
    required IconData icon,
    required Map<String, TextEditingController> ctrls,
    required Map<String, double> defaults,
    required bool isSaving,
    required bool isDark,
    required Color bg,
    required Color bg2,
    required Color border,
    required Color textColor,
    required Color text2,
    required Color text3,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Section: Tier Parameters ──
              _buildSectionCard(
                title: 'Pricing Parameters',
                subtitle: 'Configure tiered pricing for $label rides',
                icon: Icons.tune_rounded,
                isDark: isDark,
                bg: bg,
                border: border,
                textColor: textColor,
                text2: text2,
                child: Column(
                  children: [
                    // Min Fare (full width)
                    _buildParamField(
                      _paramDefs[0],
                      ctrls,
                      defaults,
                      textColor,
                      text2,
                      border,
                      bg2,
                      isDark,
                    ),
                    const SizedBox(height: 20),

                    // Section label: Base Fares
                    _buildSubHeader('Base Fares', Icons.monetization_on_outlined,
                        textColor, text2),
                    const SizedBox(height: 12),
                    _buildParamRow(
                        [_paramDefs[1], _paramDefs[2], _paramDefs[3]],
                        ctrls,
                        defaults,
                        textColor,
                        text2,
                        border,
                        bg2,
                        isDark),
                    const SizedBox(height: 20),

                    // Section label: Tier Rates
                    _buildSubHeader(
                        'Tier Rates & Caps', Icons.layers_rounded, textColor, text2),
                    const SizedBox(height: 12),
                    _buildParamRow(
                        [_paramDefs[4], _paramDefs[5]],
                        ctrls,
                        defaults,
                        textColor,
                        text2,
                        border,
                        bg2,
                        isDark),
                    const SizedBox(height: 12),
                    _buildParamRow(
                        [_paramDefs[6], _paramDefs[7]],
                        ctrls,
                        defaults,
                        textColor,
                        text2,
                        border,
                        bg2,
                        isDark),
                    const SizedBox(height: 12),
                    _buildParamField(
                      _paramDefs[8],
                      ctrls,
                      defaults,
                      textColor,
                      text2,
                      border,
                      bg2,
                      isDark,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── Section: Live Preview ──
              _buildSectionCard(
                title: 'Fare Preview',
                subtitle: 'Live preview of fares at various distances',
                icon: Icons.visibility_rounded,
                isDark: isDark,
                bg: bg,
                border: border,
                textColor: textColor,
                text2: text2,
                child: _buildPreviewTable(
                    ctrls, defaults, isDark, bg, bg2, border, textColor, text2, text3),
              ),

              const SizedBox(height: 24),

              // ── Save Button ──
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: isSaving ? null : () => _saveVehicle(vehicleKey),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.brandBlue,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        AppTheme.brandBlue.withValues(alpha: 0.5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: isSaving
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2)),
                            const SizedBox(width: 12),
                            Text('Saving…',
                                style: GoogleFonts.inter(
                                    fontSize: 15, fontWeight: FontWeight.w600)),
                          ],
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.save_rounded, size: 20),
                            const SizedBox(width: 10),
                            Text(
                              'Save $label Pricing',
                              style: GoogleFonts.inter(
                                  fontSize: 15, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Section Card ──────────────────────────────────────────────────────────
  Widget _buildSectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isDark,
    required Color bg,
    required Color border,
    required Color textColor,
    required Color text2,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.brandBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: AppTheme.brandBlue, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: GoogleFonts.inter(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: textColor)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: GoogleFonts.inter(
                            fontSize: 13, color: text2)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          child,
        ],
      ),
    );
  }

  // ─── Sub-header label ──────────────────────────────────────────────────────
  Widget _buildSubHeader(
      String text, IconData icon, Color textColor, Color text2) {
    return Row(
      children: [
        Icon(icon, size: 16, color: text2),
        const SizedBox(width: 8),
        Text(text,
            style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: text2,
                letterSpacing: 0.3)),
      ],
    );
  }

  // ─── Parameter row (multiple fields) ───────────────────────────────────────
  Widget _buildParamRow(
    List<_PricingParam> params,
    Map<String, TextEditingController> ctrls,
    Map<String, double> defaults,
    Color textColor,
    Color text2,
    Color border,
    Color bg2,
    bool isDark,
  ) {
    return Row(
      children: [
        for (int i = 0; i < params.length; i++) ...[
          if (i > 0) const SizedBox(width: 16),
          Expanded(
            child: _buildParamField(
                params[i], ctrls, defaults, textColor, text2, border, bg2, isDark),
          ),
        ],
      ],
    );
  }

  // ─── Individual parameter field ────────────────────────────────────────────
  Widget _buildParamField(
    _PricingParam param,
    Map<String, TextEditingController> ctrls,
    Map<String, double> defaults,
    Color textColor,
    Color text2,
    Color border,
    Color bg2,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          param.label,
          style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: text2,
              letterSpacing: 0.2),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: ctrls[param.key],
          style: GoogleFonts.inter(
              fontSize: 15, fontWeight: FontWeight.w500, color: textColor),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}), // trigger preview rebuild
          decoration: InputDecoration(
            hintText: param.hint,
            hintStyle: GoogleFonts.inter(
                fontSize: 13, color: text2.withValues(alpha: 0.5)),
            filled: true,
            fillColor: bg2,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  const BorderSide(color: AppTheme.brandBlue, width: 1.5),
            ),
            suffixText: param.key.contains('Cap') ? 'km' : '₹',
            suffixStyle: GoogleFonts.inter(
                fontSize: 13, fontWeight: FontWeight.w500, color: text2),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Preview Table
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildPreviewTable(
    Map<String, TextEditingController> ctrls,
    Map<String, double> defaults,
    bool isDark,
    Color bg,
    Color bg2,
    Color border,
    Color textColor,
    Color text2,
    Color text3,
  ) {
    final values = _currentValues(ctrls, defaults);

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Table(
        border: TableBorder.all(color: border, width: 1),
        columnWidths: const {
          0: FlexColumnWidth(1),
          1: FlexColumnWidth(1),
          2: FlexColumnWidth(1.5),
        },
        children: [
          // Header
          TableRow(
            decoration: BoxDecoration(
              color: AppTheme.brandBlue.withValues(alpha: isDark ? 0.15 : 0.08),
            ),
            children: [
              _tableCell('Distance', isHeader: true, color: textColor),
              _tableCell('Fare (₹)', isHeader: true, color: textColor),
              _tableCell('Breakdown', isHeader: true, color: textColor),
            ],
          ),
          // Data rows
          for (int i = 0; i < _previewDistances.length; i++)
            _buildPreviewRow(
              _previewDistances[i],
              values,
              i.isEven ? bg : bg2,
              textColor,
              text2,
              text3,
            ),
        ],
      ),
    );
  }

  TableRow _buildPreviewRow(
    double km,
    Map<String, double> values,
    Color rowBg,
    Color textColor,
    Color text2,
    Color text3,
  ) {
    final fare = _calculateFare(km, values);
    final tier1Cap = values['tier1Cap'] ?? 3;
    final tier2Cap = values['tier2Cap'] ?? 5;

    // Determine which tier this distance reaches
    String tierLabel;
    if (km <= tier1Cap) {
      tierLabel = 'Tier 1';
    } else if (km <= tier1Cap + tier2Cap) {
      tierLabel = 'Tier 1 + 2';
    } else {
      tierLabel = 'Tier 1 + 2 + 3';
    }

    final minFare = values['minFare'] ?? 25;
    final isMinApplied = fare <= minFare && km > 0;

    return TableRow(
      decoration: BoxDecoration(color: rowBg),
      children: [
        _tableCell('${km.toStringAsFixed(0)} km', color: textColor),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Text(
            '₹${fare.toStringAsFixed(1)}',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.brandBlue,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.brandTeal.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  tierLabel,
                  style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.brandTeal),
                ),
              ),
              if (isMinApplied) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'MIN',
                    style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.warning),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _tableCell(String text,
      {bool isHeader = false, required Color color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: isHeader ? 12 : 14,
          fontWeight: isHeader ? FontWeight.w700 : FontWeight.w500,
          color: color,
          letterSpacing: isHeader ? 0.5 : 0,
        ),
      ),
    );
  }
}
