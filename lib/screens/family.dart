import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../cloud.dart';
import '../db.dart';
import '../family.dart';
import '../widgets.dart';
import 'cloud.dart';

class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key});
  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  String? code;
  List<Map<String, Object?>> peers = [];
  List<Map<String, Object?>> links = [];
  List<Map<String, Object?>> inbox = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!family.available) {
      setState(() => loading = false);
      return;
    }
    setState(() => loading = true);
    try {
      code = await family.ensureCode();
      peers = await family.incomingPeers();
      links = await family.myLinks();
      inbox = await family.inbox();
    } catch (e) {
      if (mounted) snack(context, 'Family sync error: $e');
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (!family.available) {
      return Scaffold(
        appBar: AppBar(title: const Text('Family Connect')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.family_restroom, size: 64),
              const SizedBox(height: 16),
              const Text('Family Connect needs a cloud account',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text('Sign in to cloud backup first, then you can connect with family.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const CloudScreen()))
                    .then((_) => _load()),
                child: const Text('Go to Cloud backup'),
              ),
            ]),
          ),
        ),
      );
    }
    final pendingPeers = peers.where((p) => p['status'] == 'pending').toList();
    final approvedPeers = peers.where((p) => p['status'] == 'approved').toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Family Connect')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _billDialog,
        icon: const Icon(Icons.receipt_long),
        label: const Text('Bill to family'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
                children: [
                  // my code
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                        gradient: headerGradient(context), borderRadius: BorderRadius.circular(16)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Your family code', style: TextStyle(color: Colors.white70)),
                      const SizedBox(height: 6),
                      Row(children: [
                        Text(code ?? '------',
                            style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold, letterSpacing: 4)),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.copy, color: Colors.white),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: code ?? ''));
                            snack(context, 'Code copied');
                          },
                        ),
                      ]),
                      const Text('Share this with family so they can connect and see your records (after you approve).',
                          style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.person_add_alt),
                    label: const Text('Connect to family by code'),
                    onPressed: _connectDialog,
                  ),

                  if (inbox.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    _header('Approvals needed (${inbox.length})'),
                    for (final it in inbox) _inboxTile(it),
                  ],

                  if (pendingPeers.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    _header('Wants to see your records'),
                    for (final p in pendingPeers) _peerRequestTile(p),
                  ],

                  if (approvedPeers.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    _header('Can see your records'),
                    for (final p in approvedPeers)
                      ListTile(
                        leading: const Icon(Icons.visibility),
                        title: Text(p['name'] as String? ?? p['email'] as String? ?? ''),
                        subtitle: Text(p['email'] as String? ?? ''),
                        trailing: IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () async {
                            await family.removePeer(p['uid'] as String);
                            _load();
                          },
                        ),
                      ),
                  ],

                  const SizedBox(height: 18),
                  _header('Family you follow'),
                  if (links.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text('Connect with a code above to follow a family member.',
                          style: TextStyle(color: cs.outline, fontSize: 13)),
                    ),
                  for (final l in links)
                    ListTile(
                      leading: Icon((l['approved'] == true) ? Icons.people : Icons.hourglass_top,
                          color: (l['approved'] == true) ? Colors.green : Colors.orange),
                      title: Text(l['name'] as String? ?? ''),
                      subtitle: Text((l['approved'] == true) ? 'Approved \u00b7 tap to view' : 'Waiting for approval'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: (l['approved'] == true)
                          ? () => Navigator.push(context, MaterialPageRoute(
                              builder: (_) => FamilyViewScreen(ownerUid: l['uid'] as String, name: l['name'] as String? ?? '')))
                          : null,
                    ),
                ],
              ),
            ),
    );
  }

  Widget _header(String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(t, style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _peerRequestTile(Map<String, Object?> p) => Card(
        child: ListTile(
          leading: const Icon(Icons.person_outline),
          title: Text(p['name'] as String? ?? p['email'] as String? ?? ''),
          subtitle: Text(p['email'] as String? ?? ''),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              icon: const Icon(Icons.check_circle, color: Colors.green),
              onPressed: () async {
                await family.approvePeer(p['uid'] as String);
                _load();
              },
            ),
            IconButton(
              icon: const Icon(Icons.cancel, color: Colors.red),
              onPressed: () async {
                await family.removePeer(p['uid'] as String);
                _load();
              },
            ),
          ]),
        ),
      );

  Widget _inboxTile(Map<String, Object?> it) {
    final amt = (it['amount'] as num?)?.toDouble() ?? 0;
    final from = it['fromEmail'] as String? ?? 'family';
    return Card(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$from billed you ${money(amt)}', style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('${it['category'] ?? ''}  ${(it['note'] as String?)?.isNotEmpty == true ? '· ${it['note']}' : ''}'),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(
              onPressed: () async {
                await family.declineInbox(it['id'] as String);
                _load();
              },
              child: const Text('Decline'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () async {
                final name = await _askName('Record under which name?', initial: (from.split('@').first));
                if (name == null || name.isEmpty) return;
                await family.approveInbox(it, name);
                snack(context, 'Recorded as expense + payable to $name');
                _load();
              },
              child: const Text('Approve & record'),
            ),
          ]),
        ]),
      ),
    );
  }

  Future<String?> _askName(String title, {String initial = ''}) {
    final ctl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctl, autofocus: true, decoration: const InputDecoration(border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _connectDialog() async {
    final codeCtl = TextEditingController();
    final nameCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Connect to family'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: codeCtl,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Their family code', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: nameCtl,
            decoration: const InputDecoration(labelText: 'Name for them (e.g. Wife)', border: OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Request')),
        ],
      ),
    );
    if (ok != true) return;
    final err = await family.connect(codeCtl.text, nameCtl.text.trim().isEmpty ? codeCtl.text : nameCtl.text.trim());
    if (!mounted) return;
    snack(context, err ?? 'Request sent \u2014 ask them to approve you');
    _load();
  }

  Future<void> _billDialog() async {
    final targets = <Map<String, Object?>>[];
    for (final l in links) {
      targets.add({'uid': l['uid'], 'name': l['name']});
    }
    for (final p in peers.where((p) => p['status'] == 'approved')) {
      if (!targets.any((t) => t['uid'] == p['uid'])) {
        targets.add({'uid': p['uid'], 'name': p['name'] ?? p['email']});
      }
    }
    if (targets.isEmpty) {
      snack(context, 'Connect with a family member first');
      return;
    }
    final accounts = await DB.accounts();
    final cats = await DB.categories(type: 'expense');
    if (!mounted) return;
    Map<String, Object?>? target = targets.first;
    int? payId = accounts.isNotEmpty ? accounts.first['id'] as int : null;
    int? catId;
    final amtCtl = TextEditingController();
    final noteCtl = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
        child: StatefulBuilder(
          builder: (c, setSheet) => Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Bill an expense to family', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              DropdownButtonFormField<Map<String, Object?>>(
                value: target,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Family member', border: OutlineInputBorder()),
                items: [for (final t in targets) DropdownMenuItem(value: t, child: Text(t['name'] as String? ?? ''))],
                onChanged: (v) => setSheet(() => target = v),
              ),
              const SizedBox(height: 10),
              TextField(controller: amtCtl, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: 'Amount', prefixText: '$kCur ', border: const OutlineInputBorder())),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                value: payId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'You paid from', border: OutlineInputBorder()),
                items: [for (final a in accounts) DropdownMenuItem(value: a['id'] as int, child: Text(a['name'] as String? ?? ''))],
                onChanged: (v) => setSheet(() => payId = v),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                value: catId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
                items: [for (final c2 in cats) DropdownMenuItem(value: c2['id'] as int, child: Text(c2['name'] as String? ?? ''))],
                onChanged: (v) => setSheet(() => catId = v),
              ),
              const SizedBox(height: 10),
              TextField(controller: noteCtl, decoration: const InputDecoration(labelText: 'Note', border: OutlineInputBorder())),
              const SizedBox(height: 14),
              FilledButton(
                style: FilledButton.styleFrom(padding: const EdgeInsets.all(14), minimumSize: const Size.fromHeight(48)),
                onPressed: () async {
                  final amt = double.tryParse(amtCtl.text.replaceAll(',', '').trim()) ?? 0;
                  if (amt <= 0 || payId == null || target == null) {
                    snack(context, 'Enter amount, account and member');
                    return;
                  }
                  final catName = catId == null ? 'Other Expense'
                      : (cats.firstWhere((e) => e['id'] == catId)['name'] as String);
                  await family.billExpense(
                    toUid: target!['uid'] as String,
                    toName: target!['name'] as String,
                    amount: amt,
                    category: catName,
                    note: noteCtl.text.trim(),
                    date: DateTime.now(),
                    payAccountId: payId!,
                  );
                  if (c.mounted) Navigator.pop(c);
                  if (mounted) {
                    snack(context, 'Sent to ${target!['name']} \u00b7 recorded as receivable on your side');
                    _load();
                  }
                },
                child: const Text('Send & record'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Read-only snapshot of a family member's accounts and recent records.
class FamilyViewScreen extends StatefulWidget {
  final String ownerUid;
  final String name;
  const FamilyViewScreen({super.key, required this.ownerUid, required this.name});
  @override
  State<FamilyViewScreen> createState() => _FamilyViewScreenState();
}

class _FamilyViewScreenState extends State<FamilyViewScreen> {
  Map<String, Object?>? data;
  String? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      data = await family.peerData(widget.ownerUid);
      if (data == null) error = 'No shared data yet (they may not have synced).';
    } catch (e) {
      error = '$e';
    }
    if (mounted) setState(() => loading = false);
  }

  List _rows(String table) => (data?[table] as List?) ?? [];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accounts = _rows('accounts');
    final txns = _rows('txns');
    // compute balances
    final bal = <int, double>{
      for (final a in accounts) a['id'] as int: ((a['opening'] as num?) ?? 0).toDouble()
    };
    for (final t in txns) {
      final amt = ((t['amount'] as num?) ?? 0).toDouble();
      final type = t['type'];
      final acc = t['accountId'] as int?;
      final to = t['toAccountId'] as int?;
      if (type == 'income' && acc != null) bal[acc] = (bal[acc] ?? 0) + amt;
      if (type == 'expense' && acc != null) bal[acc] = (bal[acc] ?? 0) - amt;
      if (type == 'transfer') {
        if (acc != null) bal[acc] = (bal[acc] ?? 0) - amt;
        if (to != null) bal[to] = (bal[to] ?? 0) + amt;
      }
    }
    final recent = [...txns]
      ..sort((a, b) => ('${b['date']}').compareTo('${a['date']}'));
    final cats = {for (final c in _rows('cats')) c['id'] as int: c};
    final accNames = {for (final a in accounts) a['id'] as int: a['name']};

    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(error!, textAlign: TextAlign.center)))
              : ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    Text('Accounts', style: Theme.of(context).textTheme.titleMedium),
                    for (final a in accounts)
                      ListTile(
                        dense: true,
                        leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: Color((a['color'] as int?) ?? 0xFF607D8B),
                            child: Icon(iconOf(a['icon']), color: Colors.white, size: 16)),
                        title: Text(a['name'] as String? ?? ''),
                        trailing: Text(money(bal[a['id']] ?? 0), style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    const Divider(),
                    Text('Recent records', style: Theme.of(context).textTheme.titleMedium),
                    for (final t in recent.take(20))
                      ListTile(
                        dense: true,
                        title: Text((t['note'] as String?)?.isNotEmpty == true
                            ? t['note'] as String
                            : (cats[t['categoryId']]?['name'] as String? ?? t['type'] as String? ?? '')),
                        subtitle: Text([
                          if (t['date'] != null) DateFormat('d MMM').format(DateTime.tryParse('${t['date']}') ?? DateTime(2000)),
                          accNames[t['accountId']] ?? '',
                        ].where((e) => '$e'.isNotEmpty).join(' · ')),
                        trailing: Text(
                          '${t['type'] == 'income' ? '+' : t['type'] == 'expense' ? '-' : ''}${money(((t['amount'] as num?) ?? 0).toDouble())}',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: t['type'] == 'income' ? Colors.green : t['type'] == 'expense' ? Colors.red : null),
                        ),
                      ),
                  ],
                ),
    );
  }
}
