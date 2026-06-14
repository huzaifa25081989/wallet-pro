import 'package:flutter/material.dart';
import '../db.dart';
import '../widgets.dart';

class CoaScreen extends StatefulWidget {
  const CoaScreen({super.key});
  @override
  State<CoaScreen> createState() => _CoaScreenState();
}

class _CoaScreenState extends State<CoaScreen> {
  List<Map<String, Object?>> accounts = [], loans = [], incRows = [], expRows = [];
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

  Future<void> _load() async {
    const from = '1970-01-01';
    const to = '2100-01-01';
    final a = await DB.all('accounts', orderBy: 'name');
    final b = await DB.balances();
    final l = await DB.all('loans', orderBy: 'name');
    final inc = await DB.catTotals('income', from, to);
    final exp = await DB.catTotals('expense', from, to);
    if (!mounted) return;
    setState(() {
      accounts = a;
      bals = b;
      loans = l;
      incRows = inc;
      expRows = exp;
    });
  }

  double _outstanding(Map<String, Object?> l) =>
      (((l['principal'] as num?) ?? 0).toDouble() -
              ((l['paid'] as num?) ?? 0).toDouble())
          .clamp(0.0, double.infinity)
          .toDouble();

  @override
  Widget build(BuildContext context) {
    final assetAccts = accounts.where((a) => a['type'] != 'Credit').toList();
    final creditAccts = accounts.where((a) => a['type'] == 'Credit').toList();
    final lent = loans.where((l) => l['type'] == 'lent').toList();
    final borrowed = loans.where((l) => l['type'] == 'borrowed').toList();

    final assetTotal =
        assetAccts.fold<double>(0, (s, a) => s + (bals[a['id']] ?? 0)) +
            lent.fold<double>(0, (s, l) => s + _outstanding(l));
    final liabTotal =
        creditAccts.fold<double>(0, (s, a) => s + (bals[a['id']] ?? 0).abs()) +
            borrowed.fold<double>(0, (s, l) => s + _outstanding(l));
    final equity = assetTotal - liabTotal;

    Widget row(String name, double v, {IconData? ic, Color? c}) => ListTile(
          dense: true,
          leading: Icon(ic ?? Icons.circle, size: 18, color: c ?? Colors.grey),
          title: Text(name),
          trailing: Text(money(v), style: const TextStyle(fontWeight: FontWeight.w600)),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Chart of Accounts')),
      body: ListView(
        children: [
          ExpansionTile(
            initiallyExpanded: true,
            leading: const Icon(Icons.account_balance, color: Colors.green),
            title: const Text('Assets', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(money(assetTotal)),
            children: [
              for (final a in assetAccts)
                row(a['name'] as String? ?? '', bals[a['id']] ?? 0,
                    ic: iconOf(a['icon']),
                    c: Color((a['color'] as int?) ?? 0xFF607D8B)),
              for (final l in lent)
                row('${l['name']} (receivable)', _outstanding(l),
                    ic: Icons.handshake, c: Colors.green),
            ],
          ),
          ExpansionTile(
            initiallyExpanded: true,
            leading: const Icon(Icons.credit_card, color: Colors.red),
            title: const Text('Liabilities',
                style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(money(liabTotal)),
            children: [
              for (final a in creditAccts)
                row(a['name'] as String? ?? '', (bals[a['id']] ?? 0).abs(),
                    ic: iconOf(a['icon']),
                    c: Color((a['color'] as int?) ?? 0xFF607D8B)),
              for (final l in borrowed)
                row('${l['name']} (payable)', _outstanding(l),
                    ic: Icons.handshake, c: Colors.red),
              if (creditAccts.isEmpty && borrowed.isEmpty)
                const ListTile(dense: true, title: Text('None')),
            ],
          ),
          ExpansionTile(
            leading: const Icon(Icons.pie_chart, color: Colors.teal),
            title: const Text('Equity', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(money(equity)),
            children: [
              row('Net worth (Assets \u2212 Liabilities)', equity,
                  ic: Icons.balance, c: Colors.teal),
            ],
          ),
          ExpansionTile(
            leading: const Icon(Icons.trending_up, color: Colors.green),
            title: const Text('Income', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('All-time by category'),
            children: [
              for (final r in incRows)
                row(r['n'] as String? ?? 'Uncategorized',
                    ((r['s'] as num?) ?? 0).toDouble(),
                    ic: iconOf(r['ic']),
                    c: Color((r['col'] as int?) ?? 0xFF9E9E9E)),
              if (incRows.isEmpty) const ListTile(dense: true, title: Text('None')),
            ],
          ),
          ExpansionTile(
            leading: const Icon(Icons.trending_down, color: Colors.red),
            title:
                const Text('Expenses', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('All-time by category'),
            children: [
              for (final r in expRows)
                row(r['n'] as String? ?? 'Uncategorized',
                    ((r['s'] as num?) ?? 0).toDouble(),
                    ic: iconOf(r['ic']),
                    c: Color((r['col'] as int?) ?? 0xFF9E9E9E)),
              if (expRows.isEmpty) const ListTile(dense: true, title: Text('None')),
            ],
          ),
        ],
      ),
    );
  }
}
