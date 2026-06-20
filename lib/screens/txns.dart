import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../db.dart';
import 'add_hub.dart';
import '../widgets.dart';
import 'txn_edit.dart';

class TxnsScreen extends StatefulWidget {
  const TxnsScreen({super.key});
  @override
  State<TxnsScreen> createState() => _TxnsScreenState();
}

class _TxnsScreenState extends State<TxnsScreen> {
  String q = '';
  String typeF = 'all';
  int? acctF;
  List<Map<String, Object?>> txns = [];
  Map<int, Map<String, Object?>> cats = {}, accts = {};

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
    final t = await DB.all('txns', orderBy: 'date DESC, id DESC');
    final c = await DB.all('cats');
    final a = await DB.all('accounts');
    if (!mounted) return;
    setState(() {
      txns = t;
      cats = {for (final x in c) x['id'] as int: x};
      accts = {for (final x in a) x['id'] as int: x};
    });
  }

  bool _match(Map<String, Object?> t) {
    if (typeF != 'all' && t['type'] != typeF) return false;
    if (acctF != null && t['accountId'] != acctF && t['toAccountId'] != acctF) return false;
    if (q.isNotEmpty) {
      final cat = cats[t['categoryId']];
      final hay =
          '${t['note'] ?? ''} ${cat?['name'] ?? ''} ${t['amount'] ?? ''}'.toLowerCase();
      if (!hay.contains(q.toLowerCase())) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = txns.where(_match).toList();
    final items = <Widget>[];
    String? lastDay;
    for (final t in filtered) {
      final dateStr = t['date'] as String? ?? '';
      final day = dateStr.length >= 10 ? dateStr.substring(0, 10) : '';
      if (day != lastDay) {
        lastDay = day;
        items.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            day.isEmpty
                ? 'Unknown date'
                : DateFormat('EEE, d MMM yyyy').format(DateTime.parse(day)),
            style:
                const TextStyle(fontWeight: FontWeight.w600, color: Colors.grey, fontSize: 12),
          ),
        ));
      }
      items.add(TxnTile(
        t: t,
        cats: cats,
        accts: accts,
        onTap: () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => TxnEdit(txn: t))),
      ));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Records')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'txns_fab',
        onPressed: () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => const AddHubScreen())),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search note, category, amount',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(28)),
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (v) => setState(() => q = v),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              for (final f in const [
                ['all', 'All'],
                ['income', 'Income'],
                ['expense', 'Expense'],
                ['transfer', 'Transfer'],
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(f[1]),
                    selected: typeF == f[0],
                    onSelected: (_) => setState(() => typeF = f[0]),
                  ),
                ),
              const SizedBox(width: 4),
              DropdownButton<int?>(
                value: acctF,
                hint: const Text('All accounts'),
                underline: const SizedBox(),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('All accounts')),
                  for (final a in accts.values)
                    DropdownMenuItem<int?>(
                        value: a['id'] as int, child: Text(a['name'] as String? ?? '')),
                ],
                onChanged: (v) => setState(() => acctF = v),
              ),
            ]),
          ),
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text('No records found.\nTap + to add your first one.', textAlign: TextAlign.center))
                : ListView(children: [...items, const SizedBox(height: 80)]),
          ),
        ],
      ),
    );
  }
}
