import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../db.dart';
import 'statement.dart';
import '../widgets.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  int period = 1; // 0 = week, 1 = month, 2 = year
  double income = 0, expense = 0;
  List<Map<String, Object?>> catRows = [];
  List<MapEntry<String, List<double>>> months = [];
  List<Map<String, Object?>> accounts = [];
  Map<int, double> bals = {};

  @override
  void initState() {
    super.initState();
    _load();
    bus.addListener(_load);
  }

  @override
  void dispose() {
    bus.removeListener(_load);
    super.dispose();
  }

  (DateTime, DateTime) _range() {
    final now = DateTime.now();
    final to = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    switch (period) {
      case 0:
        return (to.subtract(const Duration(days: 7)), to);
      case 2:
        return (DateTime(now.year, 1, 1), to);
      default:
        return (DateTime(now.year, now.month, 1), to);
    }
  }

  Future<void> _load() async {
    final (from, to) = _range();
    final fIso = from.toIso8601String(), tIso = to.toIso8601String();
    final inc = await DB.totalFor('income', fIso, tIso);
    final exp = await DB.totalFor('expense', fIso, tIso);
    final cr = await DB.catTotals('expense', fIso, tIso);

    final now = DateTime.now();
    final start = DateTime(now.year, now.month - 5, 1);
    final rows = await DB.monthlyTotals(start.toIso8601String());
    final byM = <String, List<double>>{};
    for (int i = 0; i < 6; i++) {
      final d = DateTime(now.year, now.month - 5 + i, 1);
      byM['${d.year}-${d.month.toString().padLeft(2, '0')}'] = [0, 0];
    }
    for (final r in rows) {
      final k = r['m'] as String?;
      if (k == null || !byM.containsKey(k)) continue;
      final s = ((r['s'] as num?) ?? 0).toDouble();
      if (r['type'] == 'income') {
        byM[k]![0] = s;
      } else {
        byM[k]![1] = s;
      }
    }
    final m = byM.entries
        .map((e) => MapEntry(
            DateFormat('MMM').format(DateTime.parse('${e.key}-01')), e.value))
        .toList();

    final a = await DB.all('accounts', orderBy: 'name');
    final b = await DB.balances();

    if (!mounted) return;
    setState(() {
      income = inc;
      expense = exp;
      catRows = cr;
      months = m;
      accounts = a;
      bals = b;
    });
  }

  @override
  Widget build(BuildContext context) {
    final net = income - expense;
    final periodLabel = ['Last 7 days', 'This month', 'This year'][period];
    final totalExp = catRows.fold<double>(
        0, (s, r) => s + ((r['s'] as num?) ?? 0).toDouble());
    final netWorth =
        accounts.fold<double>(0, (s, a) => s + (bals[a['id']] ?? 0));

    return Scaffold(
      appBar: AppBar(title: const Text('Reports'), actions: [IconButton(tooltip: 'Statement & Export', icon: const Icon(Icons.description_outlined), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StatementScreen())))]),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Center(
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Week')),
                ButtonSegment(value: 1, label: Text('Month')),
                ButtonSegment(value: 2, label: Text('Year')),
              ],
              selected: {period},
              onSelectionChanged: (s) {
                setState(() => period = s.first);
                _load();
              },
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Text(periodLabel, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  _sum('Income', income, Colors.green),
                  _sum('Expense', expense, Colors.red),
                  _sum('Net', net, net >= 0 ? Colors.green : Colors.red),
                ]),
              ]),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Spending by category \u2014 $periodLabel',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 12),
                  if (catRows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: Text('No expenses in this period')),
                    )
                  else ...[
                    SizedBox(
                      height: 180,
                      child: PieChart(PieChartData(
                        centerSpaceRadius: 36,
                        sectionsSpace: 2,
                        sections: [
                          for (final r in catRows)
                            PieChartSectionData(
                              value: ((r['s'] as num?) ?? 0).toDouble(),
                              color: Color((r['col'] as int?) ?? 0xFF9E9E9E),
                              title: '',
                              radius: 56,
                            ),
                        ],
                      )),
                    ),
                    const SizedBox(height: 12),
                    for (final r in catRows)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(children: [
                          CircleAvatar(
                              radius: 6,
                              backgroundColor:
                                  Color((r['col'] as int?) ?? 0xFF9E9E9E)),
                          const SizedBox(width: 8),
                          Expanded(child: Text(r['n'] as String? ?? 'Uncategorized')),
                          Text(money(((r['s'] as num?) ?? 0)),
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(width: 8),
                          Text(
                            totalExp > 0
                                ? '${(((r['s'] as num?) ?? 0).toDouble() / totalExp * 100).toStringAsFixed(0)}%'
                                : '',
                            style: const TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ]),
                      ),
                  ],
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Income vs Expense \u2014 last 6 months',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 16),
                  SizedBox(height: 200, child: _bar()),
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
                    CircleAvatar(radius: 5, backgroundColor: Colors.green),
                    SizedBox(width: 4),
                    Text('Income  ', style: TextStyle(fontSize: 12)),
                    CircleAvatar(radius: 5, backgroundColor: Colors.redAccent),
                    SizedBox(width: 4),
                    Text('Expense', style: TextStyle(fontSize: 12)),
                  ]),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Net worth', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  for (final a in accounts)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(children: [
                        Icon(iconOf(a['icon']),
                            size: 18,
                            color: Color((a['color'] as int?) ?? 0xFF607D8B)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(a['name'] as String? ?? '')),
                        Text(money(bals[a['id']] ?? 0),
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: (bals[a['id']] ?? 0) < 0 ? Colors.red : null)),
                      ]),
                    ),
                  const Divider(),
                  Row(children: [
                    const Expanded(
                        child: Text('Total',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                    Text(money(netWorth),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sum(String k, double v, Color c) => Column(children: [
        Text(k, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(money(v), style: TextStyle(fontWeight: FontWeight.bold, color: c)),
      ]);

  Widget _bar() {
    double maxY = 1;
    for (final m in months) {
      for (final v in m.value) {
        if (v > maxY) maxY = v;
      }
    }
    return BarChart(BarChartData(
      maxY: maxY * 1.2,
      gridData: const FlGridData(show: false),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (v, meta) {
              final i = v.toInt();
              if (i < 0 || i >= months.length) return const SizedBox();
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(months[i].key, style: const TextStyle(fontSize: 10)),
              );
            },
          ),
        ),
      ),
      barGroups: [
        for (int i = 0; i < months.length; i++)
          BarChartGroupData(x: i, barRods: [
            BarChartRodData(
                toY: months[i].value[0],
                color: Colors.green,
                width: 6,
                borderRadius: BorderRadius.circular(2)),
            BarChartRodData(
                toY: months[i].value[1],
                color: Colors.redAccent,
                width: 6,
                borderRadius: BorderRadius.circular(2)),
          ]),
      ],
    ));
  }
}
