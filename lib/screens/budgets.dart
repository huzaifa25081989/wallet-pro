import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../db.dart';
import '../widgets.dart';

class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key});
  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> {
  List<Map<String, Object?>> budgets = [];
  Map<int, Map<String, Object?>> cats = {};
  Map<int, double> spent = {};

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
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1).toIso8601String();
    final b = await DB.all('budgets');
    final c = await DB.all('cats');
    final s = await DB.spentByCat(monthStart);
    if (!mounted) return;
    setState(() {
      budgets = b;
      cats = {for (final x in c) x['id'] as int: x};
      spent = s;
    });
  }

  Future<void> _edit({Map<String, Object?>? budget}) async {
    final expenseCats = cats.values.where((c) => c['type'] == 'expense').toList();
    final usedCatIds = budgets.map((b) => b['categoryId']).toSet();
    final options = budget == null
        ? expenseCats.where((c) => !usedCatIds.contains(c['id'])).toList()
        : expenseCats;
    if (options.isEmpty) {
      snack(context, 'All expense categories already have budgets');
      return;
    }
    int? catId = budget?['categoryId'] as int? ?? options.first['id'] as int;
    final amtCtl = TextEditingController(
        text: budget == null ? '' : '${(budget['limitAmt'] as num?) ?? ''}');

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => AlertDialog(
          title: Text(budget == null ? 'Add budget' : 'Edit budget'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                value: catId,
                decoration: const InputDecoration(
                    labelText: 'Category', border: OutlineInputBorder()),
                items: [
                  for (final cat in options)
                    DropdownMenuItem(
                      value: cat['id'] as int,
                      child: Row(children: [
                        Icon(iconOf(cat['icon']),
                            size: 18,
                            color: Color((cat['color'] as int?) ?? 0xFF9E9E9E)),
                        const SizedBox(width: 8),
                        Text(cat['name'] as String? ?? ''),
                      ]),
                    ),
                ],
                onChanged: budget == null ? (v) => setS(() => catId = v) : null,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amtCtl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Monthly limit',
                    prefixText: '$kCur ',
                    border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final amt = double.tryParse(amtCtl.text.replaceAll(',', ''));
    if (amt == null || amt <= 0 || catId == null) return;
    if (budget == null) {
      await DB.insert('budgets', {'categoryId': catId, 'limitAmt': amt});
    } else {
      await DB.update('budgets',
          {'id': budget['id'], 'categoryId': catId, 'limitAmt': amt});
    }
  }

  @override
  Widget build(BuildContext context) {
    final monthLabel = DateFormat('MMMM yyyy').format(DateTime.now());
    return Scaffold(
      appBar: AppBar(title: Text('Budgets \u2014 $monthLabel')),
      floatingActionButton: FloatingActionButton(
        heroTag: 'budget_fab',
        onPressed: () => _edit(),
        child: const Icon(Icons.add),
      ),
      body: budgets.isEmpty
          ? const Center(
              child: Text('No budgets yet.\nTap + to set a monthly limit.',
                  textAlign: TextAlign.center))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final b in budgets) _budgetCard(b),
                const SizedBox(height: 80),
              ],
            ),
    );
  }

  Widget _budgetCard(Map<String, Object?> b) {
    final cat = cats[b['categoryId']];
    final limit = ((b['limitAmt'] as num?) ?? 0).toDouble();
    final sp = spent[b['categoryId']] ?? 0;
    final ratio = limit > 0 ? sp / limit : 0.0;
    final color = ratio >= 1
        ? Colors.red
        : ratio >= 0.7
            ? Colors.orange
            : Colors.green;
    final remaining = limit - sp;

    return Card(
      child: InkWell(
        onTap: () => _edit(budget: b),
        onLongPress: () async {
          if (await confirm(context, 'Delete budget?',
              'Remove the budget for ${cat?['name'] ?? 'this category'}?')) {
            await DB.delete('budgets', b['id'] as int);
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(iconOf(cat?['icon']),
                    size: 20, color: Color((cat?['color'] as int?) ?? 0xFF9E9E9E)),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(cat?['name'] as String? ?? 'Category',
                        style: const TextStyle(fontWeight: FontWeight.w600))),
                Text('${money(sp)} / ${money(limit)}',
                    style: const TextStyle(fontSize: 12)),
              ]),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ratio.clamp(0.0, 1.0),
                  minHeight: 8,
                  color: color,
                  backgroundColor: Colors.grey.shade300,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                remaining >= 0
                    ? '${money(remaining)} left this month'
                    : 'Over budget by ${money(remaining.abs())}',
                style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
