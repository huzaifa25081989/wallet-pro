import 'package:flutter/material.dart';
import '../db.dart';
import '../theme.dart';
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
    final a = await DB.accounts();
    final b = await DB.balances();
    if (!mounted) return;
    setState(() {
      accounts = a;
      bals = b;
    });
  }

  void _open(Widget w) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => w)).then((_) => _load());

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    double assets = 0, liab = 0;
    for (final a in accounts) {
      final v = bals[a['id']] ?? 0;
      if (a['type'] == 'Credit' || v < 0) {
        liab += v < 0 ? v : 0;
        if (a['type'] == 'Credit' && v >= 0) assets += v;
      } else {
        assets += v;
      }
    }
    final net = accounts.fold<double>(0, (s, a) => s + (bals[a['id']] ?? 0));

    return Scaffold(
      floatingActionButton: FloatingActionButton.large(
        heroTag: 'home_voice',
        onPressed: () => _open(const TxnEdit(autoVoice: true)),
        child: const Icon(Icons.mic, size: 32),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // ---- gradient header ----
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
                      const Text('Wallet Pro',
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(money(net),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Row(children: [
                    _pill(Icons.arrow_downward, 'Assets', money(assets)),
                    const SizedBox(width: 12),
                    _pill(Icons.arrow_upward, 'Liabilities', money(liab.abs())),
                  ]),
                ],
              ),
            ),
            // ---- quick actions ----
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Accounts', style: Theme.of(context).textTheme.titleMedium),
                  Text('${accounts.length}',
                      style: TextStyle(color: cs.outline, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            for (final a in accounts)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Color((a['color'] as int?) ?? cs.primary.value),
                      child: Icon(iconOf(a['icon']), color: Colors.white),
                    ),
                    title: Text(a['name'] as String? ?? '',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(a['type'] as String? ?? ''),
                    trailing: Text(
                      money(bals[a['id']] ?? 0),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: (bals[a['id']] ?? 0) < 0 ? Colors.red : null,
                      ),
                    ),
                    onTap: () => _open(AccountDetail(account: a)),
                  ),
                ),
              ),
            const SizedBox(height: 100),
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
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(k, style: const TextStyle(color: Colors.white70, fontSize: 11)),
              Text(v,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
            ]),
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
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                  color: c.withOpacity(0.14), shape: BoxShape.circle),
              child: Icon(ic, color: c, size: 26),
            ),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          ]),
        ),
      );
}
