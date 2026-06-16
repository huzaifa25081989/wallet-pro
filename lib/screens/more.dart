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
import 'activate.dart';
import 'admin_branding.dart';
import 'insights.dart';
import 'drive_help.dart';
import '../branding.dart';
import '../pro.dart';
import 'accounts.dart';
import 'categories.dart';
import 'coa.dart';
import 'goals.dart';
import 'loans.dart';
import 'recurring.dart';

final _gsi = GoogleSignIn(scopes: [gd.DriveApi.driveAppdataScope]);

/// Called on app start. Backs up to Drive once a day if enabled.
Future<void> tryAutoBackup() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('autoBackup') ?? false)) return;
    final last = prefs.getInt('lastBackup') ?? 0;
    if (DateTime.now().millisecondsSinceEpoch - last < 20 * 3600 * 1000) return;
    final acct = await _gsi.signInSilently();
    if (acct == null) return;
    final client = await _gsi.authenticatedClient();
    if (client == null) return;
    await _upload(gd.DriveApi(client));
    await prefs.setInt('lastBackup', DateTime.now().millisecondsSinceEpoch);
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
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = '${info.version} (${info.buildNumber})');
    } catch (_) {}
  }

  Future<void> _checkUpdate() async {
    final uri = Uri.parse('https://github.com/huzaifa25081989/wallet-pro/releases/latest');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) snack(context, 'Could not open the releases page');
    }
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
      final header =
          rows.first.map((e) => e.toString().trim().toLowerCase()).toList();
      int idx(List<String> names) =>
          header.indexWhere((h) => names.any((n) => h.contains(n)));
      final iAcc = idx(['account']);
      final iCat = idx(['category']);
      final iAmt = idx(['amount']);
      final iDate = idx(['date']);
      final iNote = idx(['note', 'payee', 'description', 'label']);
      final iType = idx(['type']);
      if (iAmt < 0) {
        if (mounted) snack(context, 'No "amount" column found \u2014 is this a Wallet CSV export?');
        return;
      }

      final d = await DB.db;
      int n = 0;
      for (final r in rows.skip(1)) {
        if (r.length <= iAmt) continue;
        final amtRaw =
            r[iAmt].toString().replaceAll(',', '').replaceAll(' ', '').trim();
        final amt = double.tryParse(amtRaw);
        if (amt == null || amt == 0) continue;

        String type = amt < 0 ? 'expense' : 'income';
        if (iType >= 0) {
          final t = r[iType].toString().toLowerCase();
          if (t.contains('exp')) type = 'expense';
          if (t.contains('inc')) type = 'income';
          // Wallet exports transfers as two rows (one per account);
          // we import each by its amount sign so balances stay correct.
          if (t.contains('trans')) type = amt < 0 ? 'expense' : 'income';
        }

        final accName = iAcc >= 0 && r.length > iAcc && r[iAcc].toString().trim().isNotEmpty
            ? r[iAcc].toString().trim()
            : 'Imported';
        final catName = iCat >= 0 && r.length > iCat && r[iCat].toString().trim().isNotEmpty
            ? r[iCat].toString().trim()
            : (type == 'income' ? 'Other Income' : 'Other Expense');
        final accountId = await DB.accountByName(accName);
        final categoryId = await DB.catByName(catName, type);
        final date = iDate >= 0 && r.length > iDate
            ? _parseDate(r[iDate].toString())
            : DateTime.now().toIso8601String();
        final note =
            iNote >= 0 && r.length > iNote ? r[iNote].toString().trim() : '';

        await d.insert('txns', {
          'type': type,
          'amount': amt.abs(),
          'accountId': accountId,
          'toAccountId': null,
          'categoryId': categoryId,
          'date': date,
          'note': note,
        });
        n++;
      }
      bus.ping();
      if (mounted) snack(context, 'Imported $n records \u2714');
    } catch (e) {
      if (mounted) snack(context, 'Import failed: could not parse that file');
    }
  }

  // ---------------- Google Drive ----------------
  Future<void> _driveBackup() async {
    try {
      final api = await _driveApi();
      if (api == null) {
        if (mounted) snack(context, 'Google sign-in cancelled');
        return;
      }
      await _upload(api);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('lastBackup', DateTime.now().millisecondsSinceEpoch);
      if (mounted) snack(context, 'Backed up to Google Drive \u2714');
    } catch (e) {
      if (mounted) _showDriveError('backup', e.toString());
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
    if (v && !await requirePro(context, 'Automatic Google Drive backup')) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoBackup', v);
    setState(() => autoBackup = v);
    if (v) {
      snack(context, 'Auto backup enabled \u2014 backs up to Drive once a day on app open');
      _run(_driveBackup);
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
          const Divider(),
          const _Header('Google Drive'),
          ListTile(
            leading: const Icon(Icons.cloud_upload_outlined),
            title: const Text('Back up to Google Drive now'),
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
            subtitle: const Text('Backs up to Drive when you open the app'),
            value: autoBackup,
            onChanged: _toggleAuto,
          ),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('Google Drive setup help'),
            subtitle: const Text('Fix sign-in / backup errors'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const DriveHelpScreen())),
          ),
          const Divider(),
          const _Header('App'),
          ListTile(
            leading: Icon(pro.isPro ? Icons.verified : Icons.workspace_premium,
                color: Theme.of(context).colorScheme.primary),
            title: Text(pro.isPro ? 'Wallet Pro — Active' : 'Upgrade to Wallet Pro'),
            subtitle: Text(pro.isPro
                ? '${pro.tier.toUpperCase()} · until ${pro.expiryLabel}'
                : 'Unlock PDF/Excel export & cloud auto-backup'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ActivateScreen()))
                .then((_) => setState(() {})),
          ),
          ListTile(
            leading: const Icon(Icons.system_update_outlined),
            title: const Text('Check for updates'),
            subtitle: Text(_version.isEmpty ? 'Wallet Pro' : 'Installed: v$_version'),
            trailing: const Icon(Icons.open_in_new),
            onTap: _checkUpdate,
          ),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('About Developer'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const AboutDeveloperScreen())),
          ),
          if (pro.tier == 'business')
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
            subtitle: Text(branding.tagline),
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
