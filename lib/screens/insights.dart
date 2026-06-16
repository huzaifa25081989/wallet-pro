import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../db.dart';
import '../theme.dart';
import '../widgets.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});
  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  bool loading = true;
  int score = 0;
  Map<String, int> parts = {};
  List<_Insight> insights = [];
  double savingsRate = 0, debtRatio = 0, emergencyMonths = 0, diversification = 0;

  @override
  void initState() {
    super.initState();
    _compute();
  }

  String _iso(DateTime d) => DateTime(d.year, d.month, d.day).toIso8601String();

  Future<void> _compute() async {
    final now = DateTime.now();
    final accts = await DB.accounts();
    final bals = await DB.balances();

    double assets = 0, liab = 0, investments = 0, liquid = 0;
    for (final a in accts) {
      final v = bals[a['id']] ?? 0;
      final grp = (a['grp'] as String?) ?? 'main';
      if (v >= 0) {
        assets += v;
      } else {
        liab += -v;
      }
      if (grp == 'investment') investments += v > 0 ? v : 0;
      if (grp == 'main' && v > 0) liquid += v;
    }
    final netWorth = assets - liab;

    // last 3 full-ish months income/expense
    final from3 = DateTime(now.year, now.month - 3, 1);
    final income3 = await DB.totalFor('income', _iso(from3), _iso(now.add(const Duration(days: 1))));
    final expense3 = await DB.totalFor('expense', _iso(from3), _iso(now.add(const Duration(days: 1))));
    final avgMonthlyExpense = expense3 <= 0 ? 1 : expense3 / 3;

    savingsRate = income3 <= 0 ? 0 : ((income3 - expense3) / income3).clamp(-1, 1).toDouble();
    debtRatio = assets <= 0 ? (liab > 0 ? 1 : 0) : (liab / assets).clamp(0, 1).toDouble();
    emergencyMonths = liquid / avgMonthlyExpense;
    diversification = netWorth <= 0 ? 0 : (investments / netWorth).clamp(0, 1).toDouble();

    // component scores (each /25)
    final sSav = ((savingsRate.clamp(0, 0.4) / 0.4) * 25).round();
    final sDebt = ((1 - debtRatio) * 25).round();
    final sEmer = ((emergencyMonths.clamp(0, 6) / 6) * 25).round();
    final sDiv = ((diversification.clamp(0, 0.4) / 0.4) * 25).round();
    parts = {
      'Savings rate': sSav,
      'Low debt': sDebt,
      'Emergency fund': sEmer,
      'Diversification': sDiv,
    };
    score = (sSav + sDebt + sEmer + sDiv).clamp(0, 100);

    // ---- insights ----
    final ins = <_Insight>[];

    // this vs last month by category
    final thisFrom = DateTime(now.year, now.month, 1);
    final lastFrom = DateTime(now.year, now.month - 1, 1);
    final thisCat = await DB.catTotals('expense', _iso(thisFrom), _iso(now.add(const Duration(days: 1))));
    final lastCat = await DB.catTotals('expense', _iso(lastFrom), _iso(thisFrom));
    final lastMap = {for (final r in lastCat) (r['n'] as String? ?? '?'): ((r['s'] as num?) ?? 0).toDouble()};
    String? bigName;
    double bigPct = 0, bigNow = 0;
    for (final r in thisCat) {
      final n = r['n'] as String? ?? '?';
      final nowV = ((r['s'] as num?) ?? 0).toDouble();
      final lastV = lastMap[n] ?? 0;
      if (lastV > 0) {
        final pct = (nowV - lastV) / lastV;
        if (pct > bigPct && nowV > lastV) {
          bigPct = pct;
          bigName = n;
          bigNow = nowV;
        }
      }
    }
    if (bigName != null && bigPct >= 0.15) {
      ins.add(_Insight(Icons.trending_up, Colors.orange,
          'Spending up on $bigName',
          'You spent ${(bigPct * 100).round()}% more on $bigName this month (${money(bigNow)}). Worth a look.'));
    }

    // weekend spending
    final monthTxns = await DB.txnsRaw(_iso(thisFrom), _iso(now.add(const Duration(days: 1))));
    double weekend = 0, totalExp = 0;
    for (final t in monthTxns) {
      if (t['type'] != 'expense') continue;
      final amt = ((t['amount'] as num?) ?? 0).toDouble();
      totalExp += amt;
      final d = DateTime.tryParse(t['date'] as String? ?? '');
      if (d != null && (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday)) {
        weekend += amt;
      }
    }
    if (totalExp > 0 && weekend / totalExp > 0.35) {
      ins.add(_Insight(Icons.weekend, Colors.purple, 'Weekend spending',
          '${(weekend / totalExp * 100).round()}% of this month\'s spending happens on weekends.'));
    }

    // subscription detection (last 4 months)
    final from4 = DateTime(now.year, now.month - 4, 1);
    final all4 = await DB.txnsRaw(_iso(from4), _iso(now.add(const Duration(days: 1))));
    final byKey = <String, Set<String>>{};
    final keyAmt = <String, double>{};
    final keyLabel = <String, String>{};
    for (final t in all4) {
      if (t['type'] != 'expense') continue;
      final amt = ((t['amount'] as num?) ?? 0).toDouble();
      final label = ((t['note'] as String?)?.trim().isNotEmpty == true
          ? t['note']
          : t['catName']) as String? ?? 'Expense';
      final key = '$label@${amt.round()}';
      final mon = (t['date'] as String).substring(0, 7);
      byKey.putIfAbsent(key, () => {}).add(mon);
      keyAmt[key] = amt;
      keyLabel[key] = label;
    }
    final subs = byKey.entries.where((e) => e.value.length >= 2).toList();
    if (subs.isNotEmpty) {
      final total = subs.fold<double>(0, (s, e) => s + (keyAmt[e.key] ?? 0));
      final names = subs.take(3).map((e) => keyLabel[e.key]).join(', ');
      ins.add(_Insight(Icons.subscriptions, Colors.teal, 'Possible subscriptions',
          '${subs.length} recurring charges detected (e.g. $names) ~ ${money(total)}/month. Cancel any you don\'t use.'));
    }

    // savings tip toward goals
    final goals = await DB.all('goals');
    for (final g in goals) {
      final target = ((g['target'] as num?) ?? 0).toDouble();
      final saved = ((g['saved'] as num?) ?? 0).toDouble();
      final remaining = target - saved;
      if (remaining <= 0) continue;
      final due = DateTime.tryParse(g['dueDate'] as String? ?? '');
      if (due != null && due.isAfter(now)) {
        final months = ((due.difference(now).inDays) / 30).ceil().clamp(1, 600);
        ins.add(_Insight(Icons.flag, Colors.green, 'Goal: ${g['name']}',
            'Save ${money(remaining / months)}/month to reach ${money(target)} by ${DateFormat('MMM yyyy').format(due)}.'));
      }
      break; // one goal tip is enough
    }

    if (savingsRate < 0.1 && income3 > 0) {
      ins.add(_Insight(Icons.savings, Colors.red, 'Low savings rate',
          'You are saving ${(savingsRate * 100).round()}% of income. Aim for 20%+ — trimming your top category helps most.'));
    }
    if (emergencyMonths < 3 && avgMonthlyExpense > 1) {
      ins.add(_Insight(Icons.health_and_safety, Colors.blue, 'Build an emergency fund',
          'Your liquid cash covers ${emergencyMonths.toStringAsFixed(1)} months. Target 3-6 months of expenses.'));
    }

    if (!mounted) return;
    setState(() {
      insights = ins;
      loading = false;
    });
  }

  Color _scoreColor() {
    if (score >= 75) return Colors.green;
    if (score >= 50) return Colors.orange;
    return Colors.red;
  }

  String _grade() {
    if (score >= 85) return 'Excellent';
    if (score >= 70) return 'Good';
    if (score >= 50) return 'Fair';
    return 'Needs work';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Smart Insights')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(14),
              children: [
                // score gauge
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                      gradient: headerGradient(context),
                      borderRadius: BorderRadius.circular(20)),
                  child: Column(children: [
                    const Text('Financial Health Score',
                        style: TextStyle(color: Colors.white70)),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: 140,
                      height: 140,
                      child: Stack(alignment: Alignment.center, children: [
                        SizedBox(
                          width: 140,
                          height: 140,
                          child: CircularProgressIndicator(
                            value: score / 100,
                            strokeWidth: 12,
                            backgroundColor: Colors.white24,
                            valueColor: AlwaysStoppedAnimation(_scoreColor()),
                          ),
                        ),
                        Column(mainAxisSize: MainAxisSize.min, children: [
                          Text('$score',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold)),
                          Text(_grade(), style: const TextStyle(color: Colors.white70)),
                        ]),
                      ]),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(children: [
                      for (final e in parts.entries) _bar(context, e.key, e.value),
                    ]),
                  ),
                ),
                const SizedBox(height: 8),
                if (insights.isEmpty)
                  const Card(
                      child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                              'Add a few transactions over a couple of months and your personalised insights will appear here.')))
                else
                  for (final i in insights) _card(i),
                const SizedBox(height: 30),
              ],
            ),
    );
  }

  Widget _bar(BuildContext context, String label, int v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        SizedBox(width: 120, child: Text(label, style: const TextStyle(fontSize: 13))),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
                value: v / 25, minHeight: 9, color: Theme.of(context).colorScheme.primary),
          ),
        ),
        const SizedBox(width: 8),
        Text('$v/25', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _card(_Insight i) => Card(
        child: ListTile(
          leading: CircleAvatar(backgroundColor: i.color.withOpacity(0.18), child: Icon(i.icon, color: i.color)),
          title: Text(i.title, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(i.body),
        ),
      );
}

class _Insight {
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  _Insight(this.icon, this.color, this.title, this.body);
}
