import 'package:flutter/material.dart';
import '../db.dart';
import '../widgets.dart';
import 'accounts.dart';

class _Friend {
  final Map<String, Object?> account;
  bool selected;
  final shareCtl = TextEditingController();
  _Friend(this.account, {this.selected = false});
}

class SplitBillScreen extends StatefulWidget {
  const SplitBillScreen({super.key});
  @override
  State<SplitBillScreen> createState() => _SplitBillScreenState();
}

class _SplitBillScreenState extends State<SplitBillScreen> {
  List<Map<String, Object?>> accounts = [];
  List<Map<String, Object?>> cats = [];
  List<_Friend> friends = [];
  int? payAccountId;
  int? categoryId;
  String mode = 'equal';
  final totalCtl = TextEditingController();
  final noteCtl = TextEditingController();
  DateTime date = DateTime.now();
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    accounts = await DB.accounts();
    cats = await DB.categories(type: 'expense');
    friends = accounts
        .where((a) => groupOf(a) == 'people')
        .map((a) => _Friend(a))
        .toList();
    if (mounted) setState(() {});
  }

  double get total => double.tryParse(totalCtl.text.replaceAll(',', '').trim()) ?? 0;
  List<_Friend> get chosen => friends.where((f) => f.selected).toList();

  double _equalShare() {
    final n = chosen.length + 1; // +1 = me
    return n == 0 ? 0 : total / n;
  }

  double _friendShare(_Friend f) {
    if (mode == 'equal') return _equalShare();
    return double.tryParse(f.shareCtl.text.replaceAll(',', '').trim()) ?? 0;
  }

  double get friendsTotal => chosen.fold(0, (s, f) => s + _friendShare(f));
  double get myShare => total - friendsTotal;

  Future<void> _save() async {
    if (payAccountId == null) {
      snack(context, 'Choose the account you paid from');
      return;
    }
    if (total <= 0) {
      snack(context, 'Enter the total amount you paid');
      return;
    }
    if (chosen.isEmpty) {
      snack(context, 'Select at least one friend to split with');
      return;
    }
    if (friendsTotal > total + 0.01) {
      snack(context, "Friends' shares exceed the total");
      return;
    }
    setState(() => busy = true);
    final iso = date.toIso8601String();
    final note = noteCtl.text.trim();
    // My share -> expense from paying account
    if (myShare > 0.01) {
      await DB.insert('txns', {
        'type': 'expense',
        'amount': myShare,
        'accountId': payAccountId,
        'toAccountId': null,
        'categoryId': categoryId,
        'date': iso,
        'note': note.isEmpty ? 'My share' : note,
      });
    }
    // Each friend's share -> transfer from paying account to friend (they owe me)
    for (final f in chosen) {
      final share = _friendShare(f);
      if (share <= 0.01) continue;
      await DB.insert('txns', {
        'type': 'transfer',
        'amount': share,
        'accountId': payAccountId,
        'toAccountId': f.account['id'],
        'categoryId': null,
        'date': iso,
        'note': note.isEmpty ? 'Split bill share' : note,
      });
    }
    bus.ping();
    if (mounted) {
      snack(context, 'Recorded: my ${money(myShare)} + ${chosen.length} friend share(s)');
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Split a bill')),
      body: friends.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('You have no "people" accounts yet.', textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text('Add your friends as accounts (group: Lenders & Borrowers) first, then split bills with them.',
                      textAlign: TextAlign.center, style: TextStyle(color: cs.outline, fontSize: 13)),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const AccountEdit()))
                        .then((_) => _load()),
                    child: const Text('Add a person account'),
                  ),
                ]),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('You paid the whole bill. Record your own share as an expense and what each friend owes you.',
                    style: TextStyle(color: cs.outline, fontSize: 13)),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: totalCtl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                          labelText: 'Total you paid', prefixText: '$kCur ', border: const OutlineInputBorder()),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: payAccountId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Paid from', border: OutlineInputBorder()),
                  items: [
                    for (final a in accounts)
                      DropdownMenuItem(value: a['id'] as int, child: Text(a['name'] as String? ?? '')),
                  ],
                  onChanged: (v) => setState(() => payAccountId = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: categoryId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Category (for your share)', border: OutlineInputBorder()),
                  items: [
                    for (final c in cats)
                      DropdownMenuItem(value: c['id'] as int, child: Text(c['name'] as String? ?? '')),
                  ],
                  onChanged: (v) => setState(() => categoryId = v),
                ),
                const SizedBox(height: 16),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'equal', label: Text('Split equally')),
                    ButtonSegment(value: 'custom', label: Text('Custom amounts')),
                  ],
                  selected: {mode},
                  onSelectionChanged: (s) => setState(() => mode = s.first),
                ),
                const SizedBox(height: 12),
                Text('Split with', style: Theme.of(context).textTheme.titleSmall),
                for (final f in friends)
                  CheckboxListTile(
                    dense: true,
                    value: f.selected,
                    onChanged: (v) => setState(() => f.selected = v ?? false),
                    title: Text(f.account['name'] as String? ?? ''),
                    secondary: f.selected && mode == 'custom'
                        ? SizedBox(
                            width: 110,
                            child: TextField(
                              controller: f.shareCtl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              textAlign: TextAlign.right,
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(isDense: true, hintText: 'share'),
                            ),
                          )
                        : (f.selected
                            ? Text(money(_equalShare()), style: const TextStyle(fontWeight: FontWeight.bold))
                            : null),
                  ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(14)),
                  child: Column(children: [
                    _row('Total', total),
                    _row('Friends owe you', friendsTotal),
                    const Divider(),
                    _row('Your expense', myShare, bold: true),
                  ]),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: busy ? null : _save,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.all(15)),
                  child: Text(busy ? 'Saving...' : 'Record split'),
                ),
              ],
            ),
    );
  }

  Widget _row(String k, double v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(k, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          Text(money(v), style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.w600, fontSize: bold ? 16 : 14)),
        ]),
      );
}
