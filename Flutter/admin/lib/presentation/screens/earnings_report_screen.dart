// lib/presentation/screens/earnings_report_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/auth_provider.dart';
import 'financial_pdf_export.dart';

class EarningsReportScreen extends ConsumerStatefulWidget {
  const EarningsReportScreen({super.key});

  @override
  ConsumerState<EarningsReportScreen> createState() => _EarningsReportScreenState();
}

class _EarningsReportScreenState extends ConsumerState<EarningsReportScreen> {
  String _dateFilter = 'All Time'; // Today, This Week, This Month, All Time
  String _methodFilter = 'All'; // All, UPI, Cash
  Set<String> _selectedTransactions = {};
  
  double _totalEarnings = 0;
  int _activeSubscriptions = 0;
  int _expiredSubscriptions = 0;
  bool _isLoadingStats = true;

  @override
  void initState() {
    super.initState();
    _fetchStats();
  }

  void _fetchStats() async {
    setState(() => _isLoadingStats = true);
    try {
      // 1. Total Earnings via Aggregation (1 read!)
      Query query = FirebaseFirestore.instance.collection('payments');
      if (_dateFilter != 'All Time') {
        final now = DateTime.now();
        DateTime start = now;
        if (_dateFilter == 'Today') start = DateTime(now.year, now.month, now.day);
        else if (_dateFilter == 'Last 7 Days') start = now.subtract(const Duration(days: 7));
        else if (_dateFilter == 'This Month') start = DateTime(now.year, now.month, 1);
        query = query.where('createdAt', isGreaterThanOrEqualTo: start);
      }
      
      if (_methodFilter != 'All') query = query.where('method', isEqualTo: _methodFilter.toLowerCase());
      
      final aggSnap = await query.aggregate(sum('amount')).get();
      _totalEarnings = aggSnap.getSum('amount') ?? 0.0;
      
      // 2. Active vs Expired Subscriptions via Count Aggregation (2 reads!)
      final nowTimestamp = Timestamp.now();
      final activeSnap = await FirebaseFirestore.instance.collection('drivers')
          .where('subscriptionActiveUntil', isGreaterThan: nowTimestamp)
          .count()
          .get();
          
      final expiredSnap = await FirebaseFirestore.instance.collection('drivers')
          .where('subscriptionActiveUntil', isLessThanOrEqualTo: nowTimestamp)
          .count()
          .get();
          
      _activeSubscriptions = activeSnap.count ?? 0;
      _expiredSubscriptions = expiredSnap.count ?? 0;
      
    } catch(e) {
      debugPrint("Error fetching stats: $e");
    } finally {
      if (mounted) setState(() => _isLoadingStats = false);
    }
  }

  Stream<QuerySnapshot> _getTransactionsStream() {
    Query query = FirebaseFirestore.instance.collection('payments');
    if (_dateFilter != 'All Time') {
      final now = DateTime.now();
      DateTime start = now;
      if (_dateFilter == 'Today') start = DateTime(now.year, now.month, now.day);
      else if (_dateFilter == 'Last 7 Days') start = now.subtract(const Duration(days: 7));
      else if (_dateFilter == 'This Month') start = DateTime(now.year, now.month, 1);
      query = query.where('createdAt', isGreaterThanOrEqualTo: start);
    }
    if (_methodFilter != 'All') query = query.where('method', isEqualTo: _methodFilter.toLowerCase());
    return query.orderBy('createdAt', descending: true).limit(100).snapshots();
  }

  void _exportSelected(List<QueryDocumentSnapshot> docs) {
    if (_selectedTransactions.isEmpty) return;
    
    final selectedDocs = docs.where((doc) => _selectedTransactions.contains(doc.id)).toList();
    final List<Map<String, dynamic>> exportData = selectedDocs.map((d) {
      final data = d.data() as Map<String, dynamic>;
      final createdAt = data['createdAt'];
      DateTime? dt;
      if (createdAt is Timestamp) dt = createdAt.toDate();
      
      return {
        'id': d.id,
        'amount': data['amount'],
        'method': data['method'],
        'createdAt': dt,
      };
    }).toList();
    
    FinancialPdfExport.generateAndPrint(exportData);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 1024;
    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isDesktop ? 32 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header & Export ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Financials & Analytics',
                  style: GoogleFonts.inter(
                    fontSize: isDesktop ? 24 : 20,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              StreamBuilder<QuerySnapshot>(
                stream: _getTransactionsStream(),
                builder: (context, snapshot) {
                  return OutlinedButton.icon(
                    onPressed: _selectedTransactions.isNotEmpty && snapshot.hasData
                        ? () => _exportSelected(snapshot.data!.docs)
                        : null,
                    icon: const Icon(Icons.picture_as_pdf, size: 16),
                    label: Text('Save PDF (${_selectedTransactions.length})'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                  );
                }
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // ── Filters ──
          Row(
            children: [
              _buildDropdown('Date Range', ['All Time', 'Today', 'Last 7 Days', 'This Month'], _dateFilter, (v) {
                setState(() { _dateFilter = v!; _selectedTransactions.clear(); });
                _fetchStats();
              }, isDark),
              const SizedBox(width: 16),
              _buildDropdown('Payment Mode', ['All', 'UPI', 'Card', 'Netbanking'], _methodFilter, (v) {
                setState(() { _methodFilter = v!; _selectedTransactions.clear(); });
                _fetchStats();
              }, isDark),
            ],
          ),
          const SizedBox(height: 24),

          // ── Top Metrics Row ──
          if (_isLoadingStats)
            const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
          else if (isDesktop)
            Row(
              children: [
                Expanded(flex: 2, child: _buildTotalEarningsCard()),
                const SizedBox(width: 16),
                Expanded(child: _buildSubMetricCard('Active Drivers', _activeSubscriptions.toString(), Icons.check_circle_outline, AppTheme.success, isDark)),
                const SizedBox(width: 16),
                Expanded(child: _buildSubMetricCard('Expired Drivers', _expiredSubscriptions.toString(), Icons.warning_amber_rounded, AppTheme.danger, isDark)),
              ],
            )
          else
            Column(
              children: [
                _buildTotalEarningsCard(),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _buildSubMetricCard('Active Drivers', _activeSubscriptions.toString(), Icons.check_circle_outline, AppTheme.success, isDark)),
                    const SizedBox(width: 16),
                    Expanded(child: _buildSubMetricCard('Expired Drivers', _expiredSubscriptions.toString(), Icons.warning_amber_rounded, AppTheme.danger, isDark)),
                  ],
                ),
              ],
            ),
            
          const SizedBox(height: 32),

          // ── Transactions & Chart ──
          StreamBuilder<QuerySnapshot>(
            stream: _getTransactionsStream(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Center(child: Text('Error loading transactions', style: TextStyle(color: textColor)));
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

              final docs = snapshot.data!.docs;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (docs.isNotEmpty) ...[
                    // Chart
                    Container(
                      height: 250,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                      ),
                      child: _buildRevenueChart(docs, isDark),
                    ),
                    const SizedBox(height: 32),
                  ],

                  Text('Transactions Ledger', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: textColor)),
                  const SizedBox(height: 16),

                  if (docs.isEmpty)
                    Center(child: Padding(padding: const EdgeInsets.all(40), child: Text('No transactions found.', style: TextStyle(color: textColor))))
                  else
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minWidth: width - (isDesktop ? 300 : 32)),
                            child: DataTable(
                              headingRowColor: WidgetStateProperty.all(isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2),
                              dataRowMinHeight: 64,
                              dataRowMaxHeight: 64,
                              columns: [
                                DataColumn(
                                  label: Checkbox(
                                    value: _selectedTransactions.length == docs.length && docs.isNotEmpty,
                                    onChanged: (val) {
                                      setState(() {
                                        if (val == true) _selectedTransactions.addAll(docs.map((d) => d.id));
                                        else _selectedTransactions.clear();
                                      });
                                    },
                                    activeColor: AppTheme.brandBlue,
                                  ),
                                ),
                                const DataColumn(label: Text('Transaction ID')),
                                const DataColumn(label: Text('Date')),
                                const DataColumn(label: Text('Type')),
                                const DataColumn(label: Text('Method')),
                                const DataColumn(label: Text('Status')),
                                const DataColumn(label: Text('Amount')),
                              ],
                              rows: docs.map((doc) {
                                final data = doc.data() as Map<String, dynamic>;
                                final isSelected = _selectedTransactions.contains(doc.id);
                                return _buildTransactionRow(doc.id, data, isSelected, isDark);
                              }).toList(),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown(String label, List<String> items, String value, Function(String?) onChanged, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 12, color: isDark ? AppTheme.darkText2 : AppTheme.lightText2)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              dropdownColor: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
              icon: Icon(Icons.keyboard_arrow_down, color: isDark ? AppTheme.darkText2 : AppTheme.lightText2),
              items: items.map((i) => DropdownMenuItem(value: i, child: Text(i, style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText)))).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTotalEarningsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [AppTheme.brandTeal, AppTheme.brandBlue], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: AppTheme.brandBlue.withValues(alpha: 0.2), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Total Subscription Revenue', style: GoogleFonts.inter(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Text('₹${_totalEarnings.toStringAsFixed(2)}', style: GoogleFonts.inter(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _buildSubMetricCard(String title, String value, IconData icon, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.inter(color: isDark ? AppTheme.darkText2 : AppTheme.lightText2, fontSize: 12)),
                Text(value, style: GoogleFonts.inter(color: isDark ? AppTheme.darkText : AppTheme.lightText, fontSize: 24, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRevenueChart(List<QueryDocumentSnapshot> docs, bool isDark) {
    // Group earnings by day
    final Map<int, double> dailyEarnings = {};
    for (var doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final amt = ((data['amount'] ?? 0) as num).toDouble();
      final created = data['createdAt'] as Timestamp?;
      if (created != null) {
        final dt = created.toDate();
        final dayKey = DateTime(dt.year, dt.month, dt.day).millisecondsSinceEpoch;
        dailyEarnings[dayKey] = (dailyEarnings[dayKey] ?? 0) + amt;
      }
    }

    final sortedKeys = dailyEarnings.keys.toList()..sort();
    final spots = <FlSpot>[];
    double maxAmt = 0;
    
    for (int i = 0; i < sortedKeys.length; i++) {
      final amt = dailyEarnings[sortedKeys[i]]!;
      if (amt > maxAmt) maxAmt = amt;
      spots.add(FlSpot(i.toDouble(), amt));
    }

    if (spots.isEmpty) return const Center(child: Text("No chart data"));

    return LineChart(
      LineChartData(
        gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (v) => FlLine(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder, strokeWidth: 1)),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= sortedKeys.length) return const SizedBox();
                final dt = DateTime.fromMillisecondsSinceEpoch(sortedKeys[index]);
                return Padding(padding: const EdgeInsets.only(top: 8), child: Text(DateFormat('MM/dd').format(dt), style: TextStyle(color: isDark ? AppTheme.darkText2 : AppTheme.lightText2, fontSize: 10)));
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                return Text(value.toInt().toString(), style: TextStyle(color: isDark ? AppTheme.darkText2 : AppTheme.lightText2, fontSize: 10));
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: (spots.length - 1).toDouble(),
        minY: 0,
        maxY: maxAmt * 1.2,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: AppTheme.brandBlue,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(show: true, color: AppTheme.brandBlue.withValues(alpha: 0.1)),
          ),
        ],
      ),
    );
  }

  DataRow _buildTransactionRow(String id, Map<String, dynamic> data, bool isSelected, bool isDark) {
    final amount = ((data['amount'] ?? 0) as num).toDouble();
    final method = data['method'] ?? 'UPI';
    final createdAt = data['createdAt'] as Timestamp?;
    final dateStr = createdAt != null ? DateFormat('MMM dd, yyyy HH:mm').format(createdAt.toDate()) : 'Unknown';
    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;
    final text2Color = isDark ? AppTheme.darkText2 : AppTheme.lightText2;

    return DataRow(
      selected: isSelected,
      color: WidgetStateProperty.resolveWith((states) => isSelected ? AppTheme.brandBlue.withValues(alpha: 0.1) : null),
      cells: [
        DataCell(Checkbox(
          value: isSelected,
          onChanged: (val) {
            setState(() {
              if (val == true) _selectedTransactions.add(id);
              else _selectedTransactions.remove(id);
            });
          },
          activeColor: AppTheme.brandBlue,
        )),
        DataCell(Text(id.substring(0, 10).toUpperCase(), style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600, color: text2Color))),
        DataCell(Text(dateStr, style: GoogleFonts.inter(color: textColor))),
        DataCell(Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: AppTheme.brandBlue.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: const Icon(Icons.subscriptions, size: 14, color: AppTheme.brandBlue),
            ),
            const SizedBox(width: 8),
            Text('Subscription', style: GoogleFonts.inter(fontWeight: FontWeight.w500, color: textColor)),
          ],
        )),
        DataCell(Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2, borderRadius: BorderRadius.circular(4)),
          child: Text(method, style: GoogleFonts.inter(fontSize: 12, color: text2Color)),
        )),
        DataCell(Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: AppTheme.success.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
          child: Text('SUCCESS', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.success)),
        )),
        DataCell(Text('+₹${amount.toStringAsFixed(0)}', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: AppTheme.success, fontSize: 15))),
      ],
    );
  }
}
