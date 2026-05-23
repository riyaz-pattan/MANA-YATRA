// lib/presentation/screens/dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/dashboard_provider.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final statsAsync = ref.watch(dashboardStatsProvider);
    final adminUser = ref.watch(adminUserProvider).valueOrNull;
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 1024;

    return statsAsync.when(
      loading: () => _buildSkeleton(isDark),
      error: (e, _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48,
              color: isDark ? AppTheme.darkText3 : AppTheme.lightText3),
            const SizedBox(height: 12),
            Text('Failed to load dashboard',
              style: GoogleFonts.inter(
                color: isDark ? AppTheme.darkText2 : AppTheme.lightText2)),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () => ref.invalidate(dashboardStatsProvider),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(120, 40)),
            ),
          ],
        ),
      ),
      data: (stats) => RefreshIndicator(
        onRefresh: () async => ref.invalidate(dashboardStatsProvider),
        color: AppTheme.brandBlue,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(isDesktop ? 28 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Welcome Banner ──
              _buildWelcomeBanner(isDark, adminUser?.displayName ?? 'Admin', stats),
              const SizedBox(height: 24),

              // ── KPI Cards ──
              _buildKPIGrid(isDark, stats, isDesktop),
              const SizedBox(height: 24),

              // ── Charts ──
              if (isDesktop)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildRidesChart(isDark)),
                    const SizedBox(width: 20),
                    Expanded(child: _buildRevenueChart(isDark)),
                  ],
                )
              else
                Column(
                  children: [
                    _buildRidesChart(isDark),
                    const SizedBox(height: 20),
                    _buildRevenueChart(isDark),
                  ],
                ),

              const SizedBox(height: 24),

              // ── Quick Stats Row ──
              _buildQuickStats(isDark, stats, isDesktop),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeBanner(bool isDark, String name, DashboardStats stats) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppTheme.brandBlue.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Welcome back,',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            name,
            style: GoogleFonts.inter(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _bannerChip(Icons.route_rounded, '${stats.ongoingRides} ongoing rides'),
              const SizedBox(width: 12),
              _bannerChip(Icons.local_taxi, '${stats.onlineDrivers} drivers online'),
              const SizedBox(width: 12),
              _bannerChip(Icons.trending_up, '₹${stats.todayRevenue.toStringAsFixed(0)} today'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bannerChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white70),
          const SizedBox(width: 6),
          Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKPIGrid(bool isDark, DashboardStats stats, bool isDesktop) {
    final cards = [
      _KPIData('Active Drivers', '${stats.onlineDrivers}', Icons.local_taxi,
          AppTheme.brandBlue, '+${stats.approvedDrivers} approved'),
      _KPIData('Ongoing Rides', '${stats.ongoingRides}', Icons.route,
          AppTheme.brandTeal, '${stats.totalRides} total'),
      _KPIData("Today's Revenue", '₹${stats.todayRevenue.toStringAsFixed(0)}',
          Icons.account_balance_wallet, AppTheme.success,
          '₹${stats.totalRevenue.toStringAsFixed(0)} total'),
      _KPIData('Completion Rate', '${stats.completionRate.toStringAsFixed(1)}%',
          Icons.check_circle, AppTheme.brandPurple,
          '${stats.cancellationRate.toStringAsFixed(1)}% cancellation'),
      _KPIData('Total Riders', '${stats.totalRiders}', Icons.people,
          AppTheme.info, 'registered users'),
      _KPIData('Pending Approvals', '${stats.pendingDrivers}', Icons.pending_actions,
          AppTheme.warning, 'driver applications'),
    ];

    if (isDesktop) {
      return GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 2.0,
        children: cards.map((c) => _buildKPICard(isDark, c)).toList(),
      );
    }

    // Mobile: 2 columns
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.1,
      children: cards.map((c) => _buildKPICard(isDark, c)).toList(),
    );
  }

  Widget _buildKPICard(bool isDark, _KPIData data) {
    final bg = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;
    final text2Color = isDark ? AppTheme.darkText2 : AppTheme.lightText2;
    final text3Color = isDark ? AppTheme.darkText3 : AppTheme.lightText3;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    data.label,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: text2Color,
                    ),
                  ),
                ),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: data.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(data.icon, size: 18, color: data.color),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                data.value,
                style: GoogleFonts.inter(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: textColor,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              data.subtitle,
              style: GoogleFonts.inter(fontSize: 11, color: text3Color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRidesChart(bool isDark) {
    final bg = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;
    final text2Color = isDark ? AppTheme.darkText2 : AppTheme.lightText2;
    final text3Color = isDark ? AppTheme.darkText3 : AppTheme.lightText3;
    final gridColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Daily Rides',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Last 7 Days',
                  style: GoogleFonts.inter(fontSize: 11, color: text3Color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 10,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: gridColor,
                    strokeWidth: 0.5,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      getTitlesWidget: (value, meta) => Text(
                        '${value.toInt()}',
                        style: GoogleFonts.inter(fontSize: 10, color: text3Color),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                        if (value.toInt() < days.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              days[value.toInt()],
                              style: GoogleFonts.inter(fontSize: 10, color: text3Color),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: const [
                      FlSpot(0, 15),
                      FlSpot(1, 22),
                      FlSpot(2, 18),
                      FlSpot(3, 30),
                      FlSpot(4, 25),
                      FlSpot(5, 35),
                      FlSpot(6, 28),
                    ],
                    isCurved: true,
                    color: AppTheme.brandBlue,
                    barWidth: 2.5,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, bar, index) =>
                          FlDotCirclePainter(
                        radius: 3,
                        color: AppTheme.brandBlue,
                        strokeWidth: 2,
                        strokeColor: bg,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppTheme.brandBlue.withValues(alpha: 0.2),
                          AppTheme.brandBlue.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ],
                minY: 0,
                maxY: 45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRevenueChart(bool isDark) {
    final bg = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;
    final text3Color = isDark ? AppTheme.darkText3 : AppTheme.lightText3;
    final gridColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Revenue',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Last 7 Days',
                  style: GoogleFonts.inter(fontSize: 11, color: text3Color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 5000,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: gridColor,
                    strokeWidth: 0.5,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 42,
                      getTitlesWidget: (value, meta) => Text(
                        '₹${(value / 1000).toStringAsFixed(0)}k',
                        style: GoogleFonts.inter(fontSize: 10, color: text3Color),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                        if (value.toInt() < days.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              days[value.toInt()],
                              style: GoogleFonts.inter(fontSize: 10, color: text3Color),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                barGroups: [
                  _barGroup(0, 3200, isDark),
                  _barGroup(1, 4500, isDark),
                  _barGroup(2, 3800, isDark),
                  _barGroup(3, 6200, isDark),
                  _barGroup(4, 5100, isDark),
                  _barGroup(5, 7800, isDark),
                  _barGroup(6, 5500, isDark),
                ],
                maxY: 10000,
              ),
            ),
          ),
        ],
      ),
    );
  }

  BarChartGroupData _barGroup(int x, double y, bool isDark) {
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: y,
          gradient: const LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [AppTheme.brandTeal, AppTheme.brandBlue],
          ),
          width: 16,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(4),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickStats(bool isDark, DashboardStats stats, bool isDesktop) {
    final bg = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;
    final text2Color = isDark ? AppTheme.darkText2 : AppTheme.lightText2;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Driver Overview',
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _miniStat('Total', '${stats.totalDrivers}', AppTheme.brandBlue, isDark),
              const SizedBox(width: 16),
              _miniStat('Approved', '${stats.approvedDrivers}', AppTheme.success, isDark),
              const SizedBox(width: 16),
              _miniStat('Online', '${stats.onlineDrivers}', AppTheme.info, isDark),
              const SizedBox(width: 16),
              _miniStat('Pending', '${stats.pendingDrivers}', AppTheme.warning, isDark),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value, Color color, bool isDark) {
    final text2Color = isDark ? AppTheme.darkText2 : AppTheme.lightText2;
    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;

    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 12, color: text2Color),
          ),
        ],
      ),
    );
  }

  // ── Skeleton Loader ──
  Widget _buildSkeleton(bool isDark) {
    final bg = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final shimmer = isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Banner skeleton
          Container(
            height: 120,
            decoration: BoxDecoration(
              color: shimmer,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          const SizedBox(height: 24),
          // KPI cards skeleton
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 2.4,
            children: List.generate(
              6,
              (_) => Container(
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: shimmer),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Chart skeletons
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 270,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: shimmer),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Container(
                  height: 270,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: shimmer),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _KPIData {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String subtitle;

  const _KPIData(this.label, this.value, this.icon, this.color, this.subtitle);
}
