import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../cloud.dart';
import '../widgets.dart';

class CloudScreen extends StatefulWidget {
  const CloudScreen({super.key});
  @override
  State<CloudScreen> createState() => _CloudScreenState();
}

class _CloudScreenState extends State<CloudScreen> {
  final emailCtl = TextEditingController();
  final passCtl = TextEditingController();
  bool busy = false;
  bool obscure = true;

  Future<void> _run(Future<String?> Function() action, {String? ok}) async {
    setState(() => busy = true);
    final err = await action();
    if (!mounted) return;
    setState(() => busy = false);
    if (err != null) {
      snack(context, err);
    } else if (ok != null) {
      snack(context, ok);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: cloud,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        return Scaffold(
          appBar: AppBar(title: const Text('Cloud backup')),
          body: !cloud.ready
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                        'Cloud backup is unavailable right now.\n\n${cloud.error ?? 'Check your internet connection and reopen the app.'}',
                        textAlign: TextAlign.center),
                  ),
                )
              : cloud.signedIn
                  ? _signedIn(context, cs)
                  : _signedOut(context, cs),
        );
      },
    );
  }

  Widget _signedIn(BuildContext context, ColorScheme cs) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF11998E), Color(0xFF38EF7D)]),
              borderRadius: BorderRadius.circular(18)),
          child: Row(children: [
            const Icon(Icons.cloud_done, color: Colors.white, size: 36),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Backed up to the cloud',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 2),
                Text(cloud.email ?? '', style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        ListTile(
          leading: const Icon(Icons.sync),
          title: const Text('Auto sync'),
          subtitle: const Text('Save to the cloud automatically after every change'),
          trailing: Switch(value: cloud.autoSync, onChanged: (v) => cloud.setAuto(v)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            cloud.lastSynced != null
                ? 'Last synced: ${DateFormat('d MMM, h:mm a').format(cloud.lastSynced!)}'
                : 'Not synced yet this session',
            style: TextStyle(color: cs.outline, fontSize: 12),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          icon: const Icon(Icons.cloud_upload),
          label: Text(busy ? 'Working...' : 'Back up now'),
          onPressed: busy ? null : () => _run(() async => (await cloud.backup()) ? null : (cloud.error ?? 'Backup failed'), ok: 'Backed up \u2714'),
          style: FilledButton.styleFrom(padding: const EdgeInsets.all(14)),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          icon: const Icon(Icons.cloud_download),
          label: const Text('Restore from cloud'),
          onPressed: busy
              ? null
              : () async {
                  final go = await confirm(context, 'Restore from cloud?',
                      'This REPLACES the data on this phone with your cloud backup. Use this on a new phone or after reinstalling.');
                  if (go) _run(cloud.restore, ok: 'Restored from cloud \u2714');
                },
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(14)),
        ),
        const SizedBox(height: 24),
        TextButton.icon(
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
          onPressed: busy ? null : () => cloud.signOut(),
        ),
      ],
    );
  }

  Widget _signedOut(BuildContext context, ColorScheme cs) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Keep your data safe',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(
            'Create a free account with your email. Your transactions back up automatically, and you can sign in on any phone to get everything back.',
            style: TextStyle(color: cs.outline)),
        const SizedBox(height: 20),
        TextField(
          controller: emailCtl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
              labelText: 'Email', prefixIcon: Icon(Icons.email_outlined), border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: passCtl,
          obscureText: obscure,
          decoration: InputDecoration(
            labelText: 'Password (6+ characters)',
            prefixIcon: const Icon(Icons.lock_outline),
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => obscure = !obscure),
            ),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: busy
              ? null
              : () => _run(() => cloud.signUp(emailCtl.text, passCtl.text), ok: 'Account created \u2014 syncing on'),
          style: FilledButton.styleFrom(padding: const EdgeInsets.all(15)),
          child: Text(busy ? 'Please wait...' : 'Create account'),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: busy
              ? null
              : () => _run(() => cloud.signIn(emailCtl.text, passCtl.text), ok: 'Signed in \u2714'),
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(15)),
          child: const Text('I already have an account — Sign in'),
        ),
        const SizedBox(height: 16),
        Text('Your data is private to your account. We never see your password.',
            style: TextStyle(color: cs.outline, fontSize: 12), textAlign: TextAlign.center),
      ],
    );
  }
}
