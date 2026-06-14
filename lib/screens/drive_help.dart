import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets.dart';

const kSha1 = 'E0:65:41:60:17:12:AC:CC:F2:79:71:B8:62:93:E7:BE:37:F2:32:A5';
const kPackage = 'com.huzaifa.wallet_pro';

class DriveHelpScreen extends StatelessWidget {
  const DriveHelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Widget step(int n, String title, String body) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(radius: 13, child: Text('$n')),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(body, style: const TextStyle(fontSize: 13)),
              ]),
            ),
          ]),
        );

    Widget copyRow(String label, String value) => Card(
          child: ListTile(
            dense: true,
            title: Text(label, style: const TextStyle(fontSize: 12)),
            subtitle: SelectableText(value, style: const TextStyle(fontSize: 12)),
            trailing: IconButton(
              icon: const Icon(Icons.copy, size: 18),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                snack(context, 'Copied');
              },
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Google Drive setup')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
              'Automatic Google Drive backup needs a one-time setup in your own Google Cloud account (free). This registers the app so Google lets it sign in.',
              style: TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          copyRow('App package name', kPackage),
          copyRow('Signing certificate SHA-1', kSha1),
          const SizedBox(height: 12),
          step(1, 'Open Google Cloud Console',
              'Create a project (or pick one) at console.cloud.google.com.'),
          step(2, 'Enable the Drive API',
              'APIs & Services → Library → search "Google Drive API" → Enable.'),
          step(3, 'OAuth consent screen',
              'APIs & Services → OAuth consent screen → External → fill app name + your email → add your Gmail under "Test users".'),
          step(4, 'Create Android OAuth client',
              'Credentials → Create credentials → OAuth client ID → Android. Paste the package name and SHA-1 above.'),
          step(5, 'Wait a few minutes',
              'Google can take 5-10 minutes to activate. Then tap "Back up to Google Drive" again.'),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open Google Cloud Console'),
            onPressed: () => launchUrl(Uri.parse('https://console.cloud.google.com/apis/credentials'),
                mode: LaunchMode.externalApplication),
          ),
          const SizedBox(height: 10),
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                  'No time for this? You don\'t need Drive at all: use "Export backup file" to send a backup to WhatsApp, email, or save it to Drive manually. Your data is never at risk.',
                  style: TextStyle(fontSize: 12.5)),
            ),
          ),
        ],
      ),
    );
  }
}
