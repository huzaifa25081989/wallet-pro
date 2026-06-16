import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

const _repo = 'huzaifa25081989/wallet-pro';

int _verNum(String tag) {
  // tag like "v1.0.12" -> 12 ; fallback parse last integer group
  final m = RegExp(r'(\d+)\s*$').firstMatch(tag.trim());
  return m == null ? 0 : int.tryParse(m.group(1)!) ?? 0;
}

Future<void> checkForUpdate(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  void say(String m) => messenger.showSnackBar(SnackBar(content: Text(m)));
  say('Checking for updates...');
  try {
    final info = await PackageInfo.fromPlatform();
    final current = int.tryParse(info.buildNumber) ?? 0;
    final res = await http.get(
      Uri.parse('https://api.github.com/repos/$_repo/releases/latest'),
      headers: {'Accept': 'application/vnd.github+json'},
    );
    if (res.statusCode == 404) {
      if (context.mounted) {
        _enableUpdatesDialog(context);
      }
      return;
    }
    if (res.statusCode != 200) {
      say('Update check failed (${res.statusCode}).');
      return;
    }
    final data = jsonDecode(res.body) as Map<String, Object?>;
    final tag = data['tag_name'] as String? ?? '';
    final latest = _verNum(tag);
    final assets = (data['assets'] as List?) ?? [];
    String? url;
    for (final a in assets) {
      final name = (a as Map)['name'] as String? ?? '';
      if (name.toLowerCase().endsWith('.apk')) {
        url = a['browser_download_url'] as String?;
        break;
      }
    }
    if (latest <= current || url == null) {
      say('You are on the latest version (v${info.version}).');
      return;
    }
    if (!context.mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Update available'),
        content: Text(
            'A newer version ($tag) is available. Download and install it now? Your data stays intact.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Later')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Update now')),
        ],
      ),
    );
    if (go != true) return;
    await _downloadAndInstall(context, url, tag);
  } catch (e) {
    say('Update check error: $e');
  }
}

Future<void> _downloadAndInstall(BuildContext context, String url, String tag) async {
  final messenger = ScaffoldMessenger.of(context);
  final entry = OverlayEntry(
    builder: (_) => Container(
      color: Colors.black54,
      child: const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Downloading update...'),
            ]),
          ),
        ),
      ),
    ),
  );
  Overlay.of(context).insert(entry);
  try {
    final res = await http.get(Uri.parse(url));
    final dir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/WalletPro_$tag.apk');
    await f.writeAsBytes(res.bodyBytes, flush: true);
    entry.remove();
    final open = await OpenFilex.open(f.path, type: 'application/vnd.android.package-archive');
    if (open.type != ResultType.done) {
      messenger.showSnackBar(SnackBar(
          content: Text('Downloaded. If install did not start, allow "Install unknown apps" for Wallet Pro. (${open.message})')));
    }
  } catch (e) {
    if (entry.mounted) entry.remove();
    messenger.showSnackBar(SnackBar(content: Text('Download failed: $e')));
  }
}

void _enableUpdatesDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('In-app updates not enabled'),
      content: const Text(
          'To update inside the app, the GitHub repository releases must be public so the app can download them. Make the repo Public in GitHub settings, then try again. (Your data always stays private on your phone.)'),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
    ),
  );
}
