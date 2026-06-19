import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../db.dart';
import '../theme.dart';
import '../widgets.dart';
import 'statement.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  String period = 'month';
  String breakdownType = 'expense';
  int? accountId;
  String? label;
  List<String> allLabels = [];
  DateTime from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime to = DateTime.now();

  List<Map<String, Object?>> accounts = [];
  double income = 0, expense = 0;
  Map<String, double> catTotals = {};
  Map<String, int> catColor = {};
  List<MapEntry<String, List<double>>> monthly = []; // [(label,[inc,exp])]
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _init();
    bus.addListener(_load);
  }

  @override
  void dispose() {
    bus.removeListener(_load);
    super.dispose();
  }

  Future<void> _init() async {
    accounts = await DB.accounts();
    allLabels = await DB.distinctLabels();
    await _load();
  }

  void _applyPeriod() {
    final now = DateTime.now();
    switch (period) {
      case 'week':
        from = now.subtract(Duration(days: now.weekday - 1));
        to = now;
        break;
      case 'quarter':
        from = DateTime(now.year, now.month - 2, 1);
        to = now;
        break;
      case 'year':
        from = DateTime(now.year, 1, 1);
        to = now;
        break;
      case 'all':
        from = DateTime(2010);
        to = now;
        break;
      case 'custom':
        break;
      default:
        from = DateTime(now.year, now.month, 1);
        to = now;
    }
  }

  String _iso(DateTime d) => DateTime(d.year, d.month, d.day).toIso8601String();

  Future<void> _load() async {
    if (period != 'custom') _applyPeriod();
    final toExcl = _iso(to.add(const Duration(days: 1)));
    final rows = await DB.analyticsTxns(_iso(from), toExcl, accountId: accountId, label: label);
    double inc = 0, exp = 0;
    final ct = <String, double>{};
    final cc = <String, int>{};
    for (final r in rows) {
      final amt = ((r['amount'] as num?) ?? 0).toDouble();
      final t = r['type'] as String?;
      if (t == 'income') inc += amt;
      if (t == 'expense') exp += amt;
      if (t == breakdownType) {
        final name = r['catName'] as String? ?? 'Uncategorized';
        ct[name] = (ct[name] ?? 0) + amt;
        cc[name] = (r['catColor'] as int?) ?? 0xFF9E9E9E;
      }
    }
    // MoM last 6 months
    final now = DateTime.now();
    final start6 = DateTime(now.year, now.month - 5, 1);
    final rows6 = await DB.analyticsTxns(_iso(start6), _iso(now.add(const Duration(days: 1))), accountId: accountId, label: label);
    final buckets = <String, List<double>>{};
    for (int i = 5; i >= 0; i--) {
      final m = DateTime(now.year, now.month - i, 1);
      buckets['${m.year}-${m.month.toString().padLeft(2, '0')}'] = [0, 0];
    }
    for (final r in rows6) {
      final d = DateTime.tryParse(r['date'] as String? ?? '');
      if (d == null) continue;
      final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
      if (!buckets.containsKey(key)) continue;
      final amt = ((r['amount'] as num?) ?? 0).toDouble();
      if (r['type'] == 'income') buckets[key]![0] += amt;
      if (r['type'] == 'expense') buckets[key]![1] += amt;
    }
    if (!mounted) return;
    setState(() {
      income = inc;
      expense = exp;
      catTotals = ct;
      catColor = cc;
      monthly = buckets.entries.toList();
      loading = false;
    });
  }

  Future<void> _pickCustom() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2010),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: from, end: to),
    );
    if (r != null) {
      setState(() {
        period = 'custom';
        from = r.start;
        to = r.end;
      });
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final net = income - expense;
    final savings = income > 0 ? (net / income * 100) : 0.0;
    final sorted = catTotals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final totalBreak = catTotals.values.fold<double>(0, (s, v) => s + v);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.description_outlined),
            tooltip: 'Statement & Export',
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => StatementScreen(accountId: accountId))),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 30),
              children: [
                // period chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final p in const [
                      ['week', 'Week'], ['month', 'Month'], ['quarter', '3 Months'],
                      ['year', 'Year'], ['all', 'All'],
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(p[1]),
                          selected: period == p[0],
                          onSelected: (_) {
                            setState(() => period = p[0]);
                            _load();
                          },
                        ),
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.date_range, size: 16),
                      label: Text(period == 'custom'
                          ? '${DateFormat('d MMM').format(from)} - ${DateFormat('d MMM').format(to)}'
                          : 'Custom'),
                      onPressed: _pickCustom,
                    ),
                  ]),
                ),
                const SizedBox(height: 10),
                // account filter
                Row(children: [
                  const Icon(Icons.filter_alt_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButton<int?>(
                      value: accountId,
                      isExpanded: true,
                      underline: const SizedBox.shrink(),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('All accounts')),
                        for (final a in accounts)
                          DropdownMenuItem(value: a['id'] as int, child: Text(a['name'] as String? ?? '')),
                      ],
                      onChanged: (v) {
                        setState(() => accountId = v);
                        _load();
                      },
                    ),
                  ),
                ]),
                if (allLabels.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.label_outline, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButton<String?>(
                        value: label,
                        isExpanded: true,
                        underline: const SizedBox.shrink(),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('All labels')),
                          for (final l in allLabels)
                            DropdownMenuItem(value: l, child: Text(l)),
                        ],
                        onChanged: (v) {
                          setState(() => label = v);
                          _load();
                        },
                      ),
                    ),
                  ]),
                ],
                const SizedBox(height: 6),
                // KPI cards
                Row(children: [
                  _kpi('Income', income, [const Color(0xFF11998E), const Color(0xFF38EF7D)], Icons.south_west),
                  const SizedBox(width: 10),
                  _kpi('Expense', expense, [const Color(0xFFEB3349), const Color(0xFFF45C43)], Icons.north_east),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  _kpi('Net', net, [const Color(0xFF1A2980), const Color(0xFF26D0CE)], Icons.account_balance_wallet),
                  const SizedBox(width: 10),
                  _kpi('Savings %', savings, [const Color(0xFF8E2DE2), const Color(0xFF4A00E0)], Icons.percent, isPct: true),
                ]),
                const SizedBox(height: 16),
                // MoM trend
                _sectionTitle('Month-on-month trend'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 16, 12, 8),
                    child: SizedBox(height: 200, child: _momChart()),
                  ),
                ),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _legendDot(const Color(0xFF38EF7D), 'Income'),
                  const SizedBox(width: 16),
                  _legendDot(const Color(0xFFF45C43), 'Expense'),
                ]),
                const SizedBox(height: 16),
                // breakdown donut
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Breakdown by category', style: Theme.of(context).textTheme.titleMedium),
                  SegmentedButton<String>(
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    segments: const [
                      ButtonSegment(value: 'expense', label: Text('Out')),
                      ButtonSegment(value: 'income', label: Text('In')),
                    ],
                    selected: {breakdownType},
                    onSelectionChanged: (s) {
                      setState(() => breakdownType = s.first);
                      _load();
                    },
                  ),
                ]),
                const SizedBox(height: 8),
                if (sorted.isEmpty)
                  const Card(child: Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No data for this period'))))
                else
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(children: [
                        SizedBox(
                          height: 180,
                          child: PieChart(PieChartData(
                            sectionsSpace: 2,
                            centerSpaceRadius: 48,
                            sections: [
                              for (final e in sorted.take(8))
                                PieChartSectionData(
                                  value: e.value,
                                  color: Color(catColor[e.key] ?? 0xFF9E9E9E),
                                  title: totalBreak > 0 ? '${(e.value / totalBreak * 100).round()}%' : '',
                                  radius: 55,
                                  titleStyle: const TextStyle(
                                      color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                            ],
                          )),
                        ),
                        const SizedBox(height: 12),
                        for (final e in sorted.take(8))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(children: [
                              Container(width: 12, height: 12, decoration: BoxDecoration(
                                  color: Color(catColor[e.key] ?? 0xFF9E9E9E), borderRadius: BorderRadius.circular(3))),
                              const SizedBox(width: 10),
                              Expanded(child: Text(e.key, maxLines: 1, overflow: TextOverflow.ellipsis)),
                              Text(money(e.value), style: const TextStyle(fontWeight: FontWeight.w600)),
                            ]),
                          ),
                      ]),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _kpi(String label, double v, List<Color> grad, IconData ic, {bool isPct = false}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: grad, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: grad.last.withOpacity(0.35), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(ic, color: Colors.white70, size: 20),
          const SizedBox(height: 10),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(isPct ? '${v.toStringAsFixed(1)}%' : money(v),
                style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold)),
          ),
        ]),
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t, style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _legendDot(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(t, style: const TextStyle(fontSize: 12)),
      ]);

  Widget _momChart() {
    if (monthly.isEmpty) return const Center(child: Text('No data'));
    double maxV = 1;
    for (final e in monthly) {
      maxV = [maxV, e.value[0], e.value[1]].reduce((a, b) => a > b ? a : b);
    }
    return BarChart(BarChartData(
      maxY: maxV * 1.2,
      barTouchData: BarTouchData(enabled: true),
      gridData: FlGridData(show: false),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (v, meta) {
              final i = v.toInt();
              if (i < 0 || i >= monthly.length) return const SizedBox.shrink();
              final parts = monthly[i].key.split('-');
              const names = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(names[int.parse(parts[1])], style: const TextStyle(fontSize: 10)),
              );
            },
          ),
        ),
      ),
      barGroups: [
        for (int i = 0; i < monthly.length; i++)
          BarChartGroupData(x: i, barRods: [
            BarChartRodData(toY: monthly[i].value[0], color: const Color(0xFF38EF7D), width: 7, borderRadius: BorderRadius.circular(2)),
            BarChartRodData(toY: monthly[i].value[1], color: const Color(0xFFF45C43), width: 7, borderRadius: BorderRadius.circular(2)),
          ]),
      ],
    ));
  }
}
