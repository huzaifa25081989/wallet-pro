import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../db.dart';
import '../theme.dart';
import '../widgets.dart';
import 'statement.dart';
import 'txn_edit.dart';

const accountTypes = ['Bank', 'Cash', 'Savings', 'Investment', 'Credit', 'Person', 'Wallet', 'Crypto', 'Gold', 'Property', 'Vehicle', 'Loan'];

/// Account groups shown as separate sections on the Home screen.
const accountGroups = ['main', 'people', 'investment'];
const groupLabels = {
  'main': 'Main Accounts',
  'people': 'Lenders & Borrowers',
  'investment': 'Investments',
};
String groupOf(Map<String, Object?> a) => (a['grp'] as String?) ?? 'main';

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
  final phoneCtl = TextEditingController();
  String type = 'Bank';
  String grp = 'main';
  int icon = Icons.account_balance.codePoint;
  int color = Colors.teal.value;

  @override
  void initState() {
    super.initState();
    final a = widget.account;
    if (a != null) {
      nameCtl.text = a['name'] as String? ?? '';
      openCtl.text = '${(a['opening'] as num?) ?? 0}';
      phoneCtl.text = a['phone'] as String? ?? '';
      type = a['type'] as String? ?? 'Bank';
      grp = a['grp'] as String? ?? 'main';
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
      'grp': grp,
      'phone': phoneCtl.text.trim(),
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
            DropdownButtonFormField<String>(
              value: grp,
              decoration: const InputDecoration(
                  labelText: 'Show under', border: OutlineInputBorder()),
              items: [
                for (final g in accountGroups)
                  DropdownMenuItem(value: g, child: Text(groupLabels[g]!)),
              ],
              onChanged: (v) => setState(() => grp = v ?? 'main'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: openCtl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                  labelText: 'Opening balance',
                  prefixText: '$kCur ',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneCtl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                  labelText: 'Phone for WhatsApp (optional)',
                  hintText: 'e.g. 03001234567',
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
  List<Map<String, Object?>> ledger = [];
  String filter = 'all';
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
    final l = await DB.accountLedger(id);
    double inc = 0, exp = 0;
    for (final r in l) {
      final d = (r['delta'] as num).toDouble();
      if (d >= 0) inc += d; else exp += -d;
    }
    final b = await DB.balances();
    if (!mounted) return;
    setState(() {
      ledger = l;
      balance = b[id] ?? 0;
      incomeT = inc;
      expenseT = exp;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rows = ledger.where((r) {
      switch (filter) {
        case 'income': return r['type'] == 'income';
        case 'expense': return r['type'] == 'expense';
        case 'transfer': return r['type'] == 'transfer';
        default: return true;
      }
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.account['name'] as String? ?? 'Account'),
        actions: [
          IconButton(
            icon: const Icon(Icons.description_outlined),
            tooltip: 'Statement',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StatementScreen(accountId: widget.account['id'] as int))),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => AccountEdit(account: widget.account))),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: headerGradient(context),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(children: [
              const Text('Current balance',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 4),
              Text(money(balance),
                  style: const TextStyle(
                      color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                Column(children: [
                  const Text('Money in', style: TextStyle(fontSize: 12, color: Colors.white70)),
                  Text('+${money(incomeT)}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ]),
                Column(children: [
                  const Text('Money out', style: TextStyle(fontSize: 12, color: Colors.white70)),
                  Text('\u2212${money(expenseT)}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ]),
              ]),
            ]),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              for (final f in const [
                ['all', 'All'], ['income', 'Income'],
                ['expense', 'Expense'], ['transfer', 'Transfers']
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(f[1]),
                    selected: filter == f[0],
                    onSelected: (_) => setState(() => filter = f[0]),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: rows.isEmpty
                ? const Center(child: Text('No records for this filter'))
                : ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 64),
                    itemBuilder: (_, i) {
                      final r = rows[i];
                      final delta = (r['delta'] as num).toDouble();
                      final running = (r['running'] as num).toDouble();
                      final up = delta >= 0;
                      final date = DateTime.tryParse(r['date'] as String? ?? '');
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              Color((r['catColor'] as int?) ?? cs.primary.value),
                          child: Icon(
                              r['type'] == 'transfer'
                                  ? Icons.swap_horiz
                                  : iconOf(r['catIcon']),
                              color: Colors.white, size: 20),
                        ),
                        title: Text(r['label'] as String? ?? '',
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          '${date != null ? DateFormat('d MMM yyyy').format(date) : ''}'
                          '${(r['note'] as String?)?.isNotEmpty == true ? ' \u00b7 ${r['note']}' : ''}',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('${up ? '+' : '\u2212'}${money(delta.abs())}',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: up ? Colors.green : Colors.red)),
                            Text('Bal ${money(running)}',
                                style: TextStyle(fontSize: 11, color: cs.outline)),
                          ],
                        ),
                        onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => TxnEdit(txn: r))),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
