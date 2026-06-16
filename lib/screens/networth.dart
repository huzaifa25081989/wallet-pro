import 'package:flutter/material.dart';
import '../db.dart';
import '../theme.dart';
import '../widgets.dart';

class NetWorthScreen extends StatefulWidget {
  const NetWorthScreen({super.key});
  @override
  State<NetWorthScreen> createState() => _NetWorthScreenState();
}

class _NetWorthScreenState extends State<NetWorthScreen> {
  bool loading = true;
  double assets = 0, liab = 0;
  final Map<String, double> byType = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final accts = await DB.accounts();
    final bals = await DB.balances();
    byType.clear();
    assets = 0;
    liab = 0;
    for (final a in accts) {
      final v = bals[a['id']] ?? 0;
      final type = a['type'] as String? ?? 'Other';
      byType[type] = (byType[type] ?? 0) + v;
      if (v >= 0) {
        assets += v;
      } else {
        liab += -v;
      }
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final net = assets - liab;
    final entries = byType.entries.toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
    final maxAbs = entries.isEmpty ? 1.0 : entries.first.value.abs().clamp(1, double.infinity);

    return Scaffold(
      appBar: AppBar(title: const Text('Net Worth')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(14),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                      gradient: headerGradient(context),
                      borderRadius: BorderRadius.circular(20)),
                  child: Column(children: [
                    const Text('Total net worth', style: TextStyle(color: Colors.white70)),
                    const SizedBox(height: 4),
                    Text(money(net),
                        style: const TextStyle(
                            color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 14),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                      Column(children: [
                        const Text('Assets', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        Text(money(assets),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ]),
                      Column(children: [
                        const Text('Liabilities', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        Text(money(liab),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ]),
                    ]),
                  ]),
                ),
                const SizedBox(height: 14),
                Text('By asset class', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                for (final e in entries)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text(money(e.value),
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: e.value < 0 ? Colors.red : null)),
                        ]),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: (e.value.abs() / maxAbs).clamp(0.0, 1.0),
                            minHeight: 8,
                            color: e.value < 0 ? Colors.red : cs.primary,
                            backgroundColor: cs.surfaceContainerHighest,
                          ),
                        ),
                      ]),
                    ),
                  ),
                const SizedBox(height: 30),
              ],
            ),
    );
  }
}
