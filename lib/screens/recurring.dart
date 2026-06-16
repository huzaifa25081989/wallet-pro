import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../db.dart';
import '../widgets.dart';

class RecurringScreen extends StatefulWidget {
  const RecurringScreen({super.key});
  @override
  State<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends State<RecurringScreen> {
  List<Map<String, Object?>> rules = [];

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
    final r = await DB.all('recurring', orderBy: 'nextDate');
    if (!mounted) return;
    setState(() => rules = r);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Recurring & Planned')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const RecurringEdit())).then((_) => _load()),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: rules.isEmpty
          ? const Center(
              child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                  'No recurring or planned payments yet.\n\nAuto-post items create a record on their date automatically. Reminders just show the upcoming date.',
                  textAlign: TextAlign.center),
            ))
          : ListView(
              children: [
                for (final r in rules)
                  Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: r['type'] == 'income'
                            ? Colors.green
                            : r['type'] == 'transfer'
                                ? cs.primary
                                : Colors.red,
                        child: Icon(
                            r['type'] == 'income'
                                ? Icons.south_west
                                : r['type'] == 'transfer'
                                    ? Icons.swap_horiz
                                    : Icons.north_east,
                            color: Colors.white),
                      ),
                      title: Text(r['title'] as String? ?? '(untitled)'),
                      subtitle: Text(
                          '${_freqLabel(r['freq'] as String?)} \u00b7 next ${_d(r['nextDate'])}'
                          '${(r['autoPost'] as int? ?? 1) == 1 ? '' : ' \u00b7 reminder'}'),
                      trailing: Text(money((r['amount'] as num?) ?? 0),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      onTap: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => RecurringEdit(rule: r)))
                          .then((_) => _load()),
                    ),
                  ),
                const SizedBox(height: 90),
              ],
            ),
    );
  }

  String _freqLabel(String? f) =>
      {'weekly': 'Weekly', 'yearly': 'Yearly'}[f] ?? 'Monthly';
  String _d(Object? iso) {
    final t = DateTime.tryParse(iso as String? ?? '');
    return t == null ? '-' : DateFormat('d MMM yyyy').format(t);
  }
}

class RecurringEdit extends StatefulWidget {
  final Map<String, Object?>? rule;
  const RecurringEdit({super.key, this.rule});
  @override
  State<RecurringEdit> createState() => _RecurringEditState();
}

class _RecurringEditState extends State<RecurringEdit> {
  final titleCtl = TextEditingController();
  final amountCtl = TextEditingController();
  String type = 'expense';
  String freq = 'monthly';
  int? accountId, toAccountId, categoryId;
  DateTime next = DateTime.now();
  bool autoPost = true;
  List<Map<String, Object?>> accounts = [], cats = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    accounts = await DB.accounts();
    final r = widget.rule;
    if (r != null) {
      titleCtl.text = r['title'] as String? ?? '';
      amountCtl.text = '${(r['amount'] as num?) ?? ''}';
      type = r['type'] as String? ?? 'expense';
      freq = r['freq'] as String? ?? 'monthly';
      accountId = r['accountId'] as int?;
      toAccountId = r['toAccountId'] as int?;
      categoryId = r['categoryId'] as int?;
      autoPost = (r['autoPost'] as int? ?? 1) == 1;
      next = DateTime.tryParse(r['nextDate'] as String? ?? '') ?? DateTime.now();
    }
    cats = await DB.categories(type: type == 'transfer' ? null : type);
    if (mounted) setState(() {});
  }

  Future<void> _reloadCats() async {
    cats = await DB.categories(type: type == 'transfer' ? null : type);
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    final amt = double.tryParse(amountCtl.text.replaceAll(',', '')) ?? 0;
    if (titleCtl.text.trim().isEmpty || amt <= 0 || accountId == null) {
      snack(context, 'Enter a title, amount and account');
      return;
    }
    final m = <String, Object?>{
      'title': titleCtl.text.trim(),
      'type': type,
      'amount': amt,
      'accountId': accountId,
      'toAccountId': type == 'transfer' ? toAccountId : null,
      'categoryId': type == 'transfer' ? null : categoryId,
      'note': titleCtl.text.trim(),
      'freq': freq,
      'dayOfMonth': next.day,
      'nextDate': DateTime(next.year, next.month, next.day).toIso8601String(),
      'autoPost': autoPost ? 1 : 0,
      'active': 1,
    };
    if (widget.rule == null) {
      await DB.insert('recurring', m);
    } else {
      m['id'] = widget.rule!['id'];
      await DB.update('recurring', m);
    }
    await DB.runRecurring();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.rule == null ? 'New recurring' : 'Edit recurring'),
        actions: [
          if (widget.rule != null)
            IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  await DB.delete('recurring', widget.rule!['id'] as int);
                  if (mounted) Navigator.pop(context);
                }),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'expense', label: Text('Expense')),
              ButtonSegment(value: 'income', label: Text('Income')),
              ButtonSegment(value: 'transfer', label: Text('Transfer')),
            ],
            selected: {type},
            onSelectionChanged: (s) {
              setState(() => type = s.first);
              _reloadCats();
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: titleCtl,
            decoration: const InputDecoration(
                labelText: 'Title (e.g. Wife pocket money)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: amountCtl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
                labelText: 'Amount', prefixText: '$kCur ', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            value: accountId,
            isExpanded: true,
            decoration: InputDecoration(
                labelText: type == 'transfer' ? 'From account' : 'Account',
                border: const OutlineInputBorder()),
            items: [
              for (final a in accounts)
                DropdownMenuItem(value: a['id'] as int, child: Text(a['name'] as String? ?? '')),
            ],
            onChanged: (v) => setState(() => accountId = v),
          ),
          if (type == 'transfer') ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: toAccountId,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'To account', border: OutlineInputBorder()),
              items: [
                for (final a in accounts)
                  DropdownMenuItem(value: a['id'] as int, child: Text(a['name'] as String? ?? '')),
              ],
              onChanged: (v) => setState(() => toAccountId = v),
            ),
          ] else ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: categoryId,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Category', border: OutlineInputBorder()),
              items: [
                for (final c in cats)
                  DropdownMenuItem(value: c['id'] as int, child: Text(c['name'] as String? ?? '')),
              ],
              onChanged: (v) => setState(() => categoryId = v),
            ),
          ],
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: freq,
            decoration: const InputDecoration(labelText: 'Repeats', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
              DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
              DropdownMenuItem(value: 'yearly', child: Text('Yearly')),
            ],
            onChanged: (v) => setState(() => freq = v ?? 'monthly'),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.event),
              title: const Text('First / next date'),
              subtitle: Text(DateFormat('d MMM yyyy').format(next)),
              onTap: () async {
                final p = await showDatePicker(
                    context: context,
                    initialDate: next,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100));
                if (p != null) setState(() => next = p);
              },
            ),
          ),
          SwitchListTile(
            title: const Text('Auto-post'),
            subtitle: Text(autoPost
                ? 'Creates the record automatically on its date'
                : 'Reminder only - you confirm manually'),
            value: autoPost,
            onChanged: (v) => setState(() => autoPost = v),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
