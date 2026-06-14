import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../db.dart';
import '../widgets.dart';

class LoansScreen extends StatefulWidget {
  const LoansScreen({super.key});
  @override
  State<LoansScreen> createState() => _LoansScreenState();
}

class _LoansScreenState extends State<LoansScreen> {
  List<Map<String, Object?>> loans = [];

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
    final l = await DB.all('loans', orderBy: 'dueDate');
    if (!mounted) return;
    setState(() => loans = l);
  }

  Future<void> _addPayment(Map<String, Object?> l) async {
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Add payment \u2014 ${l['name']}'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
              labelText: 'Payment amount', prefixText: '$kCur ', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true) return;
    final amt = double.tryParse(ctl.text.replaceAll(',', '')) ?? 0;
    if (amt <= 0) return;
    final paid = (((l['paid'] as num?) ?? 0).toDouble() + amt);
    await DB.update('loans', {'id': l['id'], 'paid': paid});
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: const Text('Loans & Debts')),
      floatingActionButton: FloatingActionButton(
        heroTag: 'loans_fab',
        onPressed: () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => const LoanEdit())),
        child: const Icon(Icons.add),
      ),
      body: loans.isEmpty
          ? const Center(
              child: Text('No loans or debts yet.\nTap + to add one.',
                  textAlign: TextAlign.center))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final l in loans) _loanCard(l, now),
                const SizedBox(height: 80),
              ],
            ),
    );
  }

  Widget _loanCard(Map<String, Object?> l, DateTime now) {
    final principal = ((l['principal'] as num?) ?? 0).toDouble();
    final paid = ((l['paid'] as num?) ?? 0).toDouble();
    final rate = ((l['rate'] as num?) ?? 0).toDouble();
    final borrowed = l['type'] == 'borrowed';
    final due = DateTime.tryParse(l['dueDate'] as String? ?? '');
    final overdue = due != null && due.isBefore(now) && paid < principal;
    final ratio = principal > 0 ? (paid / principal).clamp(0.0, 1.0) : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(l['name'] as String? ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              Chip(
                label: Text(borrowed ? 'I owe' : 'Owed to me',
                    style: const TextStyle(fontSize: 11, color: Colors.white)),
                backgroundColor: borrowed ? Colors.red : Colors.green,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            ]),
            const SizedBox(height: 4),
            Text(
              '${money(principal)}'
              '${rate > 0 ? ' \u2022 ${rate.toStringAsFixed(rate.truncateToDouble() == rate ? 0 : 1)}% p.a.' : ''}'
              '${due != null ? ' \u2022 due ${DateFormat('d MMM yyyy').format(due)}' : ''}',
              style: TextStyle(
                  fontSize: 12, color: overdue ? Colors.red : Colors.grey,
                  fontWeight: overdue ? FontWeight.bold : FontWeight.normal),
            ),
            if (overdue)
              const Text('OVERDUE',
                  style: TextStyle(
                      color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 8,
                color: borrowed ? Colors.red : Colors.green,
                backgroundColor: Colors.grey.shade300,
              ),
            ),
            const SizedBox(height: 6),
            Text(
                'Repaid ${money(paid)} of ${money(principal)} \u2022 remaining ${money((principal - paid).clamp(0, double.infinity))}',
                style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            Row(children: [
              FilledButton.tonalIcon(
                onPressed: paid >= principal ? null : () => _addPayment(l),
                icon: const Icon(Icons.add, size: 16),
                label: Text(paid >= principal ? 'Settled' : 'Add payment'),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20),
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => LoanEdit(loan: l))),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class LoanEdit extends StatefulWidget {
  final Map<String, Object?>? loan;
  const LoanEdit({super.key, this.loan});
  @override
  State<LoanEdit> createState() => _LoanEditState();
}

class _LoanEditState extends State<LoanEdit> {
  final nameCtl = TextEditingController();
  final principalCtl = TextEditingController();
  final rateCtl = TextEditingController(text: '0');
  final noteCtl = TextEditingController();
  String type = 'borrowed';
  DateTime? due;

  @override
  void initState() {
    super.initState();
    final l = widget.loan;
    if (l != null) {
      nameCtl.text = l['name'] as String? ?? '';
      principalCtl.text = '${(l['principal'] as num?) ?? ''}';
      rateCtl.text = '${(l['rate'] as num?) ?? 0}';
      noteCtl.text = l['note'] as String? ?? '';
      type = l['type'] as String? ?? 'borrowed';
      due = DateTime.tryParse(l['dueDate'] as String? ?? '');
    }
  }

  Future<void> _save() async {
    final principal = double.tryParse(principalCtl.text.replaceAll(',', ''));
    if (nameCtl.text.trim().isEmpty || principal == null || principal <= 0) {
      snack(context, 'Enter a name and a valid amount');
      return;
    }
    final m = <String, Object?>{
      'name': nameCtl.text.trim(),
      'type': type,
      'principal': principal,
      'rate': double.tryParse(rateCtl.text) ?? 0,
      'dueDate': due?.toIso8601String(),
      'note': noteCtl.text.trim(),
    };
    if (widget.loan == null) {
      m['paid'] = 0.0;
      await DB.insert('loans', m);
    } else {
      m['id'] = widget.loan!['id'];
      m['paid'] = widget.loan!['paid'];
      await DB.update('loans', m);
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    if (!await confirm(context, 'Delete loan?', 'This cannot be undone.')) return;
    await DB.delete('loans', widget.loan!['id'] as int);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.loan == null ? 'Add loan / debt' : 'Edit loan / debt'),
          actions: [
            if (widget.loan != null)
              IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'borrowed', label: Text('I owe (borrowed)')),
                ButtonSegment(value: 'lent', label: Text('Owed to me (lent)')),
              ],
              selected: {type},
              onSelectionChanged: (s) => setState(() => type = s.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtl,
              decoration: const InputDecoration(
                  labelText: 'Name (person / bank / purpose)',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: principalCtl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Principal amount',
                  prefixText: '$kCur ',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: rateCtl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Interest / profit rate (% per year, 0 if none)',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.event),
                title: Text(due == null
                    ? 'Due date (optional)'
                    : DateFormat('d MMM yyyy').format(due!)),
                trailing: due == null
                    ? const Icon(Icons.add, size: 18)
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => setState(() => due = null)),
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: due ?? DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (d != null) setState(() => due = d);
                },
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtl,
              decoration: const InputDecoration(
                  labelText: 'Note (optional)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
              child: const Text('Save'),
            ),
          ],
        ),
      );
}
