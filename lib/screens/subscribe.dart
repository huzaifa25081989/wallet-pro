import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../license.dart';
import '../theme.dart';
import '../widgets.dart';

class SubscribeScreen extends StatefulWidget {
  final bool wall;
  const SubscribeScreen({super.key, this.wall = false});
  @override
  State<SubscribeScreen> createState() => _SubscribeScreenState();
}

class _SubscribeScreenState extends State<SubscribeScreen> {
  final codeCtl = TextEditingController();
  String selected = '1Y';
  bool working = false;

  Plan get _plan => kPlans.firstWhere((p) => p.code == selected);

  Future<void> _emailOwner() async {
    final p = _plan;
    final subject = Uri.encodeComponent('ProFinance subscription - ${p.label}');
    final body = Uri.encodeComponent(
        'Hi, I would like to subscribe to ProFinance.\n\n'
        'Plan: ${p.label} (\$${p.priceUsd})\n'
        'My App ID: ${license.appId}\n\n'
        'I have sent the payment. Please send my activation code. Thank you.');
    final uri = Uri.parse('mailto:$kOwnerEmail?subject=$subject&body=$body');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) snack(context, 'No email app found. Email $kOwnerEmail');
    }
  }

  Future<void> _activate() async {
    setState(() => working = true);
    final err = await license.activate(codeCtl.text);
    setState(() => working = false);
    if (!mounted) return;
    if (err == null) {
      snack(context, 'Activated! Premium until ${DateFormat('d MMM yyyy').format(license.premiumExpiryDate)}');
      if (widget.wall && Navigator.of(context).canPop()) Navigator.of(context).pop();
    } else {
      snack(context, err);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final body = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(gradient: headerGradient(context), borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.workspace_premium, color: Colors.white),
              const SizedBox(width: 8),
              Text(license.isPremium ? 'Premium active' : (license.isTrial ? 'Free trial' : 'Trial ended'),
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 6),
            Text(
              license.isPremium
                  ? '${license.planLabel(license.plan)} \u00b7 ${license.premiumDaysLeft} days left (until ${DateFormat('d MMM yyyy').format(license.premiumExpiryDate)})'
                  : license.isTrial
                      ? '${license.trialDaysLeft} days left in your free trial'
                      : 'Your free trial is over. Subscribe to keep using ProFinance.',
              style: const TextStyle(color: Colors.white70),
            ),
          ]),
        ),
        const SizedBox(height: 18),
        Text('Choose a plan', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final p in kPlans)
          Card(
            color: selected == p.code ? cs.primaryContainer : null,
            child: RadioListTile<String>(
              value: p.code,
              groupValue: selected,
              onChanged: (v) => setState(() => selected = v!),
              title: Text(p.label, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('\$${p.priceUsd}  \u00b7  ${(p.priceUsd / (p.days / 30)).toStringAsFixed(1)}\$/month'),
              secondary: p.code == '1Y'
                  ? Chip(label: const Text('Popular'), backgroundColor: cs.tertiaryContainer)
                  : (p.code == '2Y' ? const Chip(label: Text('Best value')) : null),
            ),
          ),
        const SizedBox(height: 10),
        // App ID
        Card(
          child: ListTile(
            leading: const Icon(Icons.fingerprint),
            title: const Text('Your App ID'),
            subtitle: Text(license.appId, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2)),
            trailing: IconButton(
              icon: const Icon(Icons.copy),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: license.appId));
                snack(context, 'App ID copied');
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _emailOwner,
          icon: const Icon(Icons.email_outlined),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          label: Text('I paid \u2014 email my App ID for ${_plan.label}'),
        ),
        const SizedBox(height: 8),
        Text(
          'How it works: pick a plan, send the payment to the owner, then tap the button above to email your App ID. '
          'You will receive an activation code that only works on this device. Paste it below.',
          style: TextStyle(fontSize: 12.5, color: cs.outline),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: codeCtl,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Activation code',
            hintText: 'Paste the code you received',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.vpn_key_outlined),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: working ? null : _activate,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: working ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Activate'),
        ),
        const SizedBox(height: 40),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Membership'),
        automaticallyImplyLeading: !widget.wall,
      ),
      body: widget.wall ? PopScope(canPop: false, child: body) : body,
    );
  }
}

/// Owner-only screen to generate activation codes (needs the private seed).
class OwnerSignScreen extends StatefulWidget {
  const OwnerSignScreen({super.key});
  @override
  State<OwnerSignScreen> createState() => _OwnerSignScreenState();
}

class _OwnerSignScreenState extends State<OwnerSignScreen> {
  final seedCtl = TextEditingController();
  final appIdCtl = TextEditingController();
  String planCode = '1Y';
  String? result;

  Future<void> _gen() async {
    final pl = kPlans.firstWhere((p) => p.code == planCode);
    final code = await license.signLicense(seedCtl.text, appIdCtl.text, pl);
    setState(() => result = code ?? 'Could not sign (check the private seed)');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Generate license (owner)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Only you can use this. Paste your private seed, the customer\u2019s App ID, pick the plan they paid for, and share the generated code.'),
          const SizedBox(height: 14),
          TextField(
            controller: seedCtl,
            decoration: const InputDecoration(labelText: 'Private seed (keep secret)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: appIdCtl,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Customer App ID', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: planCode,
            decoration: const InputDecoration(labelText: 'Plan', border: OutlineInputBorder()),
            items: [for (final p in kPlans) DropdownMenuItem(value: p.code, child: Text('${p.label} (\$${p.priceUsd})'))],
            onChanged: (v) => setState(() => planCode = v!),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _gen, style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)), child: const Text('Generate code')),
          if (result != null) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Activation code', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  SelectableText(result!),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: result!));
                        snack(context, 'Code copied');
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy'),
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}


/// Blocks the app with the subscribe screen once the free trial ends.
class LicenseGate extends StatelessWidget {
  final Widget child;
  const LicenseGate({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: license,
      builder: (_, __) => license.isActive ? child : const SubscribeScreen(wall: true),
    );
  }
}
