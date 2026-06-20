import 'dart:io';
import 'package:excel/excel.dart' as xl;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'widgets.dart';

final _d = DateFormat('dd-MM-yyyy');
String _money(num v) => fmt(v);
String _dt(Object? iso) {
  final t = DateTime.tryParse(iso as String? ?? '');
  return t == null ? '' : _d.format(t);
}

Future<void> _share(String filename, List<int> bytes, String text) async {
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/$filename');
  await f.writeAsBytes(bytes, flush: true);
  await Share.shareXFiles([XFile(f.path)], text: text);
}

/// statement = {opening, rows:[{date,desc,dr,cr,bal}], closing, totalDr, totalCr}
Future<void> exportStatementPdf({
  required String title,
  required String subtitle,
  required Map<String, Object?> statement,
}) async {
  final rows = (statement['rows'] as List).cast<Map<String, Object?>>();
  final opening = (statement['opening'] as num).toDouble();
  final closing = (statement['closing'] as num).toDouble();
  final totalDr = (statement['totalDr'] as num).toDouble();
  final totalCr = (statement['totalCr'] as num).toDouble();

  final doc = pw.Document();
  final data = <List<String>>[
    ['', 'Opening balance', '', '', _money(opening)],
    for (final r in rows)
      [
        _dt(r['date']),
        r['desc'] as String? ?? '',
        (r['dr'] as num) == 0 ? '' : _money(r['dr'] as num),
        (r['cr'] as num) == 0 ? '' : _money(r['cr'] as num),
        _money(r['bal'] as num),
      ],
    ['', 'Closing balance', _money(totalDr), _money(totalCr), _money(closing)],
  ];

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(24),
    header: (c) => pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 12),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('Wallet Pro',
            style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
        pw.Text(title,
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.Text(subtitle, style: pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
        pw.Divider(),
      ]),
    ),
    footer: (c) => pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text('Page ${c.pageNumber} of ${c.pagesCount}',
          style: pw.TextStyle(fontSize: 9, color: PdfColors.grey)),
    ),
    build: (c) => [
      pw.TableHelper.fromTextArray(
        headers: ['Date', 'Description', 'Debit', 'Credit', 'Balance'],
        data: data,
        border: pw.TableBorder.all(color: PdfColors.grey300, width: .5),
        headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey700),
        cellStyle: const pw.TextStyle(fontSize: 9),
        cellHeight: 18,
        cellAlignments: {
          0: pw.Alignment.centerLeft,
          1: pw.Alignment.centerLeft,
          2: pw.Alignment.centerRight,
          3: pw.Alignment.centerRight,
          4: pw.Alignment.centerRight,
        },
        oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
      ),
    ],
  ));

  final name = '${title.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}.pdf';
  await _share(name, await doc.save(), '$title\n$subtitle');
}

Future<void> exportStatementExcel({
  required String title,
  required String subtitle,
  required Map<String, Object?> statement,
}) async {
  final rows = (statement['rows'] as List).cast<Map<String, Object?>>();
  final opening = (statement['opening'] as num).toDouble();
  final closing = (statement['closing'] as num).toDouble();
  final totalDr = (statement['totalDr'] as num).toDouble();
  final totalCr = (statement['totalCr'] as num).toDouble();

  final book = xl.Excel.createExcel();
  final sheetName = 'Statement';
  final sheet = book[sheetName];
  // remove the auto-created default sheet if different
  for (final s in book.sheets.keys.toList()) {
    if (s != sheetName) book.delete(s);
  }

  void row(List<xl.CellValue?> cells) => sheet.appendRow(cells);
  xl.TextCellValue t(String s) => xl.TextCellValue(s);
  xl.DoubleCellValue n(num v) => xl.DoubleCellValue(v.toDouble());

  row([t(title)]);
  row([t(subtitle)]);
  row([]);
  row([t('Date'), t('Description'), t('Debit'), t('Credit'), t('Balance')]);
  row([t(''), t('Opening balance'), t(''), t(''), n(opening)]);
  for (final r in rows) {
    row([
      t(_dt(r['date'])),
      t(r['desc'] as String? ?? ''),
      (r['dr'] as num) == 0 ? t('') : n(r['dr'] as num),
      (r['cr'] as num) == 0 ? t('') : n(r['cr'] as num),
      n(r['bal'] as num),
    ]);
  }
  row([t(''), t('Totals'), n(totalDr), n(totalCr), t('')]);
  row([t(''), t('Closing balance'), t(''), t(''), n(closing)]);

  final bytes = book.save();
  if (bytes == null) return;
  final name = '${title.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}.xlsx';
  await _share(name, bytes, '$title\n$subtitle');
}

/// Category breakdown export (PDF) for a period.
Future<void> exportCategoryPdf({
  required String title,
  required String subtitle,
  required List<Map<String, Object?>> incomeRows,
  required List<Map<String, Object?>> expenseRows,
}) async {
  final doc = pw.Document();
  List<List<String>> tbl(List<Map<String, Object?>> rows) => [
        for (final r in rows)
          [r['n'] as String? ?? 'Uncategorized', _money((r['s'] as num?) ?? 0)],
      ];
  double sum(List<Map<String, Object?>> rows) =>
      rows.fold(0.0, (a, r) => a + ((r['s'] as num?) ?? 0).toDouble());

  doc.addPage(pw.MultiPage(
    margin: const pw.EdgeInsets.all(24),
    header: (c) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text('Wallet Pro', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
      pw.Text(title, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
      pw.Text(subtitle, style: pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
      pw.Divider(),
    ]),
    build: (c) => [
      pw.Text('Income by category', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
      pw.TableHelper.fromTextArray(
        headers: ['Category', 'Amount'],
        data: [...tbl(incomeRows), ['Total income', _money(sum(incomeRows))]],
        cellStyle: const pw.TextStyle(fontSize: 10),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.green700),
        headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold),
        cellAlignments: {1: pw.Alignment.centerRight},
      ),
      pw.SizedBox(height: 16),
      pw.Text('Expense by category', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
      pw.TableHelper.fromTextArray(
        headers: ['Category', 'Amount'],
        data: [...tbl(expenseRows), ['Total expense', _money(sum(expenseRows))]],
        cellStyle: const pw.TextStyle(fontSize: 10),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.red700),
        headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold),
        cellAlignments: {1: pw.Alignment.centerRight},
      ),
    ],
  ));
  final name = '${title.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}.pdf';
  await _share(name, await doc.save(), '$title\n$subtitle');
}

/// Detailed multi-column ledger export.
/// rows: [{date, detail, fromName, toName, nature, category, project, labels, dr(num), cr(num)}]
Future<void> exportLedgerPdf({
  required String title,
  required String subtitle,
  required List<Map<String, Object?>> rows,
}) async {
  double totalDr = 0, totalCr = 0;
  for (final r in rows) {
    totalDr += (r['dr'] as num? ?? 0).toDouble();
    totalCr += (r['cr'] as num? ?? 0).toDouble();
  }
  final headers = ['Date', 'Detail', 'From', 'To', 'Nature', 'Category', 'Project', 'Labels', 'Debit', 'Credit'];
  final data = <List<String>>[
    for (final r in rows)
      [
        _dt(r['date']),
        (r['detail'] as String? ?? ''),
        (r['fromName'] as String? ?? ''),
        (r['toName'] as String? ?? ''),
        (r['nature'] as String? ?? ''),
        (r['category'] as String? ?? ''),
        (r['project'] as String? ?? ''),
        (r['labels'] as String? ?? ''),
        (r['dr'] as num? ?? 0) == 0 ? '' : _money(r['dr'] as num),
        (r['cr'] as num? ?? 0) == 0 ? '' : _money(r['cr'] as num),
      ],
    ['', 'TOTALS', '', '', '', '', '', '', _money(totalDr), _money(totalCr)],
  ];
  final doc = pw.Document();
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4.landscape,
    margin: const pw.EdgeInsets.all(18),
    build: (ctx) => [
      pw.Text(title, style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
      pw.Text(subtitle, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
      pw.SizedBox(height: 8),
      pw.TableHelper.fromTextArray(
        headers: headers,
        data: data,
        border: pw.TableBorder.all(color: PdfColors.grey300, width: .5),
        headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.teal700),
        cellStyle: const pw.TextStyle(fontSize: 7.5),
        cellHeight: 16,
        cellAlignments: {
          8: pw.Alignment.centerRight,
          9: pw.Alignment.centerRight,
        },
      ),
    ],
  ));
  final name = '${title.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}.pdf';
  await _share(name, await doc.save(), '$title\n$subtitle');
}

Future<void> exportLedgerExcel({
  required String title,
  required String subtitle,
  required List<Map<String, Object?>> rows,
}) async {
  double totalDr = 0, totalCr = 0;
  for (final r in rows) {
    totalDr += (r['dr'] as num? ?? 0).toDouble();
    totalCr += (r['cr'] as num? ?? 0).toDouble();
  }
  final book = xl.Excel.createExcel();
  const sheetName = 'Ledger';
  final sheet = book[sheetName];
  for (final s in book.sheets.keys.toList()) {
    if (s != sheetName) book.delete(s);
  }
  void row(List<xl.CellValue?> cells) => sheet.appendRow(cells);
  xl.TextCellValue t(String s) => xl.TextCellValue(s);
  xl.DoubleCellValue n(num v) => xl.DoubleCellValue(v.toDouble());

  row([t(title)]);
  row([t(subtitle)]);
  row([]);
  row([t('Date'), t('Detail'), t('From'), t('To'), t('Nature'), t('Category'), t('Project'), t('Labels'), t('Debit'), t('Credit')]);
  for (final r in rows) {
    row([
      t(_dt(r['date'])),
      t(r['detail'] as String? ?? ''),
      t(r['fromName'] as String? ?? ''),
      t(r['toName'] as String? ?? ''),
      t(r['nature'] as String? ?? ''),
      t(r['category'] as String? ?? ''),
      t(r['project'] as String? ?? ''),
      t(r['labels'] as String? ?? ''),
      (r['dr'] as num? ?? 0) == 0 ? t('') : n(r['dr'] as num),
      (r['cr'] as num? ?? 0) == 0 ? t('') : n(r['cr'] as num),
    ]);
  }
  row([t(''), t('TOTALS'), t(''), t(''), t(''), t(''), t(''), t(''), n(totalDr), n(totalCr)]);

  final bytes = book.save();
  if (bytes == null) return;
  final name = '${title.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}.xlsx';
  await _share(name, bytes, '$title\n$subtitle');
}
