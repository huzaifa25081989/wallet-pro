import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../db.dart';
import '../widgets.dart';
import 'txn_edit.dart';

const accountTypes = ['Bank', 'Cash', 'Savings', 'Investment', 'Credit'];

/// Full account list (opened from More tab).
class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});
  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  List<Map<String, Object?>> accounts = [];
  Map<int, double> bals = {};

  @override
  void initState() {
    super.initState();
    _load();
    bus.addListener(_load);
  }

  @override
  void dispose() {
    bus.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final a = await DB.all('accounts', orderBy: 'name');
    final b = await DB.balances();
    if (!mounted) return;
    setState(() {
      accounts = a;
      bals = b;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Accounts & Wallets')),
        floatingActionButton: FloatingActionButton(
          heroTag: 'accts_fab',
          onPressed: () =>
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountEdit())),
          child: const Icon(Icons.add),
        ),
        body: ListView(
          children: [
            for (final a in accounts)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Color((a['color'] as int?) ?? Colors.teal.value),
                  child: Icon(iconOf(a['icon']), color: Colors.white),
                ),
                title: Text(a['name'] as String? ?? ''),
                subtitle: Text(a['type'] as String? ?? ''),
                trailing: Text(money(bals[a['id']] ?? 0),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                onTap: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => AccountDetail(account: a))),
              ),
          ],
        ),
      );
}

/// Add or edit a single account.
class AccountEdit extends StatefulWidget {
  final Map<String, Object?>? account;
  const AccountEdit({super.key, this.account});
  @override
  State<AccountEdit> createState() => _AccountEditState();
}

class _AccountEditState extends State<AccountEdit> {
  final nameCtl = TextEditingController();
  final openCtl = TextEditingController(text: '0');
  String type = 'Bank';
  int icon = Icons.account_balance.codePoint;
  int color = Colors.teal.value;

  @override
  void initState() {
    super.initState();
    final a = widget.account;
    if (a != null) {
      nameCtl.text = a['name'] as String? ?? '';
      openCtl.text = '${(a['opening'] as num?) ?? 0}';
      type = a['type'] as String? ?? 'Bank';
      icon = (a['icon'] as int?) ?? icon;
      color = (a['color'] as int?) ?? color;
    }
  }

  Future<void> _save() async {
    if (nameCtl.text.trim().isEmpty) {
      snack(context, 'Enter an account name');
      return;
    }
    final m = <String, Object?>{
      'name': nameCtl.text.trim(),
      'type': type,
      'icon': icon,
      'color': color,
      'opening': double.tryParse(openCtl.text.replaceAll(',', '')) ?? 0,
    };
    if (widget.account == null) {
      await DB.insert('accounts', m);
    } else {
      m['id'] = widget.account!['id'];
      await DB.update('accounts', m);
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    if (!await confirm(context, 'Delete account?',
        'Records linked to this account will remain but the account will be removed. Continue?')) {
      return;
    }
    await DB.delete('accounts', widget.account!['id'] as int);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.account == null ? 'Add account' : 'Edit account'),
          actions: [
            if (widget.account != null)
              IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: nameCtl,
              decoration: const InputDecoration(
                  labelText: 'Account name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: type,
              decoration:
                  const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
              items: [
                for (final t in accountTypes) DropdownMenuItem(value: t, child: Text(t)),
              ],
              onChanged: (v) => setState(() => type = v ?? 'Bank'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: openCtl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Opening balance',
                  prefixText: '$kCur ',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: Card(
                  child: ListTile(
                    leading: Icon(iconOf(icon)),
                    title: const Text('Icon'),
                    onTap: () async {
                      final i = await pickIcon(context);
                      if (i != null) setState(() => icon = i.codePoint);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Card(
                  child: ListTile(
                    leading: CircleAvatar(backgroundColor: Color(color), radius: 12),
                    title: const Text('Color'),
                    onTap: () async {
                      final c = await pickColor(context, Color(color));
                      if (c != null) setState(() => color = c.value);
                    },
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
              child: const Text('Save account'),
            ),
          ],
        ),
      );
}

/// Per-account detail: balance, income/expense totals, full history.
class AccountDetail extends StatefulWidget {
  final Map<String, Object?> account;
  const AccountDetail({super.key, required this.account});
  @override
  State<AccountDetail> createState() => _AccountDetailState();
}

class _AccountDetailState extends State<AccountDetail> {
  List<Map<String, Object?>> txns = [];
  Map<int, Map<String, Object?>> cats = {}, accts = {};
  double balance = 0, incomeT = 0, expenseT = 0;

  @override
  void initState() {
    super.initState();
    _load();
    bus.addListener(_load);
  }

  @override
  void dispose() {
    bus.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final id = widget.account['id'] as int;
    final t = await DB.all('txns',
        where: 'accountId=? OR toAccountId=?', args: [id, id], orderBy: 'date DESC, id DESC');
    final c = await DB.all('cats');
    final a = await DB.all('accounts');
    final b = await DB.balances();
    double inc = 0, exp = 0;
    for (final r in t) {
      final amt = ((r['amount'] as num?) ?? 0).toDouble();
      final type = r['type'];
      if (type == 'income' && r['accountId'] == id) inc += amt;
      if (type == 'expense' && r['accountId'] == id) exp += amt;
      if (type == 'transfer' && r['toAccountId'] == id) inc += amt;
      if (type == 'transfer' && r['accountId'] == id) exp += amt;
    }
    if (!mounted) return;
    setState(() {
      txns = t;
      cats = {for (final x in c) x['id'] as int: x};
      accts = {for (final x in a) x['id'] as int: x};
      balance = b[id] ?? 0;
      incomeT = inc;
      expenseT = exp;
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    String? lastDay;
    for (final t in txns) {
      final day = (t['date'] as String? ?? '').length >= 10
          ? (t['date'] as String).substring(0, 10)
          : '';
      if (day != lastDay) {
        lastDay = day;
        items.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            day.isEmpty ? 'Unknown date' : DateFormat('EEE, d MMM yyyy').format(DateTime.parse(day)),
            style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.grey, fontSize: 12),
          ),
        ));
      }
      items.add(TxnTile(
        t: t,
        cats: cats,
        accts: accts,
        onTap: () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => TxnEdit(txn: t))),
      ));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.account['name'] as String? ?? 'Account'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => AccountEdit(account: widget.account))),
          ),
        ],
      ),
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text('Balance', style: Theme.of(context).textTheme.labelLarge),
                  Text(money(balance),
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Column(children: [
                        const Text('Money in', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        Text('+${money(incomeT)}',
                            style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600)),
                      ]),
                      Column(children: [
                        const Text('Money out', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        Text('\u2212${money(expenseT)}',
                            style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                      ]),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: txns.isEmpty
                ? const Center(child: Text('No records yet for this account'))
                : ListView(children: items),
          ),
        ],
      ),
    );
  }
}
