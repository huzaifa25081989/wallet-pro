import 'package:flutter/material.dart';
import '../db.dart';
import '../widgets.dart';

class _Line {
  int? categoryId;
  final amountCtl = TextEditingController();
  final noteCtl = TextEditingController();
}

class SplitExpenseScreen extends StatefulWidget {
  const SplitExpenseScreen({super.key});
  @override
  State<SplitExpenseScreen> createState() => _SplitExpenseScreenState();
}

class _SplitExpenseScreenState extends State<SplitExpenseScreen> {
  List<Map<String, Object?>> accounts = [];
  List<Map<String, Object?>> cats = [];
  int? accountId;
  DateTime date = DateTime.now();
  final projectCtl = TextEditingController();
  final List<_Line> lines = [_Line(), _Line()];
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    accounts = await DB.accounts();
    cats = await DB.categories(type: 'expense');
    if (mounted) setState(() {});
  }

  double get _total {
    double t = 0;
    for (final l in lines) {
      t += double.tryParse(l.amountCtl.text.replaceAll(',', '').trim()) ?? 0;
    }
    return t;
  }

  Future<void> _save() async {
    if (accountId == null) {
      snack(context, 'Choose the account you paid from');
      return;
    }
    final valid = lines.where((l) =>
        l.categoryId != null &&
        (double.tryParse(l.amountCtl.text.replaceAll(',', '').trim()) ?? 0) > 0).toList();
    if (valid.isEmpty) {
      snack(context, 'Add at least one line with a category and amount');
      return;
    }
    setState(() => busy = true);
    for (final l in valid) {
      await DB.insert('txns', {
        'type': 'expense',
        'amount': double.parse(l.amountCtl.text.replaceAll(',', '').trim()),
        'accountId': accountId,
        'toAccountId': null,
        'categoryId': l.categoryId,
        'date': date.toIso8601String(),
        'note': l.noteCtl.text.trim(),
        'project': projectCtl.text.trim(),
      });
    }
    bus.ping();
    if (mounted) {
      snack(context, 'Recorded ${valid.length} expenses (${money(_total)})');
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Split expense')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Pay once from one account, record several expense categories.',
              style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 13)),
          const SizedBox(height: 14),
          DropdownButtonFormField<int>(
            value: accountId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Paid from', border: OutlineInputBorder()),
            items: [
              for (final a in accounts)
                DropdownMenuItem(value: a['id'] as int, child: Text(a['name'] as String? ?? '')),
            ],
            onChanged: (v) => setState(() => accountId = v),
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < lines.length; i++) _lineCard(i),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add another line'),
            onPressed: () => setState(() => lines.add(_Line())),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: projectCtl,
            decoration: const InputDecoration(
                labelText: 'Project / Cost centre (optional, applies to all)',
                prefixIcon: Icon(Icons.workspaces_outline),
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(14)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text(money(_total), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ]),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: busy ? null : _save,
            style: FilledButton.styleFrom(padding: const EdgeInsets.all(15)),
            child: Text(busy ? 'Saving...' : 'Record all'),
          ),
        ],
      ),
    );
  }

  Widget _lineCard(int i) {
    final l = lines[i];
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        child: Row(children: [
          Expanded(
            flex: 5,
            child: Column(children: [
              DropdownButtonFormField<int>(
                value: l.categoryId,
                isExpanded: true,
                isDense: true,
                decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
                items: [
                  for (final c in cats)
                    DropdownMenuItem(value: c['id'] as int, child: Text(c['name'] as String? ?? '')),
                ],
                onChanged: (v) => setState(() => l.categoryId = v),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: l.noteCtl,
                decoration: const InputDecoration(
                    labelText: 'Note', isDense: true, border: OutlineInputBorder()),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: TextField(
              controller: l.amountCtl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.right,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                  labelText: 'Amount', prefixText: '$kCur ', isDense: true, border: const OutlineInputBorder()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: lines.length <= 1 ? null : () => setState(() => lines.removeAt(i)),
          ),
        ]),
      ),
    );
  }
}
