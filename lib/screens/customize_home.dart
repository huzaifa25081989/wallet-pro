import 'package:flutter/material.dart';
import '../db.dart';
import '../widgets.dart';
import 'home.dart';

class CustomizeHomeScreen extends StatefulWidget {
  const CustomizeHomeScreen({super.key});
  @override
  State<CustomizeHomeScreen> createState() => _CustomizeHomeScreenState();
}

class _CustomizeHomeScreenState extends State<CustomizeHomeScreen> {
  List<String> order = [];
  Set<String> enabled = {};
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cfg = await DB.settingGet('homeCards');
    final saved = (cfg == null || cfg.isEmpty)
        ? List<String>.from(defaultCards)
        : cfg.split(',').where((e) => cardNames.containsKey(e)).toList();
    enabled = saved.toSet();
    // enabled first (in saved order), then the rest
    order = [...saved, ...cardNames.keys.where((k) => !saved.contains(k))];
    loaded = true;
    if (mounted) setState(() {});
  }

  Future<void> _persist() async {
    final list = order.where((k) => enabled.contains(k)).toList();
    await DB.settingSet('homeCards', list.join(','));
    bus.ping();
  }

  static const _desc = {
    'month': 'Income, expense, net & top spending this month',
    'recent': 'Your 5 most recent transactions',
    'budgets': 'Progress bars for your budgets',
    'goals': 'Progress towards your savings goals',
    'networth': 'Assets, liabilities and net worth',
    'shortcuts': 'Quick buttons to Analytics, Insights, etc.',
  };

  static const _icons = {
    'month': Icons.calendar_month,
    'recent': Icons.receipt_long,
    'budgets': Icons.donut_large,
    'goals': Icons.flag,
    'networth': Icons.account_balance,
    'shortcuts': Icons.apps,
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Customize dashboard')),
      body: !loaded
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Container(
                width: double.infinity,
                color: cs.secondaryContainer,
                padding: const EdgeInsets.all(14),
                child: Text(
                    'Turn cards on or off, and drag the handle to reorder how they appear on your home screen.',
                    style: TextStyle(fontSize: 12.5, color: cs.onSecondaryContainer)),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: order.length,
                  onReorder: (oldI, newI) {
                    setState(() {
                      if (newI > oldI) newI -= 1;
                      final k = order.removeAt(oldI);
                      order.insert(newI, k);
                    });
                    _persist();
                  },
                  itemBuilder: (context, i) {
                    final k = order[i];
                    final on = enabled.contains(k);
                    return Card(
                      key: ValueKey(k),
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: ListTile(
                        leading: Icon(_icons[k] ?? Icons.widgets,
                            color: on ? cs.primary : cs.outline),
                        title: Text(cardNames[k] ?? k,
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: on ? null : cs.outline)),
                        subtitle: Text(_desc[k] ?? '', style: const TextStyle(fontSize: 12)),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          Switch(
                            value: on,
                            onChanged: (v) {
                              setState(() {
                                if (v) {
                                  enabled.add(k);
                                } else {
                                  enabled.remove(k);
                                }
                              });
                              _persist();
                            },
                          ),
                          ReorderableDragStartListener(
                            index: i,
                            child: const Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: Icon(Icons.drag_handle),
                            ),
                          ),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            ]),
    );
  }
}
