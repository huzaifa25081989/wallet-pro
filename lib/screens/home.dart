import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../db.dart';
import '../theme.dart';
import '../widgets.dart';
import 'accounts.dart';
import 'analytics.dart';
import 'customize_home.dart';
import 'goals.dart';
import 'insights.dart';
import 'networth.dart';
import 'simulator.dart';
import 'txn_edit.dart';
import 'family.dart';
import 'txns.dart';

const defaultCards = ['month', 'recent', 'budgets', 'goals'];
const cardNames = {
  'month': 'This month summary',
  'recent': 'Recent activity',
  'budgets': 'Budget usage',
  'goals': 'Savings goals',
  'networth': 'Net worth by class',
  'shortcuts': 'Quick shortcuts',
};

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, Object?>> accounts = [];
  Map<int, double> bals = {};
  double monthIncome = 0, monthExpense = 0;
  List<Map<String, Object?>> topCats = [];
  List<Map<String, Object?>> recent = [];
  List<Map<String, Object?>> budgets = [];
  Map<int, double> spent = {};
  Map<int, Map<String, Object?>> catsById = {};
  List<Map<String, Object?>> goals = [];
  List<String> cards = defaultCards;
  double assets = 0, liab = 0;

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

  Future<void> _load() async {
    final a = await DB.accounts();
    final b = await DB.balances();
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, 1).toIso8601String();
    final to = DateTime(now.year, now.month + 1, 1).toIso8601String();
    final inc = await DB.totalFor('income', from, to);
    final exp = await DB.totalFor('expense', from, to);
    final cats = await DB.catTotals('expense', from, to);
    final rec = await DB.recentTxns(5);
    final buds = await DB.all('budgets');
    final sp = await DB.spentByCat(from);
    final allCats = await DB.all('cats');
    final gls = await DB.all('goals', orderBy: 'id DESC');
    final cfg = await DB.settingGet('homeCards');

    double as = 0, li = 0;
    for (final acc in a) {
      final v = b[acc['id']] ?? 0;
      if (v >= 0) {
        as += v;
      } else {
        li += -v;
      }
    }
    if (!mounted) return;
    setState(() {
      accounts = a;
      bals = b;
      monthIncome = inc;
      monthExpense = exp;
      topCats = cats.take(3).toList();
      recent = rec;
      budgets = buds;
      spent = sp;
      catsById = {for (final c in allCats) c['id'] as int: c};
      goals = gls;
      assets = as;
      liab = li;
      cards = (cfg == null || cfg.isEmpty)
          ? defaultCards
          : cfg.split(',').where((e) => cardNames.containsKey(e)).toList();
    });
  }

  void _open(Widget w) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => w)).then((_) => _load());

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final net = accounts.fold<double>(0, (s, a) => s + (bals[a['id']] ?? 0));

    return Scaffold(
      floatingActionButton: FloatingActionButton.large(
        heroTag: 'home_add',
        onPressed: () => _open(const TxnEdit()),
        child: const Icon(Icons.add, size: 34),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 60, 20, 24),
              decoration: BoxDecoration(
                gradient: headerGradient(context),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total balance',
                          style: TextStyle(color: Colors.white70, fontSize: 14)),
                      Row(children: [
                        _circleBtn(Icons.mic, () =>
                            _open(const TxnEdit(autoVoice: true))),
                        const SizedBox(width: 8),
                        _circleBtn(Icons.search, () => showSearch(
                            context: context, delegate: WalletSearch(accounts, bals))),
                        const SizedBox(width: 8),
                        _circleBtn(Icons.dashboard_customize, () =>
                            _open(const CustomizeHomeScreen())),
                      ]),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(money(net),
                      style: const TextStyle(
                          color: Colors.white, fontSize: 34, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Row(children: [
                    _pill(Icons.arrow_downward, 'Assets', money(assets)),
                    const SizedBox(width: 12),
                    _pill(Icons.arrow_upward, 'Liabilities', money(liab)),
                  ]),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _action(Icons.remove, 'Expense', Colors.red,
                      () => _open(const TxnEdit(initialType: 'expense'))),
                  _action(Icons.add, 'Income', Colors.green,
                      () => _open(const TxnEdit(initialType: 'income'))),
                  _action(Icons.swap_horiz, 'Transfer', cs.primary,
                      () => _open(const TxnEdit(initialType: 'transfer'))),
                  _action(Icons.account_balance_wallet, 'Account', Colors.orange,
                      () => _open(const AccountEdit())),
                ],
              ),
            ),
            for (final key in cards) _buildCard(context, key),
            ..._groupSections(context),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _circleBtn(IconData ic, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(20)),
          child: Icon(ic, color: Colors.white, size: 20),
        ),
      );

  Widget _buildCard(BuildContext context, String key) {
    switch (key) {
      case 'recent':
        return _recentCard(context);
      case 'budgets':
        return _budgetsCard(context);
      case 'goals':
        return _goalsCard(context);
      case 'networth':
        return _networthCard(context);
      case 'shortcuts':
        return _shortcutsCard(context);
      default:
        return _monthCard(context);
    }
  }

  Widget _sectionHeader(String title, {String? action, VoidCallback? onAction}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        if (action != null)
          GestureDetector(
            onTap: onAction,
            child: Row(children: [
              Text(action, style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600, fontSize: 13)),
              Icon(Icons.chevron_right, size: 18, color: cs.primary),
            ]),
          ),
      ]),
    );
  }

  Widget _monthCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final net = monthIncome - monthExpense;
    final topMax = topCats.isEmpty ? 1.0 : ((topCats.first['s'] as num?) ?? 1).toDouble();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionHeader('This month', action: 'Analytics', onAction: () => _open(const AnalyticsScreen())),
        Row(children: [
          _miniStat('Income', monthIncome, const [Color(0xFF11998E), Color(0xFF38EF7D)]),
          const SizedBox(width: 8),
          _miniStat('Expense', monthExpense, const [Color(0xFFEB3349), Color(0xFFF45C43)]),
          const SizedBox(width: 8),
          _miniStat('Net', net, const [Color(0xFF1A2980), Color(0xFF26D0CE)]),
        ]),
        if (topCats.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text('Top spending', style: TextStyle(color: cs.outline, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          for (final c in topCats)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                CircleAvatar(radius: 13, backgroundColor: Color((c['col'] as int?) ?? 0xFF9E9E9E),
                    child: Icon(iconOf(c['ic']), color: Colors.white, size: 14)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(c['n'] as String? ?? '', style: const TextStyle(fontSize: 13)),
                      Text(money((c['s'] as num?) ?? 0), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ]),
                    const SizedBox(height: 3),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (((c['s'] as num?) ?? 0).toDouble() / topMax).clamp(0.0, 1.0),
                        minHeight: 6,
                        color: Color((c['col'] as int?) ?? 0xFF9E9E9E),
                        backgroundColor: cs.surfaceContainerHighest,
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
        ],
      ]),
    );
  }

  Widget _recentCard(BuildContext context) {
    if (recent.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionHeader('Recent activity', action: 'All', onAction: () => _open(const TxnsScreen())),
        Card(
          child: Column(children: [
            for (final t in recent)
              ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: Color((t['catColor'] as int?) ?? 0xFF607D8B),
                  child: Icon(
                      t['type'] == 'transfer' ? Icons.swap_horiz : iconOf(t['catIcon']),
                      color: Colors.white, size: 16),
                ),
                title: Text(
                    (t['note'] as String?)?.isNotEmpty == true
                        ? t['note'] as String
                        : (t['catName'] as String? ?? (t['type'] as String? ?? '')),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(_recentSub(t), maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Text(_recentAmt(t),
                    style: TextStyle(fontWeight: FontWeight.bold, color: _recentColor(t))),
                onTap: () => _open(TxnEdit(txn: t)),
              ),
          ]),
        ),
      ]),
    );
  }

  String _recentSub(Map<String, Object?> t) {
    final d = DateTime.tryParse(t['date'] as String? ?? '');
    final ds = d == null ? '' : DateFormat('d MMM').format(d);
    if (t['type'] == 'transfer') return '$ds · ${t['fromName'] ?? ''} → ${t['toName'] ?? ''}';
    return '$ds · ${t['fromName'] ?? ''}';
  }

  String _recentAmt(Map<String, Object?> t) {
    final a = ((t['amount'] as num?) ?? 0).toDouble();
    final sign = t['type'] == 'income' ? '+' : t['type'] == 'expense' ? '-' : '';
    return '$sign${money(a)}';
  }

  Color? _recentColor(Map<String, Object?> t) =>
      t['type'] == 'income' ? Colors.green : t['type'] == 'expense' ? Colors.red : null;

  Widget _budgetsCard(BuildContext context) {
    if (budgets.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final list = budgets.take(3).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionHeader('Budget usage'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              for (final b in list) _budgetRow(context, b),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _budgetRow(BuildContext context, Map<String, Object?> b) {
    final cs = Theme.of(context).colorScheme;
    final catId = b['categoryId'] as int?;
    final cat = catId == null ? null : catsById[catId];
    final limit = ((b['limitAmt'] as num?) ?? 0).toDouble();
    final used = catId == null ? 0.0 : (spent[catId] ?? 0);
    final ratio = limit <= 0 ? 0.0 : (used / limit).clamp(0.0, 1.0);
    final color = ratio >= 1.0 ? Colors.red : ratio >= 0.7 ? Colors.orange : Colors.green;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(cat?['name'] as String? ?? 'Budget', style: const TextStyle(fontSize: 13)),
          Text('${money(used)} / ${money(limit)}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
              value: ratio, minHeight: 7, color: color, backgroundColor: cs.surfaceContainerHighest),
        ),
      ]),
    );
  }

  Widget _goalsCard(BuildContext context) {
    if (goals.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionHeader('Savings goals', action: 'All', onAction: () => _open(const GoalsScreen())),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              for (final g in goals.take(3)) _goalRow(context, g),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _goalRow(BuildContext context, Map<String, Object?> g) {
    final cs = Theme.of(context).colorScheme;
    final target = ((g['target'] as num?) ?? 0).toDouble();
    final saved = ((g['saved'] as num?) ?? 0).toDouble();
    final ratio = target <= 0 ? 0.0 : (saved / target).clamp(0.0, 1.0);
    final color = Color((g['color'] as int?) ?? cs.primary.value);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        CircleAvatar(radius: 14, backgroundColor: color, child: Icon(iconOf(g['icon']), color: Colors.white, size: 15)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(g['name'] as String? ?? '', style: const TextStyle(fontSize: 13)),
              Text('${(ratio * 100).round()}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                  value: ratio, minHeight: 7, color: color, backgroundColor: cs.surfaceContainerHighest),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _networthCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionHeader('Net worth', action: 'Details', onAction: () => _open(const NetWorthScreen())),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _nwStat('Assets', assets, Colors.green),
              _nwStat('Liabilities', liab, Colors.red),
              _nwStat('Net', assets - liab, Theme.of(context).colorScheme.primary),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _nwStat(String k, double v, Color c) => Column(children: [
        Text(k, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 4),
        Text(money(v), style: TextStyle(fontWeight: FontWeight.bold, color: c)),
      ]);

  Widget _shortcutsCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 0),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        _chip(Icons.insights, 'Analytics', () => _open(const AnalyticsScreen())),
        _chip(Icons.auto_awesome, 'Insights', () => _open(const InsightsScreen())),
        _chip(Icons.calculate, 'Simulator', () => _open(const SimulatorScreen())),
        _chip(Icons.account_balance, 'Net Worth', () => _open(const NetWorthScreen())),
        _chip(Icons.family_restroom, 'Family', () => _open(const FamilyScreen())),
      ]),
    );
  }

  Widget _chip(IconData ic, String label, VoidCallback onTap) => ActionChip(
        avatar: Icon(ic, size: 18),
        label: Text(label),
        onPressed: onTap,
      );

  List<Widget> _groupSections(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final widgets = <Widget>[];
    for (final g in accountGroups) {
      final list = accounts.where((a) => groupOf(a) == g).toList();
      if (list.isEmpty) continue;
      final total = list.fold<double>(0, (s, a) => s + (bals[a['id']] ?? 0));
      widgets.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(groupLabels[g]!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            Text(money(total), style: TextStyle(color: cs.outline, fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
      ));
      widgets.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Wrap(spacing: 8, runSpacing: 8, children: [for (final a in list) _accountTile(context, a)]),
      ));
    }
    return widgets;
  }

  Widget _accountTile(BuildContext context, Map<String, Object?> a) {
    final w = (MediaQuery.of(context).size.width - 20 - 16) / 2;
    final bal = bals[a['id']] ?? 0;
    final color = Color((a['color'] as int?) ?? Colors.teal.value);
    final neg = bal < 0;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _open(AccountDetail(account: a)),
      child: Container(
        width: w,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color, Color.lerp(color, Colors.black, 0.18)!],
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(iconOf(a['icon']), color: Colors.white70, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(a['name'] as String? ?? '',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
              ),
            ]),
            const SizedBox(height: 8),
            Text('${neg ? '-' : ''}$kCur ${fmt(bal.abs())}',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: neg ? const Color(0xFFFFD2D2) : Colors.white,
                    fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
      ),
    );
  }

  Widget _pill(IconData ic, String k, String v) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.18),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            Icon(ic, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(k, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(v, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              ]),
            ),
          ]),
        ),
      );

  Widget _action(IconData ic, String label, Color c, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Column(children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(color: c.withOpacity(0.14), shape: BoxShape.circle),
              child: Icon(ic, color: c, size: 26),
            ),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          ]),
        ),
      );

  Widget _miniStat(String label, double v, List<Color> grad) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: grad, begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(money(v), style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            ),
          ]),
        ),
      );
}

/// Search across accounts and categories from the home screen.
class WalletSearch extends SearchDelegate {
  final List<Map<String, Object?>> accounts;
  final Map<int, double> bals;
  WalletSearch(this.accounts, this.bals);

  @override
  List<Widget> buildActions(BuildContext context) =>
      [if (query.isNotEmpty) IconButton(icon: const Icon(Icons.clear), onPressed: () => query = '')];

  @override
  Widget buildLeading(BuildContext context) =>
      IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(context, null));

  @override
  Widget buildResults(BuildContext context) => _results(context);

  @override
  Widget buildSuggestions(BuildContext context) => _results(context);

  Widget _results(BuildContext context) {
    final q = query.trim().toLowerCase();
    final accs = accounts
        .where((a) => (a['name'] as String? ?? '').toLowerCase().contains(q))
        .toList();
    return FutureBuilder<List<Map<String, Object?>>>(
      future: DB.categories(),
      builder: (context, snap) {
        final cats = (snap.data ?? [])
            .where((c) => (c['name'] as String? ?? '').toLowerCase().contains(q))
            .toList();
        return ListView(children: [
          if (accs.isNotEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('Accounts', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          for (final a in accs)
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Color((a['color'] as int?) ?? Colors.teal.value),
                child: Icon(iconOf(a['icon']), color: Colors.white, size: 20),
              ),
              title: Text(a['name'] as String? ?? ''),
              subtitle: Text(a['type'] as String? ?? ''),
              trailing: Text(money(bals[a['id']] ?? 0), style: const TextStyle(fontWeight: FontWeight.bold)),
              onTap: () {
                close(context, null);
                Navigator.push(context, MaterialPageRoute(builder: (_) => AccountDetail(account: a)));
              },
            ),
          if (cats.isNotEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('Categories (tap to add a record)', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          for (final c in cats)
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Color((c['color'] as int?) ?? Colors.grey.value),
                child: Icon(iconOf(c['icon']), color: Colors.white, size: 20),
              ),
              title: Text(c['name'] as String? ?? ''),
              subtitle: Text(c['type'] as String? ?? ''),
              onTap: () {
                close(context, null);
                Navigator.push(context, MaterialPageRoute(
                    builder: (_) => TxnEdit(initialType: c['type'] as String?, initialCategoryId: c['id'] as int?)));
              },
            ),
          if (accs.isEmpty && cats.isEmpty)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No matches'))),
        ]);
      },
    );
  }
}
