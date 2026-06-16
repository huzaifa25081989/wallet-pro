import 'package:flutter/material.dart';
import '../branding.dart';
import '../widgets.dart';

class AdminBrandingScreen extends StatefulWidget {
  const AdminBrandingScreen({super.key});
  @override
  State<AdminBrandingScreen> createState() => _AdminBrandingScreenState();
}

class _AdminBrandingScreenState extends State<AdminBrandingScreen> {
  late final appName = TextEditingController(text: branding.appName);
  late final tagline = TextEditingController(text: branding.tagline);
  late final currency = TextEditingController(text: branding.currency);
  late final devName = TextEditingController(text: branding.devName);
  late final devQuals = TextEditingController(text: branding.devQuals);
  late final devPhone = TextEditingController(text: branding.devPhone);
  late final aboutDev = TextEditingController(text: branding.aboutDev);

  Future<void> _save() async {
    await branding.save(
      appName: appName.text.trim(),
      tagline: tagline.text.trim(),
      currency: currency.text.trim().isEmpty ? 'Rs' : currency.text.trim(),
      devName: devName.text.trim(),
      devQuals: devQuals.text.trim(),
      devPhone: devPhone.text.trim(),
      aboutDev: aboutDev.text.trim(),
    );
    if (mounted) {
      snack(context, 'Saved \u2714');
      Navigator.pop(context);
    }
  }

  Widget _field(String label, TextEditingController c, {int lines = 1}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          maxLines: lines,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin · Branding & Content')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                  'Owner-only. Changes apply across the app on this device. The phone\'s launcher icon name is set at build time and is changed in the build, not here.',
                  style: TextStyle(fontSize: 12.5)),
            ),
          ),
          const SizedBox(height: 12),
          _field('App name (shown inside the app)', appName),
          _field('Tagline', tagline),
          _field('Currency symbol', currency),
          const Divider(),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Text('About Developer', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          _field('Developer name', devName),
          _field('Qualifications', devQuals, lines: 2),
          _field('Phone', devPhone),
          _field('About text', aboutDev, lines: 4),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
            child: const Text('Save changes'),
          ),
        ],
      ),
    );
  }
}
