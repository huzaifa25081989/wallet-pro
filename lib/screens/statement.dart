import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../db.dart';
import '../export.dart';
import '../theme.dart';
import '../widgets.dart';

class StatementScreen extends StatefulWidget {
  final int? accountId;
  const StatementScreen({super.key, this.accountId});
  @override
  State<StatementScreen> createState() => _StatementScreenState();
}

class _StatementScreenState extends State<StatementScreen> {
  late DateTime from;
  late DateTime to;
  int? accountId;
  List<Map<String, Object?>> accounts = [];
  Map<String, Object?>? data;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    from = DateTime(now.year, now.month, 1);
    to = DateTime(now.year, now.month, now.day);
    accountId = widget.accountId;
    _init();
  }

  Future<void> _init() async {
    accounts = await DB.accounts();
    await _load();
  }

  String get _fromIso => DateTime(from.year, from.month, from.day).toIso8601String();
  String get _toIso =>
      DateTime(to.year, to.month, to.day).add(const Duration(days: 1)).toIso8601String();

  String get _title {
    if (accountId == null) return 'Statement - All Accounts';
    final a = accounts.firstWhere((e) => e['id'] == accountId, orElse: () => {});
    return 'Statement - ${a['name'] ?? ''}';
  }

  String get _subtitle =>
      '${DateFormat('dd MMM yyyy').format(from)} to ${DateFormat('dd MMM yyyy').format(to)}';

  Future<void> _load() async {
    final s = await DB.statement(accountId, _fromIso, _toIso);
    if (!mounted) return;
    setState(() => data = s);
  }

  Future<void> _pick(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? from : to,
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => isFrom ? from = picked : to = picked);
      _load();
    }
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() => busy = true);
    try {
      await f();
    } catch (e) {
      if (mounted) snack(context, 'Export failed: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rows = (data?['rows'] as List?)?.cast<Map<String, Object?>>() ?? [];
    return Scaffold(
      appBar: AppBar(title: const Text('Statement & Export')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              DropdownButtonFormField<int?>(
                value: accountId,
                decoration: const InputDecoration(labelText: 'Account'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All accounts (cash position)')),
                  for (final a in accounts)
                    DropdownMenuItem(value: a['id'] as int, child: Text(a['name'] as String? ?? '')),
                ],
                onChanged: (v) {
                  setState(() => accountId = v);
                  _load();
                },
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.event, size: 18),
                    label: Text('From: ${DateFormat('dd MMM yy').format(from)}'),
                    onPressed: () => _pick(true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.event, size: 18),
                    label: Text('To: ${DateFormat('dd MMM yy').format(to)}'),
                    onPressed: () => _pick(false),
                  ),
                ),
              ]),
              const SizedBox(height: 6),
              Wrap(spacing: 8, children: [
                for (final q in const ['This month', 'Last month', 'This year', 'Last 12 months'])
                  ActionChip(label: Text(q), onPressed: () => _quick(q)),
              ]),
            ]),
          ),
          // summary band
          if (data != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: headerGradient(context),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                _band('Opening', (data!['opening'] as num).toDouble()),
                _band('Debit', (data!['totalDr'] as num).toDouble()),
                _band('Credit', (data!['totalCr'] as num).toDouble()),
                _band('Closing', (data!['closing'] as num).toDouble()),
              ]),
            ),
          const SizedBox(height: 6),
          // header row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(children: const [
              Expanded(flex: 3, child: Text('Date / Description', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
              Expanded(flex: 2, child: Text('Dr', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
              Expanded(flex: 2, child: Text('Cr', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
              Expanded(flex: 2, child: Text('Balance', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
            ]),
          ),
          const Divider(height: 8),
          Expanded(
            child: rows.isEmpty
                ? const Center(child: Text('No transactions in this range'))
                : ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final r = rows[i];
                      final dr = (r['dr'] as num).toDouble();
                      final cr = (r['cr'] as num).toDouble();
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(
                            flex: 3,
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(DateFormat('dd MMM yyyy').format(DateTime.parse(r['date'] as String)),
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                              Text(r['desc'] as String? ?? '',
                                  style: TextStyle(fontSize: 11, color: cs.outline),
                                  maxLines: 2, overflow: TextOverflow.ellipsis),
                            ]),
                          ),
                          Expanded(flex: 2, child: Text(dr == 0 ? '' : fmt(dr), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, color: Colors.red))),
                          Expanded(flex: 2, child: Text(cr == 0 ? '' : fmt(cr), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, color: Colors.green))),
                          Expanded(flex: 2, child: Text(fmt((r['bal'] as num)), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
                        ]),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.picture_as_pdf, size: 18),
                label: const Text('PDF'),
                onPressed: busy || data == null
                    ? null
                    : () => _run(() => exportStatementPdf(
                        title: _title, subtitle: _subtitle, statement: data!)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.tonalIcon(
                icon: const Icon(Icons.grid_on, size: 18),
                label: const Text('Excel'),
                onPressed: busy || data == null
                    ? null
                    : () => _run(() => exportStatementExcel(
                        title: _title, subtitle: _subtitle, statement: data!)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.pie_chart, size: 18),
                label: const Text('By Category'),
                onPressed: busy ? null : _categoryExport,
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _categoryExport() => _run(() async {
        final inc = await DB.catTotals('income', _fromIso, _toIso);
        final exp = await DB.catTotals('expense', _fromIso, _toIso);
        await exportCategoryPdf(
          title: 'Category Summary',
          subtitle: _subtitle,
          incomeRows: inc,
          expenseRows: exp,
        );
      });

  void _quick(String q) {
    final now = DateTime.now();
    setState(() {
      switch (q) {
        case 'Last month':
          final m = DateTime(now.year, now.month - 1, 1);
          from = m;
          to = DateTime(now.year, now.month, 0);
          break;
        case 'This year':
          from = DateTime(now.year, 1, 1);
          to = now;
          break;
        case 'Last 12 months':
          from = DateTime(now.year - 1, now.month, now.day);
          to = now;
          break;
        default: // This month
          from = DateTime(now.year, now.month, 1);
          to = now;
      }
    });
    _load();
  }

  Widget _band(String k, double v) => Column(children: [
        Text(k, style: const TextStyle(color: Colors.white70, fontSize: 10)),
        const SizedBox(height: 2),
        Text(fmt(v),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
      ]);
}
