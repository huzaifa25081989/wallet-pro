import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../db.dart';
import '../widgets.dart';
import 'package:url_launcher/url_launcher.dart';

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
  final labelsCtl = TextEditingController();
  int? accountId, toAccountId, categoryId;
  DateTime date = DateTime.now();
  List<Map<String, Object?>> accounts = [], cats = [];
  final stt = SpeechToText();
  bool listening = false;
  List<int> suggested = [];

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
      labelsCtl.text = t['labels'] as String? ?? '';
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
    _loadSuggested();
  }

  Future<void> _loadSuggested() async {
    if (type == 'transfer') {
      if (mounted) setState(() => suggested = []);
      return;
    }
    final sug = await DB.suggestedCats(type);
    if (mounted) setState(() => suggested = sug);
  }

  Map<String, Object?>? _acc(int? id) {
    for (final a in accounts) {
      if (a['id'] == id) return a;
    }
    return null;
  }

  Map<String, Object?>? _cat(int? id) {
    for (final c in cats) {
      if (c['id'] == id) return c;
    }
    return null;
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
      'labels': labelsCtl.text.trim(),
    };
    if (widget.txn == null) {
      await DB.insert('txns', m);
    } else {
      m['id'] = widget.txn!['id'];
      await DB.update('txns', m);
    }
    await _maybeNotify(amt);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _maybeNotify(double amt) async {
    // find an involved account that has a phone number
    Map<String, Object?>? target;
    for (final id in [accountId, if (type == 'transfer') toAccountId]) {
      final a = _acc(id);
      final ph = (a?['phone'] as String?)?.trim() ?? '';
      if (ph.isNotEmpty) {
        target = a;
        break;
      }
    }
    if (target == null || !mounted) return;
    final name = target['name'] as String? ?? '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Notify $name on WhatsApp?'),
        content: Text('Send $name a message that you recorded ${money(amt)} in your shared account.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Send')),
        ],
      ),
    );
    if (ok != true) return;
    var digits = (target['phone'] as String).replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('0')) digits = '92${digits.substring(1)}'; // PK default
    final word = type == 'income' ? 'received' : type == 'expense' ? 'spent' : 'transferred';
    final note = noteCtl.text.trim();
    final msg = 'Hi $name, recorded in our account: $word ${money(amt)}'
        '${note.isEmpty ? '' : ' ($note)'} on ${DateFormat('d MMM yyyy').format(date)}.';
    final uri = Uri.parse('https://wa.me/$digits?text=${Uri.encodeComponent(msg)}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
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
            onSelectionChanged: (s) {
              setState(() {
                type = s.first;
                categoryId = null;
              });
              _loadSuggested();
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: amountCtl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              labelText: 'Amount',
              prefixText: '$kCur ',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          PickerField(
            label: type == 'transfer' ? 'From account' : 'Account',
            value: _acc(accountId),
            onTap: () async {
              final id = await pickEntity(context, 'Choose account', accounts, selected: accountId);
              if (id != null) setState(() => accountId = id);
            },
          ),
          const SizedBox(height: 12),
          if (type == 'transfer')
            PickerField(
              label: 'To account',
              value: _acc(toAccountId == accountId ? null : toAccountId),
              onTap: () async {
                final id = await pickEntity(context, 'Transfer to',
                    accounts.where((a) => a['id'] != accountId).toList(),
                    selected: toAccountId);
                if (id != null) setState(() => toAccountId = id);
              },
            )
          else ...[
            if (suggested.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final sid in suggested)
                      if (_cat(sid) != null)
                        ChoiceChip(
                          avatar: Icon(iconOf(_cat(sid)!['icon']), size: 16,
                              color: Color((_cat(sid)!['color'] as int?) ?? 0xFF9E9E9E)),
                          label: Text(_cat(sid)!['name'] as String? ?? ''),
                          selected: categoryId == sid,
                          onSelected: (_) => setState(() => categoryId = sid),
                        ),
                  ],
                ),
              ),
            PickerField(
              label: 'Category',
              value: _cat(validCat),
              onTap: () async {
                final id = await pickEntity(context, 'Choose category', catItems, selected: validCat);
                if (id != null) setState(() => categoryId = id);
              },
            ),
          ],
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
          const SizedBox(height: 12),
          TextField(
            controller: labelsCtl,
            decoration: const InputDecoration(
                labelText: 'Labels / tags (comma separated)',
                hintText: 'e.g. Trip, Family, Reimbursable',
                prefixIcon: Icon(Icons.label_outline),
                border: OutlineInputBorder()),
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
