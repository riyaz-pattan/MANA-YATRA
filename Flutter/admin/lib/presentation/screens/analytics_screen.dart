// lib/presentation/screens/analytics_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/auth_provider.dart';

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  int _totalRides = 0;
  int _activeDrivers = 0;
  double _grossRevenue = 0.0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRealData();
  }

  Future<void> _loadRealData() async {
    try {
      final rides = await FirebaseFirestore.instance.collection('rides').get();
      final drivers = await FirebaseFirestore.instance.collection('drivers').where('isBlocked', isEqualTo: false).get();
      
      double revenue = 0.0;
      for (var doc in rides.docs) {
        final data = doc.data();
        if (data['finalPrice'] != null) {
          revenue += double.tryParse(data['finalPrice'].toString()) ?? 0.0;
        }
      }

      if (mounted) {
        setState(() {
          _totalRides = rides.size;
          _activeDrivers = drivers.size;
          _grossRevenue = revenue;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 1024;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isDesktop ? 32 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Analytics & Insights',
                style: GoogleFonts.inter(
                  fontSize: isDesktop ? 24 : 20,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppTheme.darkText : AppTheme.lightText,
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today, size: 16, color: isDark ? AppTheme.darkText2 : AppTheme.lightText2),
                        const SizedBox(width: 8),
                        Text('Last 30 Days', style: GoogleFonts.inter(fontSize: 13, color: isDark ? AppTheme.darkText : AppTheme.lightText)),
                        const SizedBox(width: 8),
                        Icon(Icons.keyboard_arrow_down, size: 16, color: isDark ? AppTheme.darkText2 : AppTheme.lightText2),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.picture_as_pdf, size: 16),
                    label: const Text('Export PDF'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      backgroundColor: AppTheme.brandTeal,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Metric Cards ──
          if (_isLoading)
            const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
          else
            GridView.count(
              crossAxisCount: isDesktop ? 4 : 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: isDesktop ? 2.2 : 1.4,
              children: [
                _buildMetricCard('Total Rides', '$_totalRides', '+100%', true, isDark),
                _buildMetricCard('Gross Revenue', '₹${_grossRevenue.toStringAsFixed(0)}', '+100%', true, isDark),
                _buildMetricCard('Active Drivers', '$_activeDrivers', '0%', true, isDark),
                _buildMetricCard('Avg Rating', '5.0', '0', true, isDark),
              ],
            ),
          const SizedBox(height: 24),

          // ── Charts Row 1 ──
          if (isDesktop)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: _buildRevenueAreaChart(isDark)),
                const SizedBox(width: 24),
                Expanded(flex: 4, child: _buildRideStatusDonutChart(isDark)),
              ],
            )
          else
            Column(
              children: [
                _buildRevenueAreaChart(isDark),
                const SizedBox(height: 24),
                _buildRideStatusDonutChart(isDark),
              ],
            ),
          
          const SizedBox(height: 24),

          // ── Charts Row 2 ──
          if (isDesktop)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 1, child: _buildTopDriversTable(isDark)),
                const SizedBox(width: 24),
                Expanded(flex: 1, child: _buildRiderRetentionChart(isDark)),
              ],
            )
          else
            Column(
              children: [
                _buildTopDriversTable(isDark),
                const SizedBox(height: 24),
                _buildRiderRetentionChart(isDark),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(String title, String value, String change, bool isPositive, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: isDark ? AppTheme.darkText2 : AppTheme.lightText2)),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(value, style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w800, color: isDark ? AppTheme.darkText : AppTheme.lightText)),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (isPositive ? AppTheme.success : AppTheme.danger).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(isPositive ? Icons.arrow_upward : Icons.arrow_downward, size: 12, color: isPositive ? AppTheme.success : AppTheme.danger),
                      const SizedBox(width: 4),
                      Text(change, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: isPositive ? AppTheme.success : AppTheme.danger)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRevenueAreaChart(bool isDark) {
    final bg = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final border = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;
    final text3Color = isDark ? AppTheme.darkText3 : AppTheme.lightText3;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Revenue Growth', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: textColor)),
          const SizedBox(height: 24),
          SizedBox(
            height: 250,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(color: border, strokeWidth: 1, dashArray: [4, 4]),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (v, m) => Text('${v.toInt()}k', style: GoogleFonts.inter(fontSize: 10, color: text3Color)))),
                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, m) {
                    const days = ['1st', '5th', '10th', '15th', '20th', '25th', '30th'];
                    if (v.toInt() < days.length) return Padding(padding: const EdgeInsets.only(top: 8), child: Text(days[v.toInt()], style: GoogleFonts.inter(fontSize: 10, color: text3Color)));
                    return const SizedBox();
                  })),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: const [FlSpot(0, 10), FlSpot(1, 15), FlSpot(2, 12), FlSpot(3, 20), FlSpot(4, 25), FlSpot(5, 22), FlSpot(6, 35)],
                    isCurved: true,
                    color: AppTheme.brandTeal,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [AppTheme.brandTeal.withValues(alpha: 0.3), AppTheme.brandTeal.withValues(alpha: 0.0)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRideStatusDonutChart(bool isDark) {
    final bg = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final border = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ride Outcomes', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: textColor)),
          const SizedBox(height: 24),
          SizedBox(
            height: 250,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 70,
                    startDegreeOffset: 180,
                    sections: [
                      PieChartSectionData(value: 75, color: AppTheme.success, title: '75%', radius: 30, titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                      PieChartSectionData(value: 15, color: AppTheme.danger, title: '15%', radius: 25, titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                      PieChartSectionData(value: 10, color: AppTheme.warning, title: '10%', radius: 20, titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                    ],
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('12.4k', style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w800, color: textColor)),
                    Text('Total', style: GoogleFonts.inter(fontSize: 12, color: isDark ? AppTheme.darkText3 : AppTheme.lightText3)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopDriversTable(bool isDark) {
    final bg = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final border = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;
    final text2Color = isDark ? AppTheme.darkText2 : AppTheme.lightText2;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Top Performing Drivers', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: textColor)),
              TextButton(onPressed: () {}, child: const Text('View All')),
            ],
          ),
          const SizedBox(height: 16),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 4,
            separatorBuilder: (_, __) => Divider(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2,
                      child: Icon(Icons.person, size: 18, color: text2Color),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Driver ${index + 1}', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: textColor)),
                          Text('${120 - (index * 15)} rides completed', style: GoogleFonts.inter(fontSize: 12, color: text2Color)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: AppTheme.warning.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                      child: Row(
                        children: [
                          const Icon(Icons.star, size: 12, color: AppTheme.warning),
                          const SizedBox(width: 4),
                          Text('4.${9 - index}', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.warning)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRiderRetentionChart(bool isDark) {
    final bg = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final border = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;
    final text3Color = isDark ? AppTheme.darkText3 : AppTheme.lightText3;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Rider Retention', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: textColor)),
          const SizedBox(height: 24),
          SizedBox(
            height: 250,
            child: BarChart(
              BarChartData(
                gridData: FlGridData(
                  show: true, drawVerticalLine: false, getDrawingHorizontalLine: (value) => FlLine(color: border, strokeWidth: 1, dashArray: [4, 4]),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (v, m) => Text('${v.toInt()}%', style: GoogleFonts.inter(fontSize: 10, color: text3Color)))),
                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, m) {
                    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May'];
                    if (v.toInt() < months.length) return Padding(padding: const EdgeInsets.only(top: 8), child: Text(months[v.toInt()], style: GoogleFonts.inter(fontSize: 10, color: text3Color)));
                    return const SizedBox();
                  })),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                barGroups: [
                  BarChartGroupData(x: 0, barRods: [BarChartRodData(toY: 45, color: AppTheme.brandBlue, width: 20, borderRadius: BorderRadius.circular(4))]),
                  BarChartGroupData(x: 1, barRods: [BarChartRodData(toY: 52, color: AppTheme.brandBlue, width: 20, borderRadius: BorderRadius.circular(4))]),
                  BarChartGroupData(x: 2, barRods: [BarChartRodData(toY: 60, color: AppTheme.brandBlue, width: 20, borderRadius: BorderRadius.circular(4))]),
                  BarChartGroupData(x: 3, barRods: [BarChartRodData(toY: 65, color: AppTheme.brandBlue, width: 20, borderRadius: BorderRadius.circular(4))]),
                  BarChartGroupData(x: 4, barRods: [BarChartRodData(toY: 72, color: AppTheme.brandTeal, width: 20, borderRadius: BorderRadius.circular(4))]),
                ],
                maxY: 100,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
