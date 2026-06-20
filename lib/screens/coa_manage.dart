import 'package:flutter/material.dart';
import '../db.dart';
import '../widgets.dart';

const _ungrouped = 'Ungrouped';

class CoaManageScreen extends StatefulWidget {
  const CoaManageScreen({super.key});
  @override
  State<CoaManageScreen> createState() => _CoaManageScreenState();
}

class _CoaManageScreenState extends State<CoaManageScreen> {
  List<Map<String, Object?>> incCats = [], expCats = [];
  Map<String, double> totals = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    incCats = await DB.categories(type: 'income');
    expCats = await DB.categories(type: 'expense');
    final t = <String, double>{};
    for (final r in await DB.catTotals('income', '1970-01-01', '2100-01-01')) {
      t['income:${r['n']}'] = (r['s'] as num? ?? 0).toDouble();
    }
    for (final r in await DB.catTotals('expense', '1970-01-01', '2100-01-01')) {
      t['expense:${r['n']}'] = (r['s'] as num? ?? 0).toDouble();
    }
    if (mounted) setState(() => totals = t);
  }

  Map<String, List<Map<String, Object?>>> _grouped(List<Map<String, Object?>> cats) {
    final m = <String, List<Map<String, Object?>>>{};
    for (final c in cats) {
      final g = (c['grp'] as String?)?.trim();
      m.putIfAbsent(g == null || g.isEmpty ? _ungrouped : g, () => []).add(c);
    }
    // keep Ungrouped last
    final keys = m.keys.where((k) => k != _ungrouped).toList()..sort();
    return {for (final k in keys) k: m[k]!, if (m.containsKey(_ungrouped)) _ungrouped: m[_ungrouped]!};
  }

  Future<void> _moveCat(Map<String, Object?> cat) async {
    final type = cat['type'] as String;
    final groups = await DB.catGroups(type);
    if (!mounted) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Move to group', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          for (final g in groups)
            ListTile(leading: const Icon(Icons.folder_outlined), title: Text(g), onTap: () => Navigator.pop(c, g)),
          ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('New group...'),
              onTap: () => Navigator.pop(c, '__new__')),
          ListTile(
              leading: const Icon(Icons.layers_clear_outlined),
              title: const Text('Ungrouped'),
              onTap: () => Navigator.pop(c, '__none__')),
        ]),
      ),
    );
    if (choice == null) return;
    String? grp;
    if (choice == '__none__') {
      grp = null;
    } else if (choice == '__new__') {
      grp = await _askName('New group name');
      if (grp == null || grp.isEmpty) return;
    } else {
      grp = choice;
    }
    await DB.setCatGroup(cat['id'] as int, grp);
    _load();
  }

  Future<String?> _askName(String title, {String initial = ''}) async {
    final ctl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _groupMenu(String type, String group) async {
    if (group == _ungrouped) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.edit), title: const Text('Rename group'), onTap: () => Navigator.pop(c, 'rename')),
          ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Delete group (keep categories)'), onTap: () => Navigator.pop(c, 'delete')),
        ]),
      ),
    );
    if (action == 'rename') {
      final name = await _askName('Rename group', initial: group);
      if (name != null && name.isNotEmpty) {
        await DB.renameCatGroup(type, group, name);
        _load();
      }
    } else if (action == 'delete') {
      await DB.clearCatGroup(type, group);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chart of Accounts')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
                'Organize your GL accounts (categories) into groups under each class. Tap a category to move it; long-press / tap a group to rename or delete. Changes apply instantly.',
                style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12.5)),
          ),
          _classSection('INCOME', 'income', incCats, Colors.green),
          _classSection('EXPENSES', 'expense', expCats, Colors.red),
        ],
      ),
    );
  }

  Widget _classSection(String label, String type, List<Map<String, Object?>> cats, Color color) {
    final grouped = _grouped(cats);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          leading: Icon(Icons.account_tree, color: color),
          title: Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
          children: [
            for (final entry in grouped.entries) _groupTile(type, entry.key, entry.value, color),
          ],
        ),
      ),
    );
  }

  Widget _groupTile(String type, String group, List<Map<String, Object?>> cats, Color color) {
    final groupTotal = cats.fold<double>(0, (s, c) => s + (totals['$type:${c['name']}'] ?? 0));
    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 4, bottom: 4),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 8),
        leading: Icon(group == _ungrouped ? Icons.folder_off_outlined : Icons.folder, size: 20, color: color.withOpacity(0.8)),
        title: GestureDetector(
          onLongPress: () => _groupMenu(type, group),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Flexible(child: Text(group, style: const TextStyle(fontWeight: FontWeight.w600))),
            Text(money(groupTotal), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
          ]),
        ),
        trailing: group == _ungrouped
            ? const Icon(Icons.expand_more)
            : IconButton(icon: const Icon(Icons.more_vert, size: 20), onPressed: () => _groupMenu(type, group)),
        children: [
          for (final c in cats)
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.only(left: 28, right: 12),
              leading: CircleAvatar(
                  radius: 13,
                  backgroundColor: Color((c['color'] as int?) ?? 0xFF9E9E9E),
                  child: Icon(iconOf(c['icon']), color: Colors.white, size: 13)),
              title: Text(c['name'] as String? ?? ''),
              trailing: Text(money(totals['$type:${c['name']}'] ?? 0),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
              onTap: () => _moveCat(c),
            ),
        ],
      ),
    );
  }
}
