import 'package:flutter/material.dart';
import '../db.dart';
import '../widgets.dart';

class SetBalancesScreen extends StatefulWidget {
  const SetBalancesScreen({super.key});
  @override
  State<SetBalancesScreen> createState() => _SetBalancesScreenState();
}

class _SetBalancesScreenState extends State<SetBalancesScreen> {
  List<Map<String, Object?>> accounts = [];
  Map<int, double> bals = {};
  final Map<int, TextEditingController> ctls = {};
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    accounts = await DB.accounts();
    bals = await DB.balances();
    for (final a in accounts) {
      final id = a['id'] as int;
      ctls[id] = TextEditingController(text: (bals[id] ?? 0).toStringAsFixed(2));
    }
    if (mounted) setState(() {});
  }

  Future<void> _saveAll() async {
    setState(() => busy = true);
    int changed = 0;
    for (final a in accounts) {
      final id = a['id'] as int;
      final target = double.tryParse(ctls[id]!.text.replaceAll(',', '').trim());
      if (target == null) continue;
      final cur = bals[id] ?? 0;
      if ((target - cur).abs() < 0.005) continue;
      final curOpening = ((a['opening'] as num?) ?? 0).toDouble();
      final newOpening = curOpening + (target - cur);
      await DB.update('accounts', {'id': id, 'opening': newOpening});
      changed++;
    }
    if (mounted) {
      setState(() => busy = false);
      snack(context, 'Updated $changed account balances');
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Set account balances')),
      body: Column(children: [
        Container(
          width: double.infinity,
          color: cs.secondaryContainer,
          padding: const EdgeInsets.all(14),
          child: Text(
              'Enter the correct current balance for each account (e.g. the figure from your old app). Wallet Pro adjusts each opening balance so the totals match — your transactions are untouched.',
              style: TextStyle(fontSize: 12.5, color: cs.onSecondaryContainer)),
        ),
        Expanded(
          child: ListView(
            children: [
              for (final a in accounts)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  child: Row(children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: Color((a['color'] as int?) ?? cs.primary.value),
                      child: Icon(iconOf(a['icon']), color: Colors.white, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(a['name'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 130,
                      child: TextField(
                        controller: ctls[a['id'] as int],
                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                        textAlign: TextAlign.right,
                        decoration: InputDecoration(
                          isDense: true,
                          prefixText: '$kCur ',
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                        ),
                      ),
                    ),
                  ]),
                ),
              const SizedBox(height: 90),
            ],
          ),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: FilledButton.icon(
            icon: const Icon(Icons.check),
            label: Text(busy ? 'Saving...' : 'Save all balances'),
            onPressed: busy ? null : _saveAll,
            style: FilledButton.styleFrom(padding: const EdgeInsets.all(14)),
          ),
        ),
      ),
    );
  }
}
