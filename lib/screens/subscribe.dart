import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:intl/intl.dart';
import '../billing.dart';
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
  @override
  void initState() {
    super.initState();
    if (billing.available && billing.products.isEmpty) billing.refresh();
  }

  String _tag(String plan) => plan == '1Y' ? 'Popular' : (plan == '2Y' ? 'Best value' : '');

  Future<void> _buy(ProductDetails pd) async {
    try {
      await billing.buy(pd);
    } catch (e) {
      if (mounted) snack(context, 'Could not start purchase: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final content = AnimatedBuilder(
      animation: Listenable.merge([license, billing]),
      builder: (context, _) {
        if (widget.wall && license.isActive) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
          });
        }
        return ListView(
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
            if (!billing.available)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Subscriptions open in the Play Store version', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text('Install ProFinance from Google Play to subscribe securely. Your free trial works in any version.',
                        style: TextStyle(color: cs.outline)),
                  ]),
                ),
              )
            else if (billing.loading && billing.products.isEmpty)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            else if (billing.products.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Plans are not available right now. Try again shortly.${billing.error != null ? '\n\n(${billing.error})' : ''}',
                      style: TextStyle(color: cs.outline)),
                ),
              )
            else
              for (final pd in billing.products) _planCard(pd, cs),
            const SizedBox(height: 12),
            if (billing.available)
              Center(
                child: TextButton.icon(
                  onPressed: () => billing.restore(),
                  icon: const Icon(Icons.restore),
                  label: const Text('Restore my purchase'),
                ),
              ),
            const SizedBox(height: 10),
            Text(
              'Payment is handled securely by Google Play. Subscriptions renew automatically until cancelled; '
              'you can cancel anytime in the Play Store. A $kTrialDays-day free trial applies to new users.',
              style: TextStyle(fontSize: 12, color: cs.outline),
            ),
            const SizedBox(height: 40),
          ],
        );
      },
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Membership'), automaticallyImplyLeading: !widget.wall),
      body: widget.wall ? PopScope(canPop: false, child: content) : content,
    );
  }

  Widget _planCard(ProductDetails pd, ColorScheme cs) {
    final plan = kSubProductIds[pd.id] ?? '';
    final label = license.planLabel(plan);
    final tag = _tag(plan);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                if (tag.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Chip(
                    label: Text(tag, style: const TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: cs.tertiaryContainer,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ]),
              const SizedBox(height: 2),
              Text(pd.price, style: TextStyle(color: cs.outline)),
            ]),
          ),
          FilledButton(onPressed: () => _buy(pd), child: const Text('Subscribe')),
        ]),
      ),
    );
  }
}

/// Owner-only screen to generate offline activation codes (for sideloaded
/// installs / your own testing). Not part of the normal user flow.
class OwnerSignScreen extends StatefulWidget {
  const OwnerSignScreen({super.key});
  @override
  State<OwnerSignScreen> createState() => _OwnerSignScreenState();
}

class _OwnerSignScreenState extends State<OwnerSignScreen> {
  final seedCtl = TextEditingController();
  final appIdCtl = TextEditingController();
  final codeCtl = TextEditingController();
  String planCode = '1Y';
  String? result;

  Future<void> _gen() async {
    final pl = kPlans.firstWhere((p) => p.code == planCode);
    final code = await license.signLicense(seedCtl.text, appIdCtl.text, pl);
    setState(() => result = code ?? 'Could not sign (check the private seed)');
  }

  Future<void> _redeem() async {
    final err = await license.activate(codeCtl.text);
    if (!mounted) return;
    snack(context, err ?? 'Activated on this device');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Owner tools')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('This device\u2019s App ID: ${license.appId}'),
          const SizedBox(height: 16),
          const Text('Generate a code', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(controller: seedCtl, decoration: const InputDecoration(labelText: 'Private seed (keep secret)', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: appIdCtl, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Customer App ID', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: planCode,
            decoration: const InputDecoration(labelText: 'Plan', border: OutlineInputBorder()),
            items: [for (final p in kPlans) DropdownMenuItem(value: p.code, child: Text('${p.label} (\$${p.priceUsd})'))],
            onChanged: (v) => setState(() => planCode = v!),
          ),
          const SizedBox(height: 14),
          FilledButton(onPressed: _gen, child: const Text('Generate code')),
          if (result != null) ...[
            const SizedBox(height: 12),
            SelectableText(result!),
          ],
          const Divider(height: 36),
          const Text('Redeem a code on this device', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(controller: codeCtl, maxLines: 2, decoration: const InputDecoration(labelText: 'Activation code', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          FilledButton.tonal(onPressed: _redeem, child: const Text('Activate')),
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
