import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../db.dart';
import '../widgets.dart';

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});
  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  List<Map<String, Object?>> goals = [];

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
    final g = await DB.all('goals', orderBy: 'id DESC');
    if (!mounted) return;
    setState(() => goals = g);
  }

  Future<void> _addMoney(Map<String, Object?> g) async {
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Add to ${g['name']}'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'Amount', prefixText: '$kCur '),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok == true) {
      final add = double.tryParse(ctl.text.replaceAll(',', '')) ?? 0;
      final saved = ((g['saved'] as num?) ?? 0).toDouble() + add;
      await DB.update('goals', {'id': g['id'], 'saved': saved});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Savings Goals')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const GoalEdit())).then((_) => _load()),
        icon: const Icon(Icons.add),
        label: const Text('New goal'),
      ),
      body: goals.isEmpty
          ? const Center(
              child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('No goals yet. Tap "New goal" to start saving for something.',
                      textAlign: TextAlign.center)))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final g in goals) _goalCard(context, g),
                const SizedBox(height: 90),
              ],
            ),
    );
  }

  Widget _goalCard(BuildContext context, Map<String, Object?> g) {
    final target = ((g['target'] as num?) ?? 0).toDouble();
    final saved = ((g['saved'] as num?) ?? 0).toDouble();
    final pct = target <= 0 ? 0.0 : (saved / target).clamp(0.0, 1.0);
    final color = Color((g['color'] as int?) ?? Colors.teal.value);
    final due = DateTime.tryParse(g['dueDate'] as String? ?? '');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(backgroundColor: color, child: Icon(iconOf(g['icon']), color: Colors.white)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(g['name'] as String? ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                if (due != null)
                  Text('by ${DateFormat('d MMM yyyy').format(due)}',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
              ]),
            ),
            IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => GoalEdit(goal: g)))
                    .then((_) => _load())),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
                value: pct, minHeight: 10, color: color, backgroundColor: color.withOpacity(0.15)),
          ),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('${money(saved)} of ${money(target)}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('${(pct * 100).toStringAsFixed(0)}%'),
          ]),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add money'),
                onPressed: () => _addMoney(g)),
          ),
        ]),
      ),
    );
  }
}

class GoalEdit extends StatefulWidget {
  final Map<String, Object?>? goal;
  const GoalEdit({super.key, this.goal});
  @override
  State<GoalEdit> createState() => _GoalEditState();
}

class _GoalEditState extends State<GoalEdit> {
  final nameCtl = TextEditingController();
  final targetCtl = TextEditingController();
  final savedCtl = TextEditingController(text: '0');
  int icon = Icons.savings.codePoint;
  int color = Colors.teal.value;
  DateTime? due;

  @override
  void initState() {
    super.initState();
    final g = widget.goal;
    if (g != null) {
      nameCtl.text = g['name'] as String? ?? '';
      targetCtl.text = '${(g['target'] as num?) ?? ''}';
      savedCtl.text = '${(g['saved'] as num?) ?? 0}';
      icon = (g['icon'] as int?) ?? icon;
      color = (g['color'] as int?) ?? color;
      due = DateTime.tryParse(g['dueDate'] as String? ?? '');
    }
  }

  Future<void> _save() async {
    if (nameCtl.text.trim().isEmpty) {
      snack(context, 'Enter a goal name');
      return;
    }
    final m = <String, Object?>{
      'name': nameCtl.text.trim(),
      'target': double.tryParse(targetCtl.text.replaceAll(',', '')) ?? 0,
      'saved': double.tryParse(savedCtl.text.replaceAll(',', '')) ?? 0,
      'icon': icon,
      'color': color,
      'dueDate': due?.toIso8601String(),
    };
    if (widget.goal == null) {
      await DB.insert('goals', m);
    } else {
      m['id'] = widget.goal!['id'];
      await DB.update('goals', m);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.goal == null ? 'New goal' : 'Edit goal'),
        actions: [
          if (widget.goal != null)
            IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  await DB.delete('goals', widget.goal!['id'] as int);
                  if (mounted) Navigator.pop(context);
                }),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: nameCtl,
            decoration: const InputDecoration(
                labelText: 'Goal (e.g. Umrah, Car, Emergency fund)',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: targetCtl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
                labelText: 'Target amount', prefixText: '$kCur ', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: savedCtl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
                labelText: 'Already saved', prefixText: '$kCur ', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: Card(
                child: ListTile(
                  leading: Icon(iconOf(icon)),
                  title: const Text('Icon'),
                  onTap: () async {
                    final i = await pickIcon(context);
                    if (i != null) setState(() => icon = i.codePoint);
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Card(
                child: ListTile(
                  leading: CircleAvatar(backgroundColor: Color(color), radius: 12),
                  title: const Text('Color'),
                  onTap: () async {
                    final c = await pickColor(context, Color(color));
                    if (c != null) setState(() => color = c.value);
                  },
                ),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.event),
              title: const Text('Target date (optional)'),
              subtitle: Text(due == null ? 'None' : DateFormat('d MMM yyyy').format(due!)),
              trailing: due == null
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear), onPressed: () => setState(() => due = null)),
              onTap: () async {
                final p = await showDatePicker(
                    context: context,
                    initialDate: due ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100));
                if (p != null) setState(() => due = p);
              },
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
            child: const Text('Save goal'),
          ),
        ],
      ),
    );
  }
}
