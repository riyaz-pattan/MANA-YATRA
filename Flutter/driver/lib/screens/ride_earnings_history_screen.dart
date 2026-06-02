// lib/screens/ride_earnings_history_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import '../config/theme.dart';
import '../utils/skeleton.dart';
import 'report_issue_screen.dart';

class RideEarningsHistoryScreen extends StatefulWidget {
  const RideEarningsHistoryScreen({super.key});

  @override
  State<RideEarningsHistoryScreen> createState() => _RideEarningsHistoryScreenState();
}

class _RideEarningsHistoryScreenState extends State<RideEarningsHistoryScreen> {
  String _selectedFilter = 'Today';
  final List<String> _filters = ['Today', 'This Week', 'This Month', 'All Time'];
  int _touchedIndex = -1;
  Stream<QuerySnapshot>? _ridesStream;

  // Calendar State
  DateTime _focusedDay = DateTime.utc(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _ridesStream = FirebaseFirestore.instance
          .collection('rides')
          .where('driverId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'completed')
          .snapshots();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ridesStream == null) {
      return const Scaffold(body: Center(child: Text("Not logged in")));
    }

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: StreamBuilder<QuerySnapshot>(
        stream: _ridesStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Scaffold(
              appBar: AppBar(backgroundColor: AppTheme.bg, elevation: 0),
              body: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: 4,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, __) => const RideHistoryCardSkeleton(),
              ),
            );
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error loading history: ${snapshot.error}'));
          }

          final allDocs = snapshot.data?.docs.toList() ?? [];
          final now = DateTime.now();

          // Filter documents
          final filteredDocs = allDocs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final timestamp = (data['completedAt'] ?? data['createdAt']) as Timestamp?;
            if (timestamp == null) return false;
            final dt = timestamp.toDate().toLocal();

            if (_selectedFilter == 'Today') {
              return dt.year == now.year && dt.month == now.month && dt.day == now.day;
            } else if (_selectedFilter == 'This Week') {
              final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
              return dt.isAfter(DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day)) || 
                     (dt.year == startOfWeek.year && dt.month == startOfWeek.month && dt.day == startOfWeek.day);
            } else if (_selectedFilter == 'This Month') {
              return dt.year == now.year && dt.month == now.month;
            }
            return true; // All Time
          }).toList();

          filteredDocs.sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            final aTime = (aData['completedAt'] ?? aData['createdAt']) as Timestamp?;
            final bTime = (bData['completedAt'] ?? bData['createdAt']) as Timestamp?;
            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return 1;
            if (bTime == null) return -1;
            return bTime.compareTo(aTime);
          });

          double totalEarnings = 0;
          for (var doc in filteredDocs) {
            final data = doc.data() as Map<String, dynamic>;
            final fareStr = (data['finalPrice'] ?? data['riderBid'] ?? 0).toString();
            totalEarnings += double.tryParse(fareStr) ?? 0.0;
          }

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                title: Text('Earnings History', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: AppTheme.text)),
                backgroundColor: AppTheme.bg,
                elevation: 0,
                pinned: true,
                iconTheme: const IconThemeData(color: AppTheme.text),
              ),
              SliverToBoxAdapter(
                child: Container(
                  color: AppTheme.bg,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: _buildFilters(),
                ),
              ),
              SliverToBoxAdapter(
                child: Container(
                  color: AppTheme.bg,
                  child: Column(
                    children: [
                      _buildEarningsSummary(totalEarnings, filteredDocs.length),
                      if (filteredDocs.isNotEmpty) _buildDataVisualizer(filteredDocs, totalEarnings),
                      const Divider(color: AppTheme.border, height: 1),
                    ],
                  ),
                ),
              ),
              if (filteredDocs.isEmpty)
                SliverFillRemaining(
                  child: _buildEmptyState(),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final ride = filteredDocs[index].data() as Map<String, dynamic>;
                        ride['id'] = filteredDocs[index].id;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _buildRideCard(ride),
                        );
                      },
                      childCount: filteredDocs.length,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: _filters.map((filter) {
          final isSelected = _selectedFilter == filter;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(
                filter,
                style: GoogleFonts.inter(
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? Colors.white : AppTheme.text2,
                ),
              ),
              selected: isSelected,
              selectedColor: AppTheme.primary,
              backgroundColor: AppTheme.bg,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: isSelected ? AppTheme.primary : AppTheme.border)),
              showCheckmark: false,
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _selectedFilter = filter;
                    _touchedIndex = -1; // reset chart touch when filtering
                    _selectedDay = null; // reset calendar selection
                    _focusedDay = DateTime.utc(DateTime.now().year, DateTime.now().month, DateTime.now().day); // reset calendar focus
                  });
                }
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEarningsSummary(double total, int rides) {
    final double commissionSaved = total * 0.25;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.bg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Earnings', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.text2, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      Text('₹${total.toStringAsFixed(0)}', style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w900, color: AppTheme.success)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.bg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Rides', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.text2, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      Text('$rides', style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w900, color: AppTheme.text)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [AppTheme.success.withValues(alpha: 0.1), AppTheme.success.withValues(alpha: 0.05)]),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.success.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: AppTheme.success.withValues(alpha: 0.2), blurRadius: 10)]),
                  child: const Icon(Icons.savings_outlined, color: AppTheme.success, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Zero Commission Savings', style: GoogleFonts.inter(fontSize: 14, color: AppTheme.success, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text('You saved ~₹${commissionSaved.toStringAsFixed(0)} on commissions!', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.text2)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataVisualizer(List<DocumentSnapshot> docs, double totalEarnings) {
    if (_selectedFilter == 'Today') return const SizedBox(height: 16);
    if (_selectedFilter == 'This Week') return _buildDynamicChart(docs);
    return _buildCalendarView(docs);
  }

  Widget _buildDynamicChart(List<DocumentSnapshot> docs) {
    Map<int, Map<String, dynamic>> dailyData = {};
    double maxY = 100;

    for (var doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final dt = ((data['completedAt'] ?? data['createdAt']) as Timestamp).toDate().toLocal();
      final fare = double.tryParse((data['finalPrice'] ?? data['riderBid'] ?? 0).toString()) ?? 0;
      final dayIndex = dt.weekday - 1; // 0 = Mon, 6 = Sun
      
      dailyData.putIfAbsent(dayIndex, () => {'earnings': 0.0, 'rides': 0});
      dailyData[dayIndex]!['earnings'] += fare;
      dailyData[dayIndex]!['rides'] += 1;
    }

    for (var v in dailyData.values) {
      if (v['earnings'] > maxY) maxY = v['earnings'];
    }

    return Container(
      height: 200,
      padding: const EdgeInsets.only(top: 24, left: 16, right: 16, bottom: 16),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY * 1.2,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => Colors.black87,
              tooltipRoundedRadius: 8,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final ridesCount = dailyData[group.x]?['rides'] ?? 0;
                return BarTooltipItem(
                  '₹${rod.toY.toStringAsFixed(0)}\n',
                  GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  children: [
                    TextSpan(
                      text: '$ridesCount Rides',
                      style: GoogleFonts.inter(color: Colors.white70, fontWeight: FontWeight.normal, fontSize: 11),
                    )
                  ],
                );
              },
            ),
            touchCallback: (FlTouchEvent event, barTouchResponse) {
              setState(() {
                if (!event.isInterestedForInteractions || barTouchResponse == null || barTouchResponse.spot == null) {
                  _touchedIndex = -1;
                  return;
                }
                _touchedIndex = barTouchResponse.spot!.touchedBarGroupIndex;
              });
            },
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                  if (value.toInt() >= 0 && value.toInt() < 7) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(days[value.toInt()], style: GoogleFonts.inter(fontSize: 10, color: AppTheme.text3, fontWeight: FontWeight.w600)),
                    );
                  }
                  return const Text('');
                },
              ),
            ),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(7, (i) {
            final isTouched = i == _touchedIndex;
            return _makeBar(i, dailyData[i]?['earnings'] ?? 0.0, isTouched);
          }),
        ),
      ),
    );
  }

  BarChartGroupData _makeBar(int x, double y, bool isTouched) {
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: y,
          color: isTouched ? AppTheme.success : AppTheme.primary,
          width: 18,
          borderRadius: BorderRadius.circular(4),
          backDrawRodData: BackgroundBarChartRodData(
            show: true,
            toY: 0,
            color: AppTheme.bg2,
          ),
        ),
      ],
    );
  }

  Widget _buildCalendarView(List<DocumentSnapshot> docs) {
    Map<DateTime, Map<String, dynamic>> calendarData = {};
    for (var doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final dt = ((data['completedAt'] ?? data['createdAt']) as Timestamp).toDate().toLocal();
      final cleanDay = DateTime.utc(dt.year, dt.month, dt.day); // ignore time
      final fare = double.tryParse((data['finalPrice'] ?? data['riderBid'] ?? 0).toString()) ?? 0;
      
      calendarData.putIfAbsent(cleanDay, () => {'earnings': 0.0, 'rides': 0});
      calendarData[cleanDay]!['earnings'] += fare;
      calendarData[cleanDay]!['rides'] += 1;
    }

    final isMonthLocked = _selectedFilter == 'This Month';
    final now = DateTime.now();
    final firstDay = isMonthLocked ? DateTime.utc(now.year, now.month, 1) : DateTime.utc(2023, 1, 1);
    final lastDay = isMonthLocked ? DateTime.utc(now.year, now.month + 1, 0) : DateTime.utc(2030, 12, 31);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TableCalendar(
            firstDay: firstDay,
            lastDay: lastDay,
            focusedDay: _focusedDay,
            currentDay: DateTime.utc(now.year, now.month, now.day),
            headerStyle: HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
              titleTextStyle: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.text),
              leftChevronVisible: !isMonthLocked,
              rightChevronVisible: !isMonthLocked,
            ),
            calendarStyle: CalendarStyle(
              todayDecoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.5), shape: BoxShape.circle),
              selectedDecoration: BoxDecoration(
                color: AppTheme.primary,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              defaultTextStyle: GoogleFonts.inter(color: AppTheme.text2),
              weekendTextStyle: GoogleFonts.inter(color: AppTheme.text),
            ),
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });
            },
            onPageChanged: (focusedDay) {
              _focusedDay = focusedDay;
            },
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (context, day, focusedDay) {
                final cleanDay = DateTime.utc(day.year, day.month, day.day);
                if (calendarData.containsKey(cleanDay)) {
                  return Container(
                    margin: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text('${day.day}', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppTheme.success)),
                    ),
                  );
                }
                return null;
              },
            ),
          ),
        ),
        if (_selectedDay != null) ...[
          const SizedBox(height: 16),
          _buildCalendarSummaryCard(calendarData),
        ]
      ],
    );
  }

  Widget _buildCalendarSummaryCard(Map<DateTime, Map<String, dynamic>> calendarData) {
    final cleanSelected = DateTime.utc(_selectedDay!.year, _selectedDay!.month, _selectedDay!.day);
    final data = calendarData[cleanSelected];
    
    if (data == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          padding: const EdgeInsets.all(16),
          width: double.infinity,
          decoration: BoxDecoration(color: AppTheme.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.border)),
          child: Text('No rides completed on ${DateFormat('MMM dd').format(cleanSelected)}', textAlign: TextAlign.center, style: GoogleFonts.inter(color: AppTheme.text3)),
        ),
      );
    }

    final earnings = (data['earnings'] as double).toStringAsFixed(0);
    final rides = data['rides'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        width: double.infinity,
        decoration: BoxDecoration(color: AppTheme.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.success.withValues(alpha: 0.3)), boxShadow: [BoxShadow(color: AppTheme.success.withValues(alpha: 0.05), blurRadius: 10)]),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, color: AppTheme.success, size: 20),
            const SizedBox(width: 8),
            Text(
              '${DateFormat('MMM dd').format(cleanSelected)}:',
              style: GoogleFonts.inter(color: AppTheme.text, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            Text(
              '₹$earnings',
              style: GoogleFonts.inter(color: AppTheme.success, fontWeight: FontWeight.bold),
            ),
            Text(
              ' earned • $rides rides',
              style: GoogleFonts.inter(color: AppTheme.text2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: AppTheme.bg, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20)]),
            child: const Icon(Icons.account_balance_wallet_outlined, size: 48, color: AppTheme.text3),
          ),
          const SizedBox(height: 24),
          Text(
            'No rides found',
            style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.text),
          ),
          const SizedBox(height: 8),
          Text(
            'Complete rides in this period to see earnings.',
            style: GoogleFonts.inter(fontSize: 14, color: AppTheme.text2),
          ),
        ],
      ),
    );
  }

  Widget _buildRideCard(Map<String, dynamic> ride) {
    final pickup = ride['pickup'] != null ? (ride['pickup']['display_name'] ?? ride['pickup']['short_name'] ?? 'Unknown Pickup') : 'Unknown Pickup';
    final dropoff = ride['drop'] != null ? (ride['drop']['display_name'] ?? ride['drop']['short_name'] ?? 'Unknown Dropoff') : 'Unknown Dropoff';
    
    // Fallback to riderBid if finalPrice is missing, exactly like Rider App's history screen
    final fare = (ride['finalPrice'] ?? ride['riderBid'] ?? 0).toString();
    
    final timestamp = (ride['completedAt'] ?? ride['createdAt']) as Timestamp?;
    final date = timestamp != null ? DateFormat('MMM dd, hh:mm a').format(timestamp.toDate().toLocal()) : 'Unknown Date';
    
    final distance = ride['distanceKm']?.toStringAsFixed(1) ?? '0.0';
    final duration = ride['durationMin']?.toString() ?? '0';
    final vehicleType = ride['vehicleType'] ?? 'Unknown';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(date, style: GoogleFonts.inter(fontSize: 13, color: AppTheme.text2, fontWeight: FontWeight.w600)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('+₹$fare', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.success)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildInfoChip(Icons.electric_rickshaw, vehicleType.toString().toUpperCase()),
              const SizedBox(width: 12),
              _buildInfoChip(Icons.route, '$distance km'),
              const SizedBox(width: 12),
              _buildInfoChip(Icons.schedule, '$duration min'),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: AppTheme.border, height: 1),
          const SizedBox(height: 16),
          _buildLocationRow(Icons.my_location, AppTheme.primary, pickup.toString()),
          const SizedBox(height: 16),
          _buildLocationRow(Icons.location_on, AppTheme.danger, dropoff.toString()),
          const SizedBox(height: 16),
          const Divider(color: AppTheme.border, height: 1),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ReportIssueScreen(initialRideId: ride['id'])),
                );
              },
              icon: const Icon(Icons.support_agent, size: 18),
              label: Text('Contact Support', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.text,
                side: const BorderSide(color: AppTheme.border),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppTheme.text3),
        const SizedBox(width: 4),
        Text(text, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.text2)),
      ],
    );
  }

  Widget _buildLocationRow(IconData icon, Color color, String address) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            address,
            style: GoogleFonts.inter(fontSize: 13, color: AppTheme.text, fontWeight: FontWeight.w500),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
