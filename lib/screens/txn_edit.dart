import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../db.dart';
import 'security.dart';
import '../widgets.dart';
import 'package:url_launcher/url_launcher.dart';

String trimAmt(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

/// One allocation line of a voucher: an expense/income category,
/// or a transfer to another account (for splitting a bill).
class _Line {
  String dest; // 'cat' | 'acct'
  int? catId;
  int? acctId;
  final TextEditingController amountCtl = TextEditingController();
  _Line({this.dest = 'cat', this.catId, this.acctId, double? amount}) {
    if (amount != null && amount > 0) amountCtl.text = trimAmt(amount);
  }
}

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
  final noteCtl = TextEditingController();
  final labelsCtl = TextEditingController();
  final projectCtl = TextEditingController();
  int? accountId;
  DateTime date = DateTime.now();
  List<Map<String, Object?>> accounts = [], cats = [];
  final List<_Line> lines = [_Line()];
  final stt = SpeechToText();
  bool listening = false;
  List<int> suggested = [];

  bool get isEdit => widget.txn != null;
  bool get isSplit => lines.length > 1;

  @override
  void initState() {
    super.initState();
    if (widget.initialType != null) type = widget.initialType!;
    if (widget.initialCategoryId != null) lines[0].catId = widget.initialCategoryId;
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
      accountId = t['accountId'] as int?;
      date = DateTime.tryParse(t['date'] as String? ?? '') ?? DateTime.now();
      noteCtl.text = t['note'] as String? ?? '';
      labelsCtl.text = t['labels'] as String? ?? '';
      projectCtl.text = t['project'] as String? ?? '';
      final line = lines[0];
      line.amountCtl.text = '${(t['amount'] as num?) ?? ''}';
      if (type == 'transfer') {
        line.dest = 'acct';
        line.acctId = t['toAccountId'] as int?;
      } else {
        line.dest = 'cat';
        line.catId = t['categoryId'] as int?;
      }
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

  List<Map<String, Object?>> get otherAccounts =>
      accounts.where((a) => a['id'] != accountId).toList();

  double get total {
    double s = 0;
    for (final l in lines) {
      s += double.tryParse(l.amountCtl.text.replaceAll(',', '').trim()) ?? 0;
    }
    return s;
  }

  void _onTypeChange(String t) {
    setState(() {
      type = t;
      for (final l in lines) {
        if (t == 'transfer') {
          l.dest = 'acct';
        } else if (t == 'income') {
          l.dest = 'cat';
        }
        l.catId = null;
      }
    });
    _loadSuggested();
  }

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

  /// Parses "expense 500 groceries", "income 25000 salary", "transfer 10000".
  void _applyVoice(String words) {
    final lower = words.toLowerCase().replaceAll(',', '');
    final m = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(lower);
    if (m != null) lines[0].amountCtl.text = m.group(1)!;
    if (RegExp(r'\b(income|salary|received|earned|got paid|revenue)\b').hasMatch(lower)) {
      type = 'income';
    } else if (lower.contains('transfer')) {
      type = 'transfer';
    } else {
      type = 'expense';
    }
    lines[0].dest = type == 'transfer' ? 'acct' : 'cat';
    lines[0].catId = null;
    if (type != 'transfer') {
      for (final c in cats.where((c) => c['type'] == type)) {
        final first = (c['name'] as String).toLowerCase().split(RegExp(r'[ &]+')).first;
        if (first.length > 2 && lower.contains(first)) {
          lines[0].catId = c['id'] as int;
          break;
        }
      }
    }
    noteCtl.text = words;
    if (mounted) setState(() {});
  }

  // ---------------- save / delete ----------------
  Future<void> _save() async {
    if (accountId == null) {
      snack(context, 'Select an account');
      return;
    }
    final valid = <_Line>[];
    for (final l in lines) {
      final amt = double.tryParse(l.amountCtl.text.replaceAll(',', '').trim()) ?? 0;
      if (amt <= 0) continue;
      if (l.dest == 'cat' && l.catId == null) {
        snack(context, 'Pick a category for every line');
        return;
      }
      if (l.dest == 'acct') {
        if (l.acctId == null) {
          snack(context, 'Pick a destination account for every transfer line');
          return;
        }
        if (l.acctId == accountId) {
          snack(context, 'Transfer line must use a different account');
          return;
        }
      }
      valid.add(l);
    }
    if (valid.isEmpty) {
      snack(context, 'Enter at least one line with an amount');
      return;
    }

    final note = noteCtl.text.trim();
    final labels = labelsCtl.text.trim();
    final project = projectCtl.text.trim();
    final dateStr = date.toIso8601String();

    if (isEdit) {
      final l = valid.first;
      final amt = double.parse(l.amountCtl.text.replaceAll(',', '').trim());
      await DB.update('txns', {
        'id': widget.txn!['id'],
        'type': l.dest == 'acct' ? 'transfer' : type,
        'amount': amt,
        'accountId': accountId,
        'toAccountId': l.dest == 'acct' ? l.acctId : null,
        'categoryId': l.dest == 'acct' ? null : l.catId,
        'date': dateStr,
        'note': note,
        'labels': labels,
        'project': project,
        'voucher': widget.txn!['voucher'],
      });
    } else {
      final voucher = valid.length > 1 ? 'V${DateTime.now().microsecondsSinceEpoch}' : null;
      for (final l in valid) {
        final amt = double.parse(l.amountCtl.text.replaceAll(',', '').trim());
        await DB.insert('txns', {
          'type': l.dest == 'acct' ? 'transfer' : type,
          'amount': amt,
          'accountId': accountId,
          'toAccountId': l.dest == 'acct' ? l.acctId : null,
          'categoryId': l.dest == 'acct' ? null : l.catId,
          'date': dateStr,
          'note': note,
          'labels': labels,
          'project': project,
          'voucher': voucher,
        });
      }
    }
    bus.ping();
    if (!isSplit) await _maybeNotify(total);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _maybeNotify(double amt) async {
    Map<String, Object?>? target;
    final ids = <int?>[accountId, for (final l in lines) if (l.dest == 'acct') l.acctId];
    for (final id in ids) {
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
    if (digits.startsWith('0')) digits = '92${digits.substring(1)}';
    final word = type == 'income' ? 'received' : type == 'expense' ? 'spent' : 'transferred';
    final msg = 'Hi $name, recorded in our account: $word ${money(amt)}'
        '${noteCtl.text.trim().isEmpty ? '' : ' (${noteCtl.text.trim()})'} on ${DateFormat('d MMM yyyy').format(date)}.';
    final uri = Uri.parse('https://wa.me/$digits?text=${Uri.encodeComponent(msg)}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _delete() async {
    if (!await requirePinForDelete(context)) return;
    if (!await confirm(context, 'Delete record?', 'This cannot be undone.')) return;
    await DB.delete('txns', widget.txn!['id'] as int);
    bus.ping();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit record' : 'New voucher'),
        actions: [
          if (isEdit)
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
            onSelectionChanged: (s) => _onTypeChange(s.first),
          ),
          const SizedBox(height: 16),
          PickerField(
            label: type == 'transfer' ? 'From account' : 'Account (paid from)',
            value: _acc(accountId),
            onTap: () async {
              final id = await pickEntity(context, 'Choose account', accounts, selected: accountId);
              if (id != null) setState(() => accountId = id);
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(isSplit ? 'Split lines' : 'Details',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              if (isSplit)
                Text('Total ${money(total)}',
                    style: TextStyle(fontWeight: FontWeight.bold, color: cs.primary)),
            ],
          ),
          const SizedBox(height: 8),
          for (int i = 0; i < lines.length; i++) _lineCard(i),
          if (!isEdit)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => lines.add(_Line(dest: type == 'transfer' ? 'acct' : 'cat'))),
                icon: const Icon(Icons.add),
                label: Text(type == 'transfer'
                    ? 'Add another transfer (split bill)'
                    : 'Add split line (category or person)'),
              ),
            ),
          const SizedBox(height: 8),
          if (!isSplit && type != 'transfer' && suggested.isNotEmpty)
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
                        selected: lines[0].catId == sid && lines[0].dest == 'cat',
                        onSelected: (_) => setState(() {
                          lines[0].dest = 'cat';
                          lines[0].catId = sid;
                        }),
                      ),
                ],
              ),
            ),
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
            decoration: const InputDecoration(labelText: 'Note (optional)', border: OutlineInputBorder()),
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
          const SizedBox(height: 12),
          TextField(
            controller: projectCtl,
            decoration: const InputDecoration(
                labelText: 'Project / Cost centre (optional)',
                hintText: 'e.g. Home Renovation, Office, Trip 2026',
                prefixIcon: Icon(Icons.workspaces_outline),
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
            child: Text(isSplit ? 'Save voucher (${lines.length} lines)' : 'Save record'),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
                isEdit
                    ? 'Editing one line of this voucher'
                    : 'Tip: add lines to split across categories or people in one voucher',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _lineCard(int i) {
    final l = lines[i];
    final showToggle = type == 'expense';
    final destIsAcct = l.dest == 'acct';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (isSplit)
                  Text('Line ${i + 1}',
                      style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.outline)),
                const Spacer(),
                if (showToggle)
                  SegmentedButton<String>(
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    segments: const [
                      ButtonSegment(value: 'cat', label: Text('Category')),
                      ButtonSegment(value: 'acct', label: Text('To account')),
                    ],
                    selected: {l.dest},
                    onSelectionChanged: (s) => setState(() {
                      l.dest = s.first;
                      l.catId = null;
                      l.acctId = null;
                    }),
                  ),
                if (lines.length > 1 && !isEdit)
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => setState(() => lines.removeAt(i)),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            if (destIsAcct || type == 'transfer')
              PickerField(
                label: 'Transfer to',
                value: _acc(l.acctId),
                onTap: () async {
                  final id = await pickEntity(context, 'Transfer to', otherAccounts, selected: l.acctId);
                  if (id != null) setState(() => l.acctId = id);
                },
              )
            else
              PickerField(
                label: 'Category',
                value: _cat(catItems.any((c) => c['id'] == l.catId) ? l.catId : null),
                onTap: () async {
                  final id = await pickEntity(context, 'Choose category', catItems, selected: l.catId);
                  if (id != null) setState(() => l.catId = id);
                },
              ),
            const SizedBox(height: 10),
            TextField(
              controller: l.amountCtl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: '$kCur ',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
    );
  }
}
