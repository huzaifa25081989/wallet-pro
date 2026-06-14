import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../db.dart';
import '../widgets.dart';

class TxnEdit extends StatefulWidget {
  final Map<String, Object?>? txn;
  final bool autoVoice;
  final String? initialType;
  final int? initialCategoryId;
  const TxnEdit(
      {super.key,
      this.txn,
      this.autoVoice = false,
      this.initialType,
      this.initialCategoryId});
  @override
  State<TxnEdit> createState() => _TxnEditState();
}

class _TxnEditState extends State<TxnEdit> {
  String type = 'expense';
  final amountCtl = TextEditingController();
  final noteCtl = TextEditingController();
  int? accountId, toAccountId, categoryId;
  DateTime date = DateTime.now();
  List<Map<String, Object?>> accounts = [], cats = [];
  final stt = SpeechToText();
  bool listening = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialType != null) type = widget.initialType!;
    if (widget.initialCategoryId != null) categoryId = widget.initialCategoryId;
    _load().then((_) {
      if (widget.autoVoice && mounted) _voice();
    });
  }

  Future<void> _load() async {
    final a = await DB.accounts();
    final c = await DB.categories();
    final t = widget.txn;
    if (t != null) {
      type = t['type'] as String? ?? 'expense';
      amountCtl.text = '${(t['amount'] as num?) ?? ''}';
      noteCtl.text = t['note'] as String? ?? '';
      accountId = t['accountId'] as int?;
      toAccountId = t['toAccountId'] as int?;
      categoryId = t['categoryId'] as int?;
      date = DateTime.tryParse(t['date'] as String? ?? '') ?? DateTime.now();
    }
    if (!mounted) return;
    setState(() {
      accounts = a;
      cats = c;
      accountId ??= accounts.isNotEmpty ? accounts.first['id'] as int : null;
    });
  }

  List<Map<String, Object?>> get catItems =>
      cats.where((c) => c['type'] == type).toList();

  // ---------------- voice entry ----------------
  Future<void> _voice() async {
    if (listening) {
      await stt.stop();
      setState(() => listening = false);
      return;
    }
    final ok = await stt.initialize(onError: (_) {
      if (mounted) setState(() => listening = false);
    });
    if (!ok) {
      if (mounted) snack(context, 'Speech recognition not available on this device');
      return;
    }
    setState(() => listening = true);
    stt.listen(onResult: (r) {
      if (r.finalResult) {
        _applyVoice(r.recognizedWords);
        if (mounted) setState(() => listening = false);
      }
    });
  }

  /// Parses phrases like "expense 500 groceries lunch with team"
  /// or "income 25000 salary" or "transfer 10000".
  void _applyVoice(String words) {
    final lower = words.toLowerCase().replaceAll(',', '');
    final m = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(lower);
    if (m != null) amountCtl.text = m.group(1)!;
    if (RegExp(r'\b(income|salary|received|earned|got paid|revenue)\b').hasMatch(lower)) {
      type = 'income';
    } else if (lower.contains('transfer')) {
      type = 'transfer';
    } else {
      type = 'expense';
    }
    categoryId = null;
    if (type != 'transfer') {
      for (final c in cats.where((c) => c['type'] == type)) {
        final first =
            (c['name'] as String).toLowerCase().split(RegExp(r'[ &]+')).first;
        if (first.length > 2 && lower.contains(first)) {
          categoryId = c['id'] as int;
          break;
        }
      }
    }
    noteCtl.text = words;
    if (mounted) setState(() {});
  }

  // ---------------- save / delete ----------------
  Future<void> _save() async {
    final amt = double.tryParse(amountCtl.text.replaceAll(',', ''));
    if (amt == null || amt <= 0) {
      snack(context, 'Enter a valid amount');
      return;
    }
    if (accountId == null) {
      snack(context, 'Select an account');
      return;
    }
    if (type == 'transfer') {
      if (toAccountId == null || toAccountId == accountId) {
        snack(context, 'Select a different destination account');
        return;
      }
    } else if (categoryId == null) {
      snack(context, 'Select a category');
      return;
    }
    final m = <String, Object?>{
      'type': type,
      'amount': amt,
      'accountId': accountId,
      'toAccountId': type == 'transfer' ? toAccountId : null,
      'categoryId': type == 'transfer' ? null : categoryId,
      'date': date.toIso8601String(),
      'note': noteCtl.text.trim(),
    };
    if (widget.txn == null) {
      await DB.insert('txns', m);
    } else {
      m['id'] = widget.txn!['id'];
      await DB.update('txns', m);
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    if (!await confirm(context, 'Delete record?', 'This cannot be undone.')) return;
    await DB.delete('txns', widget.txn!['id'] as int);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final validCat = catItems.any((c) => c['id'] == categoryId) ? categoryId : null;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.txn == null ? 'Add record' : 'Edit record'),
        actions: [
          if (widget.txn != null)
            IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'mic_fab',
        backgroundColor: listening ? Colors.red : null,
        onPressed: _voice,
        tooltip: 'Speak: "expense 500 groceries"',
        child: Icon(listening ? Icons.mic : Icons.mic_none),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'expense', label: Text('Expense'), icon: Icon(Icons.remove)),
              ButtonSegment(value: 'income', label: Text('Income'), icon: Icon(Icons.add)),
              ButtonSegment(value: 'transfer', label: Text('Transfer'), icon: Icon(Icons.swap_horiz)),
            ],
            selected: {type},
            onSelectionChanged: (s) => setState(() {
              type = s.first;
              categoryId = null;
            }),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: amountCtl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            decoration: const InputDecoration(
              labelText: 'Amount',
              prefixText: '$kCur ',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            value: accountId,
            decoration: InputDecoration(
                labelText: type == 'transfer' ? 'From account' : 'Account',
                border: const OutlineInputBorder()),
            items: [
              for (final a in accounts)
                DropdownMenuItem(
                  value: a['id'] as int,
                  child: Row(children: [
                    Icon(iconOf(a['icon']), size: 18, color: Color((a['color'] as int?) ?? 0xFF607D8B)),
                    const SizedBox(width: 8),
                    Text(a['name'] as String? ?? ''),
                  ]),
                ),
            ],
            onChanged: (v) => setState(() => accountId = v),
          ),
          const SizedBox(height: 12),
          if (type == 'transfer')
            DropdownButtonFormField<int>(
              value: toAccountId == accountId ? null : toAccountId,
              decoration: const InputDecoration(
                  labelText: 'To account', border: OutlineInputBorder()),
              items: [
                for (final a in accounts.where((a) => a['id'] != accountId))
                  DropdownMenuItem(
                      value: a['id'] as int, child: Text(a['name'] as String? ?? '')),
              ],
              onChanged: (v) => setState(() => toAccountId = v),
            )
          else
            DropdownButtonFormField<int>(
              value: validCat,
              decoration: const InputDecoration(
                  labelText: 'Category', border: OutlineInputBorder()),
              items: [
                for (final c in catItems)
                  DropdownMenuItem(
                    value: c['id'] as int,
                    child: Row(children: [
                      Icon(iconOf(c['icon']), size: 18, color: Color((c['color'] as int?) ?? 0xFF9E9E9E)),
                      const SizedBox(width: 8),
                      Text(c['name'] as String? ?? ''),
                    ]),
                  ),
              ],
              onChanged: (v) => setState(() => categoryId = v),
            ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.calendar_today),
              title: Text(DateFormat('EEE, d MMM yyyy').format(date)),
              trailing: const Icon(Icons.edit_outlined, size: 18),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (d != null) setState(() => date = DateTime(d.year, d.month, d.day, date.hour, date.minute));
              },
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: noteCtl,
            decoration: const InputDecoration(
                labelText: 'Note (optional)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
            child: const Text('Save record'),
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text('Tip: tap the mic and say "expense 500 groceries"',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}
