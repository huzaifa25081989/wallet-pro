import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../branding.dart';
import '../theme.dart';

class AboutDeveloperScreen extends StatelessWidget {
  const AboutDeveloperScreen({super.key});

  @override
  Widget build(BuildContext context) {
    String digits(String s) {
      var d = s.replaceAll(RegExp(r'[^0-9]'), '');
      if (d.startsWith('0')) d = '92${d.substring(1)}';
      return d;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('About Developer')),
      body: ListenableBuilder(
        listenable: branding,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                  gradient: headerGradient(context),
                  borderRadius: BorderRadius.circular(20)),
              child: Column(children: [
                const CircleAvatar(
                    radius: 42,
                    backgroundColor: Colors.white24,
                    child: Icon(Icons.person, size: 48, color: Colors.white)),
                const SizedBox(height: 14),
                Text(branding.devName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(branding.devQuals,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ]),
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.phone),
                title: const Text('Phone'),
                subtitle: Text(branding.devPhone),
                trailing: Wrap(spacing: 4, children: [
                  IconButton(
                    icon: const Icon(Icons.call, color: Colors.green),
                    onPressed: () => launchUrl(Uri.parse('tel:${branding.devPhone}')),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chat, color: Colors.teal),
                    onPressed: () => launchUrl(
                        Uri.parse('https://wa.me/${digits(branding.devPhone)}'),
                        mode: LaunchMode.externalApplication),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(branding.aboutDev, style: const TextStyle(height: 1.4)),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text('${branding.appName} · ${branding.tagline}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}
