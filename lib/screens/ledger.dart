import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../db.dart';
import '../export.dart';
import '../widgets.dart';

class LedgerReportScreen extends StatefulWidget {
  const LedgerReportScreen({super.key});
  @override
  State<LedgerReportScreen> createState() => _LedgerReportScreenState();
}

class _LedgerReportScreenState extends State<LedgerReportScreen> {
  List<Map<String, Object?>> accounts = [];
  List<Map<String, Object?>> cats = [];
  List<String> labels = [];
  List<String> projects = [];

  DateTime from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime to = DateTime.now();
  int? accountId;
  int? categoryId;
  String? label;
  String? project;
  String type = 'all';

  List<Map<String, Object?>> rows = [];
  double totalDr = 0, totalCr = 0;
  bool busy = false;
  bool generated = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    accounts = await DB.accounts();
    cats = await DB.categories();
    labels = await DB.distinctLabels();
    projects = await DB.distinctProjects();
    if (mounted) setState(() {});
  }

  String _iso(DateTime d) => DateTime(d.year, d.month, d.day).toIso8601String();

  Future<void> _generate() async {
    setState(() => busy = true);
    final raw = await DB.ledgerRows(
      _iso(from),
      _iso(to.add(const Duration(days: 1))),
      accountId: accountId,
      categoryId: categoryId,
      label: label,
      project: project,
      type: type,
    );
    final out = <Map<String, Object?>>[];
    double dr = 0, cr = 0, running = 0;
    for (final r in raw) {
      final amt = (r['amount'] as num? ?? 0).toDouble();
      final t = r['type'] as String?;
      double rdr = 0, rcr = 0;
      if (t == 'income') {
        rcr = amt;
      } else if (t == 'expense') {
        rdr = amt;
      } else if (t == 'transfer') {
        // perspective: if filtered to an account that is the destination, it's a credit
        if (accountId != null && r['toAccountId'] == accountId) {
          rcr = amt;
        } else {
          rdr = amt;
        }
      }
      dr += rdr;
      cr += rcr;
      running += rcr - rdr;
      out.add({
        'date': r['date'],
        'detail': r['note'],
        'fromName': r['fromName'],
        'toName': r['toName'],
        'nature': (t ?? '').isEmpty ? '' : '${t![0].toUpperCase()}${t.substring(1)}',
        'category': r['catName'],
        'project': r['project'],
        'labels': r['labels'],
        'dr': rdr,
        'cr': rcr,
        'bal': running,
      });
    }
    if (!mounted) return;
    setState(() {
      rows = out;
      totalDr = dr;
      totalCr = cr;
      busy = false;
      generated = true;
    });
  }

  String get _subtitle {
    final parts = <String>['${DateFormat('d MMM yyyy').format(from)} to ${DateFormat('d MMM yyyy').format(to)}'];
    if (accountId != null) {
      parts.add('Account: ${accounts.firstWhere((a) => a['id'] == accountId)['name']}');
    }
    if (type != 'all') parts.add('Type: $type');
    if (project != null) parts.add('Project: $project');
    if (label != null) parts.add('Label: $label');
    return parts.join('  ·  ');
  }

  Future<void> _pickRange() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2010),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: from, end: to),
    );
    if (r != null) setState(() { from = r.start; to = r.end; });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Detailed report')),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.date_range),
                  title: Text('${DateFormat('d MMM yyyy').format(from)}  -  ${DateFormat('d MMM yyyy').format(to)}'),
                  trailing: const Icon(Icons.edit_calendar),
                  onTap: _pickRange,
                ),
                _dropdownInt('Account (any)', accountId, accounts, (v) => setState(() => accountId = v)),
                _dropdownInt('Category (any)', categoryId, cats, (v) => setState(() => categoryId = v)),
                if (projects.isNotEmpty)
                  _dropdownStr('Project / Cost centre (any)', project, projects, (v) => setState(() => project = v)),
                if (labels.isNotEmpty)
                  _dropdownStr('Label (any)', label, labels, (v) => setState(() => label = v)),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: const [
                    ButtonSegment(value: 'all', label: Text('All')),
                    ButtonSegment(value: 'income', label: Text('In')),
                    ButtonSegment(value: 'expense', label: Text('Out')),
                    ButtonSegment(value: 'transfer', label: Text('Transfer')),
                  ],
                  selected: {type},
                  onSelectionChanged: (s) => setState(() => type = s.first),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            icon: const Icon(Icons.search),
            label: Text(busy ? 'Working...' : 'Generate'),
            onPressed: busy ? null : _generate,
            style: FilledButton.styleFrom(padding: const EdgeInsets.all(14)),
          ),
          if (generated) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(12)),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _stat('Rows', rows.length.toString(), cs.onSecondaryContainer),
                _stat('Debit (out)', money(totalDr), Colors.red),
                _stat('Credit (in)', money(totalCr), Colors.green),
              ]),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('PDF'),
                  onPressed: rows.isEmpty ? null : () => exportLedgerPdf(
                      title: 'Detailed Report', subtitle: _subtitle, rows: rows),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.table_chart),
                  label: const Text('Excel'),
                  onPressed: rows.isEmpty ? null : () => exportLedgerExcel(
                      title: 'Detailed Report', subtitle: _subtitle, rows: rows),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            if (rows.isEmpty)
              const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('No transactions match these filters')))
            else
              ...rows.take(100).map(_previewRow),
            if (rows.length > 100)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text('Showing first 100 of ${rows.length}. Export to PDF/Excel for the full list.',
                    style: TextStyle(color: cs.outline, fontSize: 12)),
              ),
          ],
        ],
      ),
    );
  }

  Widget _stat(String k, String v, Color c) => Column(children: [
        Text(k, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 2),
        Text(v, style: TextStyle(fontWeight: FontWeight.bold, color: c)),
      ]);

  Widget _previewRow(Map<String, Object?> r) {
    final dr = (r['dr'] as num? ?? 0).toDouble();
    final cr = (r['cr'] as num? ?? 0).toDouble();
    final d = DateTime.tryParse(r['date'] as String? ?? '');
    return ListTile(
      dense: true,
      title: Text(((r['detail'] as String?)?.isNotEmpty == true ? r['detail'] as String : (r['category'] as String? ?? r['nature'] as String? ?? '')),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text([
        if (d != null) DateFormat('d MMM').format(d),
        r['nature'],
        if ((r['project'] as String?)?.isNotEmpty == true) '#${r['project']}',
      ].where((e) => e != null && (e as String).isNotEmpty).join(' · ')),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(dr > 0 ? '-${money(dr)}' : '+${money(cr)}',
              style: TextStyle(fontWeight: FontWeight.bold, color: dr > 0 ? Colors.red : Colors.green)),
          Text('Bal ${money((r['bal'] as num? ?? 0).toDouble())}',
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline)),
        ],
      ),
    );
  }

  Widget _dropdownInt(String label, int? value, List<Map<String, Object?>> items, ValueChanged<int?> onCh) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: DropdownButtonFormField<int?>(
          value: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder()),
          items: [
            const DropdownMenuItem(value: null, child: Text('Any')),
            for (final i in items) DropdownMenuItem(value: i['id'] as int, child: Text(i['name'] as String? ?? '')),
          ],
          onChanged: onCh,
        ),
      );

  Widget _dropdownStr(String label, String? value, List<String> items, ValueChanged<String?> onCh) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: DropdownButtonFormField<String?>(
          value: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder()),
          items: [
            const DropdownMenuItem(value: null, child: Text('Any')),
            for (final i in items) DropdownMenuItem(value: i, child: Text(i)),
          ],
          onChanged: onCh,
        ),
      );
}
