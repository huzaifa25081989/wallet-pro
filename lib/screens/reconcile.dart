import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as xl;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../db.dart';
import '../widgets.dart';

class _Row {
  final DateTime date;
  final String desc;
  final double amount;
  bool selected;
  bool duplicate;
  _Row(this.date, this.desc, this.amount, {this.selected = true, this.duplicate = false});
}

class ReconcileScreen extends StatefulWidget {
  const ReconcileScreen({super.key});
  @override
  State<ReconcileScreen> createState() => _ReconcileScreenState();
}

class _ReconcileScreenState extends State<ReconcileScreen> {
  List<Map<String, Object?>> accounts = [], cats = [];
  int? accountId, categoryId;
  String type = 'expense';
  List<_Row> rows = [];
  bool busy = false;
  String? fileName;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    accounts = await DB.accounts();
    cats = await DB.categories(type: type);
    if (mounted) setState(() {});
  }

  DateTime? _parseDate(String s) {
    s = s.trim();
    for (final f in ['dd-MM-yyyy', 'dd/MM/yyyy', 'yyyy-MM-dd', 'MM/dd/yyyy', 'd-MMM-yyyy', 'dd-MMM-yy']) {
      try {
        return DateFormat(f).parseStrict(s);
      } catch (_) {}
    }
    return DateTime.tryParse(s);
  }

  double? _parseAmount(String s) {
    final cleaned = s.replaceAll(RegExp(r'[^0-9.\-]'), '');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  Future<void> _pick() async {
    final res = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['xlsx', 'csv', 'xls'], withData: true);
    if (res == null || res.files.isEmpty) return;
    final file = res.files.first;
    fileName = file.name;
    final data = file.bytes;
    if (data == null) {
      snack(context, 'Could not read file');
      return;
    }
    List<List<String>> grid = [];
    try {
      if (file.extension?.toLowerCase() == 'csv') {
        final text = utf8.decode(data, allowMalformed: true);
        final delim = text.contains(';') && !text.contains(',') ? ';' : ',';
        final list = CsvToListConverter(fieldDelimiter: delim, eol: '\n', shouldParseNumbers: false)
            .convert(text);
        grid = list.map((r) => r.map((c) => c.toString()).toList()).toList();
      } else {
        final book = xl.Excel.decodeBytes(data);
        for (final t in book.tables.keys) {
          for (final r in book.tables[t]!.rows) {
            grid.add(r.map((c) => c?.value?.toString() ?? '').toList());
          }
          break; // first sheet
        }
      }
    } catch (e) {
      if (mounted) snack(context, 'Parse error: $e');
      return;
    }
    _extract(grid);
  }

  void _extract(List<List<String>> grid) {
    // find header row with a date-like and amount-like column
    int headerIdx = -1, dateCol = -1, descCol = -1, amtCol = -1;
    for (int i = 0; i < grid.length && i < 40; i++) {
      final r = grid[i].map((c) => c.toLowerCase()).toList();
      for (int j = 0; j < r.length; j++) {
        if (dateCol < 0 && r[j].contains('date')) dateCol = j;
        if (descCol < 0 && (r[j].contains('desc') || r[j].contains('narration') || r[j].contains('detail') || r[j].contains('particular'))) descCol = j;
        if (amtCol < 0 && (r[j].contains('amount') || r[j].contains('pkr') || r[j].contains('debit'))) amtCol = j;
      }
      if (dateCol >= 0 && amtCol >= 0) {
        headerIdx = i;
        break;
      }
      dateCol = descCol = amtCol = -1;
    }
    final parsed = <_Row>[];
    if (headerIdx >= 0) {
      for (int i = headerIdx + 1; i < grid.length; i++) {
        final r = grid[i];
        if (dateCol >= r.length || amtCol >= r.length) continue;
        final d = _parseDate(r[dateCol]);
        final a = _parseAmount(r[amtCol]);
        if (d == null || a == null || a == 0) continue;
        final desc = descCol >= 0 && descCol < r.length ? r[descCol] : 'Imported';
        parsed.add(_Row(d, desc.trim(), a.abs()));
      }
    }
    if (parsed.isEmpty) {
      snack(context, 'No transactions found. Make sure the file has Date and Amount columns.');
    }
    setState(() => rows = parsed);
    _markDuplicates();
  }

  Future<void> _markDuplicates() async {
    if (accountId == null || rows.isEmpty) return;
    final existing = await DB.all('txns', where: 'accountId=?', args: [accountId]);
    final keys = <String>{};
    for (final t in existing) {
      final d = DateTime.tryParse(t['date'] as String? ?? '');
      final amt = ((t['amount'] as num?) ?? 0).toDouble();
      if (d != null) keys.add('${d.year}-${d.month}-${d.day}@${amt.round()}');
    }
    for (final r in rows) {
      bool dup = false;
      for (int off = -2; off <= 2; off++) {
        final d = r.date.add(Duration(days: off));
        if (keys.contains('${d.year}-${d.month}-${d.day}@${r.amount.round()}')) {
          dup = true;
          break;
        }
      }
      r.duplicate = dup;
      r.selected = !dup;
    }
    if (mounted) setState(() {});
  }

  Future<void> _record() async {
    if (accountId == null) {
      snack(context, 'Choose the account this statement belongs to');
      return;
    }
    final chosen = rows.where((r) => r.selected && !r.duplicate).toList();
    if (chosen.isEmpty) {
      snack(context, 'Nothing selected to record');
      return;
    }
    setState(() => busy = true);
    for (final r in chosen) {
      await DB.insert('txns', {
        'type': type,
        'amount': r.amount,
        'accountId': accountId,
        'toAccountId': null,
        'categoryId': categoryId,
        'date': r.date.toIso8601String(),
        'note': r.desc,
      });
    }
    if (mounted) {
      setState(() => busy = false);
      snack(context, 'Recorded ${chosen.length} transactions');
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final newCount = rows.where((r) => !r.duplicate).length;
    final dupCount = rows.length - newCount;
    return Scaffold(
      appBar: AppBar(title: const Text('Import & Reconcile Statement')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            DropdownButtonFormField<int>(
              value: accountId,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Statement belongs to account', border: OutlineInputBorder()),
              items: [
                for (final a in accounts)
                  DropdownMenuItem(value: a['id'] as int, child: Text(a['name'] as String? ?? '')),
              ],
              onChanged: (v) {
                setState(() => accountId = v);
                _markDuplicates();
              },
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'expense', label: Text('Charges')),
                    ButtonSegment(value: 'income', label: Text('Credits')),
                  ],
                  selected: {type},
                  onSelectionChanged: (s) {
                    setState(() => type = s.first);
                    _load();
                  },
                ),
              ),
            ]),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              value: categoryId,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Category for imported items', border: OutlineInputBorder()),
              items: [
                for (final c in cats)
                  DropdownMenuItem(value: c['id'] as int, child: Text(c['name'] as String? ?? '')),
              ],
              onChanged: (v) => setState(() => categoryId = v),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.upload_file),
              label: Text(fileName ?? 'Pick statement (Excel / CSV)'),
              onPressed: _pick,
            ),
          ]),
        ),
        if (rows.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(children: [
              Text('$newCount new', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
              const SizedBox(width: 12),
              Text('$dupCount already recorded', style: TextStyle(color: cs.outline)),
            ]),
          ),
        const Divider(height: 12),
        Expanded(
          child: rows.isEmpty
              ? const Center(
                  child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                          'Pick a bank/credit-card statement file. The app finds the Date, Description and Amount columns, then shows which rows are not yet recorded so you can add them in one tap.',
                          textAlign: TextAlign.center)))
              : ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (_, i) {
                    final r = rows[i];
                    return CheckboxListTile(
                      dense: true,
                      value: r.selected,
                      onChanged: r.duplicate ? null : (v) => setState(() => r.selected = v ?? false),
                      title: Text(r.desc, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                          '${DateFormat('dd MMM yyyy').format(r.date)}${r.duplicate ? ' · already recorded' : ''}'),
                      secondary: Text(money(r.amount),
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: r.duplicate ? cs.outline : null)),
                    );
                  },
                ),
        ),
      ]),
      bottomNavigationBar: rows.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: FilledButton.icon(
                  icon: const Icon(Icons.check),
                  label: Text(busy ? 'Recording...' : 'Record selected'),
                  onPressed: busy ? null : _record,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.all(14)),
                ),
              ),
            ),
    );
  }
}
