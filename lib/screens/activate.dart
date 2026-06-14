import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../pro.dart';
import '../theme.dart';
import '../widgets.dart';

/// Returns true if Pro is active. Otherwise shows an upsell and returns false.
Future<bool> requirePro(BuildContext context, String feature) async {
  if (pro.isPro) return true;
  final go = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Pro feature'),
      content: Text('$feature is a Pro feature. Activate Pro to unlock it.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not now')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Activate Pro')),
      ],
    ),
  );
  if (go == true && context.mounted) {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const ActivateScreen()));
  }
  return pro.isPro;
}

class ActivateScreen extends StatefulWidget {
  const ActivateScreen({super.key});
  @override
  State<ActivateScreen> createState() => _ActivateScreenState();
}

class _ActivateScreenState extends State<ActivateScreen> {
  final codeCtl = TextEditingController();
  bool busy = false;

  Future<void> _activate() async {
    setState(() => busy = true);
    try {
      await pro.activate(codeCtl.text);
      if (mounted) {
        snack(context, 'Pro activated \u2714');
        setState(() {});
      }
    } catch (e) {
      if (mounted) snack(context, e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: pro,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Wallet Pro')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: headerGradient(context),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(pro.isPro ? Icons.verified : Icons.workspace_premium,
                      color: Colors.white, size: 30),
                  const SizedBox(width: 10),
                  Text(pro.isPro ? 'Pro is active' : 'Free version',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                ]),
                if (pro.isPro) ...[
                  const SizedBox(height: 8),
                  Text('Tier: ${pro.tier.toUpperCase()}',
                      style: const TextStyle(color: Colors.white)),
                  Text('Valid until: ${pro.expiryLabel}',
                      style: const TextStyle(color: Colors.white70)),
                ],
              ]),
            ),
            const SizedBox(height: 20),
            Text('Your Device ID', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Card(
              child: ListTile(
                title: SelectableText(pro.deviceId,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 15)),
                trailing: IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: pro.deviceId));
                    snack(context, 'Device ID copied');
                  },
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                  'Send this Device ID to the seller. You will receive an activation code that works only on this device.',
                  style: TextStyle(fontSize: 12.5)),
            ),
            const SizedBox(height: 12),
            Text('Activation code', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            TextField(
              controller: codeCtl,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Paste your activation code here',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.key),
              label: Text(busy ? 'Checking...' : 'Activate'),
              onPressed: busy ? null : _activate,
              style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
            ),
            if (pro.isPro)
              TextButton(
                onPressed: () async {
                  await pro.deactivate();
                  if (mounted) setState(() {});
                },
                child: const Text('Remove activation from this device'),
              ),
          ],
        ),
      ),
    );
  }
}
