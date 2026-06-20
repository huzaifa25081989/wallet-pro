import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../lock.dart';
import '../widgets.dart';

/// Ask for the PIN before a protected delete. Returns true if allowed.
Future<bool> requirePinForDelete(BuildContext context) async {
  if (!(lock.lockDelete && lock.hasPin)) return true;
  final ctl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Enter PIN to delete'),
      content: TextField(
        controller: ctl,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(labelText: 'PIN', border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, lock.verify(ctl.text)), child: const Text('Confirm')),
      ],
    ),
  );
  if (ok == false) {
    if (context.mounted) snack(context, 'Wrong PIN — delete cancelled');
  }
  return ok ?? false;
}

/// Full-screen lock shown on app open when enabled.
class LockGate extends StatefulWidget {
  final Widget child;
  const LockGate({super.key, required this.child});
  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> {
  final ctl = TextEditingController();
  String? error;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: lock,
      builder: (context, _) {
        if (!lock.needsUnlock) return widget.child;
        final cs = Theme.of(context).colorScheme;
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.lock, size: 64, color: cs.primary),
                const SizedBox(height: 16),
                const Text('Enter your PIN', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                TextField(
                  controller: ctl,
                  autofocus: true,
                  obscureText: true,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(fontSize: 24, letterSpacing: 8),
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    errorText: error,
                  ),
                  onChanged: (_) => setState(() => error = null),
                  onSubmitted: (_) => _try(),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _try,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14)),
                  child: const Text('Unlock'),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }

  void _try() {
    if (!lock.verify(ctl.text)) {
      setState(() => error = 'Wrong PIN');
    } else {
      ctl.clear();
    }
  }
}

class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});
  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: lock,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('Password & security')),
          body: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              ListTile(
                leading: Icon(lock.hasPin ? Icons.lock : Icons.lock_open,
                    color: lock.hasPin ? Colors.green : null),
                title: Text(lock.hasPin ? 'PIN is set' : 'Set a PIN'),
                subtitle: Text(lock.hasPin ? 'Tap to change or remove' : 'Protect the app with a numeric PIN'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _setPin,
              ),
              const Divider(),
              SwitchListTile(
                secondary: const Icon(Icons.phonelink_lock),
                title: const Text('Lock app on open'),
                subtitle: const Text('Ask for the PIN every time the app starts'),
                value: lock.lockOnOpen,
                onChanged: lock.hasPin ? (v) => lock.setLockOnOpen(v) : null,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.delete_forever),
                title: const Text('Require PIN to delete'),
                subtitle: const Text('Ask for the PIN before deleting any account or record'),
                value: lock.lockDelete,
                onChanged: lock.hasPin ? (v) => lock.setLockDelete(v) : null,
              ),
              if (!lock.hasPin)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Set a PIN first to turn on these protections.',
                      style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _setPin() async {
    final ctl = TextEditingController();
    final ctl2 = TextEditingController();
    final res = await showDialog<String?>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(lock.hasPin ? 'Change / remove PIN' : 'Set a PIN'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: ctl,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'New PIN (4-8 digits)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: ctl2,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Confirm PIN', border: OutlineInputBorder()),
          ),
          if (lock.hasPin)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Leave blank and tap Remove to turn off the PIN.', style: TextStyle(fontSize: 11)),
            ),
        ]),
        actions: [
          if (lock.hasPin)
            TextButton(onPressed: () => Navigator.pop(c, ''), child: const Text('Remove')),
          TextButton(onPressed: () => Navigator.pop(c, null), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (ctl.text.length < 4) {
                Navigator.pop(c, '__short__');
              } else if (ctl.text != ctl2.text) {
                Navigator.pop(c, '__mismatch__');
              } else {
                Navigator.pop(c, ctl.text);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (res == null) return;
    if (res == '__short__') {
      if (mounted) snack(context, 'PIN must be at least 4 digits');
      return;
    }
    if (res == '__mismatch__') {
      if (mounted) snack(context, 'PINs do not match');
      return;
    }
    await lock.setPin(res.isEmpty ? null : res);
    if (mounted) snack(context, res.isEmpty ? 'PIN removed' : 'PIN saved');
  }
}
