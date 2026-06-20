import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as gd;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../db.dart';
import '../theme.dart';
import '../widgets.dart';
import 'appearance.dart';
import 'about.dart';
import 'admin_branding.dart';
import 'insights.dart';
import 'drive_help.dart';
import '../updater.dart';
import 'networth.dart';
import 'simulator.dart';
import 'reconcile.dart';
import 'split_expense.dart';
import 'split_bill.dart';
import 'setbalances.dart';
import 'cloud.dart';
import '../cloud.dart';
import '../branding.dart';
import 'accounts.dart';
import 'categories.dart';
import 'coa.dart';
import 'goals.dart';
import 'loans.dart';
import 'recurring.dart';

final _gsi = GoogleSignIn(scopes: [gd.DriveApi.driveAppdataScope]);

/// Writes a JSON backup to a stable folder on the device. No sign-in needed.
Future<String?> writeLocalBackup() async {
  try {
    final base = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/WalletProBackups');
    if (!await dir.exists()) await dir.create(recursive: true);
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    final f = File('${dir.path}/wallet_pro_backup_$stamp.json');
    await f.writeAsString(jsonEncode(await DB.dump()), flush: true);
    // keep only the latest 10 dated backups
    final files = dir.listSync().whereType<File>().where((e) => e.path.endsWith('.json')).toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    for (final old in files.skip(10)) {
      try { old.deleteSync(); } catch (_) {}
    }
    return f.path;
  } catch (_) {
    return null;
  }
}

/// Called on app start. Saves a local backup once a day if enabled. Never errors.
Future<void> tryAutoBackup() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('autoBackup') ?? false)) return;
    final last = prefs.getInt('lastBackup') ?? 0;
    if (DateTime.now().millisecondsSinceEpoch - last < 20 * 3600 * 1000) return;
    final path = await writeLocalBackup();
    if (path != null) {
      await prefs.setInt('lastBackup', DateTime.now().millisecondsSinceEpoch);
    }
  } catch (_) {
    // Silent: auto-backup must never crash the app.
  }
}

Future<gd.DriveApi?> _driveApi() async {
  var acct = await _gsi.signInSilently();
  acct ??= await _gsi.signIn();
  if (acct == null) return null;
  final client = await _gsi.authenticatedClient();
  if (client == null) return null;
  return gd.DriveApi(client);
}

Future<void> _upload(gd.DriveApi api) async {
  final bytes = utf8.encode(jsonEncode(await DB.dump()));
  final old = await api.files
      .list(spaces: 'appDataFolder', q: "name = 'wallet_backup.json'");
  for (final f in old.files ?? <gd.File>[]) {
    try {
      await api.files.delete(f.id!);
    } catch (_) {}
  }
  final meta = gd.File()
    ..name = 'wallet_backup.json'
    ..parents = ['appDataFolder'];
  await api.files
      .create(meta, uploadMedia: gd.Media(Stream.value(bytes), bytes.length));
}

class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});
  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  bool autoBackup = false;
  bool busy = false;
  bool adminUnlocked = false;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _loadVersion();
    DB.settingGet('adminUnlocked').then((v) { if (mounted) setState(() => adminUnlocked = v == '1'); });
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = '${info.version} (${info.buildNumber})');
    } catch (_) {}
  }


  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => autoBackup = prefs.getBool('autoBackup') ?? false);
  }

  Future<void> _run(Future<void> Function() fn) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await fn();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  // ---------------- local backup ----------------
  Future<void> _exportBackup() async {
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    final f = File('${dir.path}/wallet_pro_backup_$stamp.json');
    await f.writeAsString(jsonEncode(await DB.dump()));
    await Share.shareXFiles([XFile(f.path)], text: 'Wallet Pro backup');
  }

  Future<void> _restoreBackup() async {
    if (!await confirm(context, 'Restore backup?',
        'This REPLACES all current data with the backup file. Continue?')) {
      return;
    }
    final res = await FilePicker.platform.pickFiles(type: FileType.any);
    if (res == null || res.files.single.path == null) return;
    try {
      final raw = await File(res.files.single.path!).readAsString();
      await DB.restore(jsonDecode(raw) as Map);
      if (mounted) snack(context, 'Backup restored \u2714');
    } catch (e) {
      if (mounted) snack(context, 'Could not read that file as a Wallet Pro backup');
    }
  }

  // ---------------- Wallet (BudgetBakers) CSV import ----------------
  String _parseDate(String s) {
    s = s.trim();
    var d = DateTime.tryParse(s);
    if (d == null) {
      final m = RegExp(r'^(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{4})').firstMatch(s);
      if (m != null) {
        d = DateTime(
            int.parse(m.group(3)!), int.parse(m.group(2)!), int.parse(m.group(1)!));
      }
    }
    return (d ?? DateTime.now()).toIso8601String();
  }

  Future<void> _importWalletCsv() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.any);
    if (res == null || res.files.single.path == null) return;

    // Offer a clean import (clears existing transactions first) so a re-import
    // after fixing transfers does not create duplicates.
    final clearFirst = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Import options'),
        content: const Text(
            'Do you want to clear existing transactions before importing? Choose "Clear & import" if you are re-importing the same backup.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Just add')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Clear & import')),
        ],
      ),
    );
    if (clearFirst == null) return;

    try {
      final raw = await File(res.files.single.path!).readAsString();
      final firstLine = raw.split('\n').first;
      final delim = firstLine.contains(';') ? ';' : ',';
      final rows = const CsvToListConverter(shouldParseNumbers: false)
          .convert(raw.replaceAll('\r\n', '\n'), fieldDelimiter: delim, eol: '\n');
      if (rows.length < 2) {
        if (mounted) snack(context, 'No data rows found in that file');
        return;
      }
      final header = rows.first.map((e) => e.toString().trim().toLowerCase()).toList();
      int idx(List<String> names) => header.indexWhere((h) => names.any((n) => h.contains(n)));
      final iAcc = idx(['account']);
      final iCat = idx(['category']);
      final iAmt = idx(['amount']);
      final iDate = idx(['date']);
      final iNote = idx(['note', 'payee', 'description', 'label']);
      final iType = idx(['type']);
      final iTransfer = idx(['transfer']); // some exports have a transfer flag/partner
      final iLabels = idx(['labels']);
      if (iAmt < 0) {
        if (mounted) snack(context, 'No "amount" column found \u2014 is this a Wallet CSV export?');
        return;
      }

      String cell(List r, int i) =>
          (i >= 0 && r.length > i) ? r[i].toString().trim() : '';

      // Parse into structured records first.
      final normal = <Map<String, Object?>>[];
      final transfers = <Map<String, Object?>>[]; // {acc, amt(signed), date, note}
      for (final r in rows.skip(1)) {
        if (r.length <= iAmt) continue;
        final amtRaw = r[iAmt].toString().replaceAll(',', '').replaceAll(' ', '').trim();
        final amt = double.tryParse(amtRaw);
        if (amt == null || amt == 0) continue;

        final typeText = cell(r, iType).toLowerCase();
        final catText = cell(r, iCat);
        final transferText = cell(r, iTransfer).toLowerCase();
        final isTransfer = typeText.contains('trans') ||
            catText.toLowerCase().contains('transfer') ||
            transferText == 'true' ||
            transferText == '1' ||
            (transferText.isNotEmpty && transferText != 'false' && transferText != '0' && iType < 0 && iTransfer >= 0);

        final accName = cell(r, iAcc).isNotEmpty ? cell(r, iAcc) : 'Imported';
        final note = cell(r, iNote);
        final date = iDate >= 0 ? _parseDate(cell(r, iDate)) : DateTime.now().toIso8601String();

        if (isTransfer) {
          transfers.add({'acc': accName, 'amt': amt, 'date': date, 'note': note});
        } else {
          String type = amt < 0 ? 'expense' : 'income';
          if (typeText.contains('exp')) type = 'expense';
          if (typeText.contains('inc')) type = 'income';
          normal.add({
            'acc': accName,
            'amt': amt.abs(),
            'type': type,
            'cat': catText.isNotEmpty ? catText : (type == 'income' ? 'Other Income' : 'Other Expense'),
            'date': date,
            'note': note,
            'labels': cell(r, iLabels),
          });
        }
      }

      final d = await DB.db;
      if (clearFirst) {
        await d.delete('txns');
      }

      int n = 0;
      // Insert normal income/expense
      for (final m in normal) {
        final accountId = await DB.accountByName(m['acc'] as String);
        final categoryId = await DB.catByName(m['cat'] as String, m['type'] as String);
        await d.insert('txns', {
          'type': m['type'],
          'amount': m['amt'],
          'accountId': accountId,
          'toAccountId': null,
          'categoryId': categoryId,
          'date': m['date'],
          'note': m['note'],
          'labels': m['labels'],
        });
        n++;
      }

      // Pair transfer legs: outgoing (amt<0) with incoming (amt>0) by amount+date.
      final outs = transfers.where((t) => (t['amt'] as double) < 0).toList();
      final ins = transfers.where((t) => (t['amt'] as double) > 0).toList();
      final usedIn = <int>{};
      String dayKey(String iso) {
        final dt = DateTime.tryParse(iso);
        return dt == null ? iso : '${dt.year}-${dt.month}-${dt.day}';
      }
      for (final o in outs) {
        final amt = (o['amt'] as double).abs();
        final oDay = dayKey(o['date'] as String);
        int match = -1;
        for (int k = 0; k < ins.length; k++) {
          if (usedIn.contains(k)) continue;
          if (((ins[k]['amt'] as double) - amt).abs() < 0.01 &&
              dayKey(ins[k]['date'] as String) == oDay) {
            match = k;
            break;
          }
        }
        // relax to amount-only if no same-day match
        if (match < 0) {
          for (int k = 0; k < ins.length; k++) {
            if (usedIn.contains(k)) continue;
            if (((ins[k]['amt'] as double) - amt).abs() < 0.01) {
              match = k;
              break;
            }
          }
        }
        if (match >= 0) {
          usedIn.add(match);
          final fromId = await DB.accountByName(o['acc'] as String);
          final toId = await DB.accountByName(ins[match]['acc'] as String);
          await d.insert('txns', {
            'type': 'transfer',
            'amount': amt,
            'accountId': fromId,
            'toAccountId': toId,
            'categoryId': null,
            'date': o['date'],
            'note': o['note'],
          });
          n++;
        } else {
          // unpaired outgoing -> transfer to suspense account (NEVER expense/income)
          final accountId = await DB.accountByName(o['acc'] as String);
          final clearingId = await DB.accountByName('Transfers (other side)');
          await d.insert('txns', {
            'type': 'transfer',
            'amount': amt,
            'accountId': accountId,
            'toAccountId': clearingId,
            'categoryId': null,
            'date': o['date'],
            'note': o['note'],
          });
          n++;
        }
      }
      // any unpaired incoming -> transfer FROM suspense account (NEVER income)
      for (int k = 0; k < ins.length; k++) {
        if (usedIn.contains(k)) continue;
        final accountId = await DB.accountByName(ins[k]['acc'] as String);
        final clearingId = await DB.accountByName('Transfers (other side)');
        await d.insert('txns', {
          'type': 'transfer',
          'amount': (ins[k]['amt'] as double).abs(),
          'accountId': clearingId,
          'toAccountId': accountId,
          'categoryId': null,
          'date': ins[k]['date'],
          'note': ins[k]['note'],
        });
        n++;
      }

      bus.ping();
      if (mounted) snack(context, 'Imported $n records \u2714 (transfers linked)');
    } catch (e) {
      if (mounted) snack(context, 'Import failed: could not parse that file');
    }
  }

  // ---------------- Google Drive ----------------
  Future<void> _driveBackup() async {
    try {
      final api = await _driveApi();
      if (api == null) {
        // sign-in unavailable -> just save locally + share, no error
        await _localBackupAndShare();
        return;
      }
      await _upload(api);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('lastBackup', DateTime.now().millisecondsSinceEpoch);
      if (mounted) snack(context, 'Backed up to Google Drive \u2714');
    } catch (e) {
      // Auto-resolve: Drive not set up -> save a local backup and open share sheet.
      await _localBackupAndShare();
    }
  }

  Future<void> _localBackupAndShare() async {
    final path = await writeLocalBackup();
    if (path != null) {
      if (mounted) {
        snack(context, 'Saved a backup on your phone & opened sharing (Drive sign-in not set up)');
      }
      try {
        await Share.shareXFiles([XFile(path)], text: 'Wallet Pro backup');
      } catch (_) {}
    } else if (mounted) {
      snack(context, 'Could not write backup file');
    }
  }

  Future<void> _driveRestore() async {
    if (!await confirm(context, 'Restore from Drive?',
        'This REPLACES all current data with your Drive backup. Continue?')) {
      return;
    }
    try {
      final api = await _driveApi();
      if (api == null) return;
      final list = await api.files.list(
          spaces: 'appDataFolder',
          q: "name = 'wallet_backup.json'",
          orderBy: 'modifiedTime desc');
      if (list.files == null || list.files!.isEmpty) {
        if (mounted) snack(context, 'No backup found in Google Drive');
        return;
      }
      final media = await api.files.get(list.files!.first.id!,
          downloadOptions: gd.DownloadOptions.fullMedia) as gd.Media;
      final bytes = <int>[];
      await for (final chunk in media.stream) {
        bytes.addAll(chunk);
      }
      await DB.restore(jsonDecode(utf8.decode(bytes)) as Map);
      if (mounted) snack(context, 'Restored from Google Drive \u2714');
    } catch (e) {
      if (mounted) _showDriveError('restore', e.toString());
    }
  }

  void _showDriveError(String action, String err) {
    final dev = err.contains('10:') || err.toLowerCase().contains('developer');
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Drive $action failed'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (dev)
              const Text(
                  'This is the common Android OAuth error (code 10). It means this app\'s package + signing fingerprint are not yet registered in your Google Cloud project. The setup steps fix it.',
                  style: TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            const Text('Technical detail:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            SelectableText(err, style: const TextStyle(fontSize: 11)),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(c);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const DriveHelpScreen()));
            },
            child: const Text('Setup help'),
          ),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _toggleAuto(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoBackup', v);
    setState(() => autoBackup = v);
    if (v) {
      final path = await writeLocalBackup();
      await prefs.setInt('lastBackup', DateTime.now().millisecondsSinceEpoch);
      if (mounted) {
        snack(context, path != null
            ? 'Auto backup on \u2014 saves a backup file on your phone daily'
            : 'Auto backup on');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        children: [
          const _Header('Insights'),
          ListTile(
            leading: const Icon(Icons.auto_awesome, color: Colors.amber),
            title: const Text('Smart Insights & Health Score'),
            subtitle: const Text('Spending analysis, score, subscriptions'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const InsightsScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.account_balance, color: Colors.indigo),
            title: const Text('Net Worth dashboard'),
            subtitle: const Text('Cash, bank, investments, gold, property...'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const NetWorthScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.calculate, color: Colors.deepPurple),
            title: const Text('What-if Simulator'),
            subtitle: const Text('"Can I afford a house in 5 years?"'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const SimulatorScreen())),
          ),
          const Divider(),
          const _Header('Recording tools'),
          ListTile(
            leading: const Icon(Icons.call_split, color: Colors.teal),
            title: const Text('Split expense (one payment, many categories)'),
            subtitle: const Text('e.g. one Cash payment = grocery + medical + food'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const SplitExpenseScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.groups, color: Colors.deepOrange),
            title: const Text('Split a bill with friends'),
            subtitle: const Text('You pay, friends owe you (equal or custom)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const SplitBillScreen())),
          ),
          const Divider(),
          const _Header('Personalize'),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Appearance & Theme'),
            subtitle: Text('${theme.current.name} theme'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const AppearanceScreen())),
          ),
          const Divider(),
          const _Header('Manage'),
          ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: const Text('Accounts & Wallets'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const AccountsScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.label_outline),
            title: const Text('Categories'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const CategoriesScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.account_tree_outlined),
            title: const Text('Chart of Accounts'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const CoaScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.handshake_outlined),
            title: const Text('Loans & Debts'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const LoansScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.event_repeat_outlined),
            title: const Text('Recurring & Planned'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const RecurringScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: const Text('Savings Goals'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const GoalsScreen())),
          ),
          const Divider(),
          const _Header('Backup & data'),
          ListTile(
            leading: const Icon(Icons.upload_file_outlined),
            title: const Text('Export backup file'),
            subtitle: const Text('Share a JSON backup (WhatsApp, email, Drive...)'),
            onTap: busy ? null : () => _run(_exportBackup),
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Restore backup file'),
            subtitle: const Text('Replaces all current data'),
            onTap: busy ? null : () => _run(_restoreBackup),
          ),
          ListTile(
            leading: const Icon(Icons.move_to_inbox_outlined),
            title: const Text('Import from Wallet (BudgetBakers)'),
            subtitle: const Text('Pick the CSV exported from the Wallet app'),
            onTap: busy ? null : () => _run(_importWalletCsv),
          ),
          ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: const Text('Import & reconcile bank statement'),
            subtitle: const Text('Find what is not yet recorded, add in one tap'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const ReconcileScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('Set account balances'),
            subtitle: const Text('Enter correct balances (fixes opening balances)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const SetBalancesScreen())),
          ),
          const Divider(),
          const _Header('Cloud account (recommended)'),
          ListenableBuilder(
            listenable: cloud,
            builder: (_, __) => ListTile(
              leading: Icon(cloud.signedIn ? Icons.cloud_done : Icons.cloud_outlined,
                  color: cloud.signedIn ? Colors.green : Theme.of(context).colorScheme.primary),
              title: Text(cloud.signedIn ? 'Cloud backup is ON' : 'Set up cloud backup (free)'),
              subtitle: Text(cloud.signedIn
                  ? '${cloud.email} · auto-syncs every change'
                  : 'Email sign-in — restore on any phone, never lose data'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const CloudScreen())),
            ),
          ),
          const Divider(),
          const _Header('Manual backup files'),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: const Text('Back up now (save & share)'),
            subtitle: const Text('Saves a file on your phone, then lets you send it anywhere'),
            onTap: busy ? null : () => _run(_localBackupAndShare),
          ),
          ListTile(
            leading: const Icon(Icons.cloud_upload_outlined),
            title: const Text('Back up to Google Drive (optional)'),
            subtitle: const Text('Needs one-time Drive setup; falls back to file if not set up'),
            onTap: busy ? null : () => _run(_driveBackup),
          ),
          ListTile(
            leading: const Icon(Icons.cloud_download_outlined),
            title: const Text('Restore from Google Drive'),
            onTap: busy ? null : () => _run(_driveRestore),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.schedule_outlined),
            title: const Text('Auto backup daily'),
            subtitle: const Text('Saves a backup file on your phone once a day (no sign-in needed)'),
            value: autoBackup,
            onChanged: _toggleAuto,
          ),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('Google Drive setup help'),
            subtitle: const Text('Only if you want automatic Drive sync'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const DriveHelpScreen())),
          ),
          const Divider(),
          const _Header('App'),
          ListTile(
            leading: const Icon(Icons.system_update_outlined),
            title: const Text('Check for updates'),
            subtitle: Text(_version.isEmpty ? 'Update inside the app' : 'Installed: v$_version'),
            trailing: const Icon(Icons.download_for_offline_outlined),
            onTap: () => checkForUpdate(context),
          ),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('About Developer'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const AboutDeveloperScreen())),
          ),
          if (adminUnlocked)
            ListTile(
              leading: Icon(Icons.admin_panel_settings, color: Theme.of(context).colorScheme.primary),
              title: const Text('Admin · Branding & Content'),
              subtitle: const Text('Edit app name, currency, About text'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => const AdminBrandingScreen()))
                  .then((_) => setState(() {})),
            ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(branding.appName),
            subtitle: Text('${branding.tagline}\nLong-press to toggle admin mode'),
            isThreeLine: true,
            onLongPress: () async {
              adminUnlocked = !adminUnlocked;
              await DB.settingSet('adminUnlocked', adminUnlocked ? '1' : '0');
              if (mounted) {
                setState(() {});
                snack(context, adminUnlocked ? 'Admin mode ON' : 'Admin mode OFF');
              }
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text,
            style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 13)),
      );
}
