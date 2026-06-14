import 'package:flutter/material.dart';
import '../db.dart';
import '../widgets.dart';
import 'accounts.dart';
import 'txn_edit.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
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

  Future<void> _load() async {
    final a = await DB.all('accounts', orderBy: 'name');
    final b = await DB.balances();
    if (!mounted) return;
    setState(() {
      accounts = a;
      bals = b;
    });
  }

  @override
  Widget build(BuildContext context) {
    double assets = 0, liab = 0;
    for (final a in accounts) {
      final v = bals[a['id']] ?? 0;
      if (a['type'] == 'Credit') {
        liab += v;
      } else {
        assets += v;
      }
    }
    final net = assets + liab;

    return Scaffold(
      appBar: AppBar(title: const Text('Wallet Pro')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'home_fab',
        onPressed: () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => const TxnEdit())),
        icon: const Icon(Icons.add),
        label: const Text('Add record'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Net worth', style: Theme.of(context).textTheme.labelLarge),
                  Text(money(net),
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: _kv('Assets', money(assets), Colors.green)),
                    Expanded(child: _kv('Liabilities', money(liab.abs()), Colors.red)),
                  ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Accounts & wallets', style: Theme.of(context).textTheme.titleMedium),
              TextButton.icon(
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const AccountEdit())),
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
            ],
          ),
          for (final a in accounts)
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Color((a['color'] as int?) ?? Colors.teal.value),
                  child: Icon(iconOf(a['icon']), color: Colors.white),
                ),
                title: Text(a['name'] as String? ?? ''),
                subtitle: Text(a['type'] as String? ?? ''),
                trailing: Text(
                  money(bals[a['id']] ?? 0),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: (bals[a['id']] ?? 0) < 0 ? Colors.red : null,
                  ),
                ),
                onTap: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => AccountDetail(account: a))),
              ),
            ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _kv(String k, String v, Color c) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Text(v, style: TextStyle(fontWeight: FontWeight.w600, color: c)),
        ],
      );
}
