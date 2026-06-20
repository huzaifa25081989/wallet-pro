import 'package:flutter/material.dart';
import '../db.dart';
import '../widgets.dart';

const _ungrouped = 'Ungrouped';

class CoaManageScreen extends StatelessWidget {
  const CoaManageScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Chart of Accounts'),
          bottom: const TabBar(tabs: [
            Tab(text: 'EXPENSES', icon: Icon(Icons.south_west)),
            Tab(text: 'INCOME', icon: Icon(Icons.north_east)),
          ]),
        ),
        body: const TabBarView(children: [
          _ClassTab(type: 'expense', color: Colors.red),
          _ClassTab(type: 'income', color: Colors.green),
        ]),
      ),
    );
  }
}

class _ClassTab extends StatefulWidget {
  final String type;
  final Color color;
  const _ClassTab({required this.type, required this.color});
  @override
  State<_ClassTab> createState() => _ClassTabState();
}

class _ClassTabState extends State<_ClassTab> with AutomaticKeepAliveClientMixin {
  List<Map<String, Object?>> cats = [];
  List<String> groups = [];
  Map<String, double> totals = {};
  bool loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    cats = await DB.categories(type: widget.type);
    groups = await DB.catGroups(widget.type);
    final t = <String, double>{};
    for (final r in await DB.catTotals(widget.type, '1970-01-01', '2100-01-01')) {
      t['${r['n']}'] = (r['s'] as num? ?? 0).toDouble();
    }
    if (mounted) setState(() {
      totals = t;
      loading = false;
    });
  }

  // group -> list of categories
  Map<String, List<Map<String, Object?>>> get _byGroup {
    final m = <String, List<Map<String, Object?>>>{};
    for (final c in cats) {
      final g = (c['grp'] as String?)?.trim();
      m.putIfAbsent(g == null || g.isEmpty ? _ungrouped : g, () => []).add(c);
    }
    final keys = m.keys.where((k) => k != _ungrouped).toList()..sort();
    return {for (final k in keys) k: m[k]!, if (m.containsKey(_ungrouped)) _ungrouped: m[_ungrouped]!};
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

  Future<void> _changeGroup(Map<String, Object?> cat, String? choice) async {
    String? grp;
    if (choice == '__new__') {
      grp = await _askName('New group name');
      if (grp == null || grp.isEmpty) return;
    } else if (choice == _ungrouped || choice == null) {
      grp = null;
    } else {
      grp = choice;
    }
    await DB.setCatGroup(cat['id'] as int, grp);
    _load();
  }

  Future<void> _groupMenu(String group) async {
    final a = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.all(14), child: Text(group, style: const TextStyle(fontWeight: FontWeight.bold))),
          ListTile(leading: const Icon(Icons.edit), title: const Text('Rename group'), onTap: () => Navigator.pop(c, 'rename')),
          ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Delete group (keep categories)'), onTap: () => Navigator.pop(c, 'delete')),
        ]),
      ),
    );
    if (a == 'rename') {
      final n = await _askName('Rename group', initial: group);
      if (n != null && n.isNotEmpty) {
        await DB.renameCatGroup(widget.type, group, n);
        _load();
      }
    } else if (a == 'delete') {
      await DB.clearCatGroup(widget.type, group);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (loading) return const Center(child: CircularProgressIndicator());
    final cs = Theme.of(context).colorScheme;
    final grouped = _byGroup;
    return Column(
      children: [
        // toolbar
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Row(children: [
            Expanded(
              child: Text('Tap the Group dropdown on any category to move it.',
                  style: TextStyle(fontSize: 12.5, color: cs.outline)),
            ),
            TextButton.icon(
              onPressed: () async {
                final n = await _askName('New group name');
                if (n == null || n.isEmpty) return;
                // create the group by attaching it to the first ungrouped cat? No—just remember via a category.
                // groups exist only when a category uses them, so prompt to add one now:
                if (cats.isEmpty) return;
                await showModalBottomSheet(
                  context: context,
                  builder: (c) => SafeArea(
                    child: ListView(shrinkWrap: true, children: [
                      Padding(padding: const EdgeInsets.all(14), child: Text('Add a category to "$n"', style: const TextStyle(fontWeight: FontWeight.bold))),
                      for (final cat in cats)
                        ListTile(
                          leading: CircleAvatar(radius: 13, backgroundColor: Color((cat['color'] as int?) ?? 0xFF9E9E9E), child: Icon(iconOf(cat['icon']), size: 13, color: Colors.white)),
                          title: Text(cat['name'] as String? ?? ''),
                          onTap: () async {
                            await DB.setCatGroup(cat['id'] as int, n);
                            if (c.mounted) Navigator.pop(c);
                            _load();
                          },
                        ),
                    ]),
                  ),
                );
              },
              icon: const Icon(Icons.create_new_folder_outlined, size: 18),
              label: const Text('New group'),
            ),
          ]),
        ),
        // header row of the "table"
        Container(
          color: cs.surfaceVariant,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(children: [
            const Expanded(flex: 3, child: Text('CATEGORY (GL)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
            Expanded(flex: 2, child: Text('GROUP', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: cs.primary))),
          ]),
        ),
        Expanded(
          child: ListView(
            children: [
              for (final entry in grouped.entries) ...[
                _groupHeader(entry.key, entry.value),
                for (final c in entry.value) _catRow(c),
              ],
              const SizedBox(height: 30),
            ],
          ),
        ),
      ],
    );
  }

  Widget _groupHeader(String group, List<Map<String, Object?>> items) {
    final cs = Theme.of(context).colorScheme;
    final total = items.fold<double>(0, (s, c) => s + (totals[c['name']] ?? 0));
    return InkWell(
      onTap: group == _ungrouped ? null : () => _groupMenu(group),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        margin: const EdgeInsets.only(top: 6),
        color: widget.color.withOpacity(0.10),
        child: Row(children: [
          Icon(group == _ungrouped ? Icons.folder_off_outlined : Icons.folder, size: 18, color: widget.color),
          const SizedBox(width: 8),
          Expanded(child: Text(group, style: TextStyle(fontWeight: FontWeight.bold, color: widget.color))),
          Text(money(total), style: TextStyle(fontSize: 12, color: cs.outline)),
          if (group != _ungrouped) const Icon(Icons.more_vert, size: 16),
        ]),
      ),
    );
  }

  Widget _catRow(Map<String, Object?> c) {
    final current = ((c['grp'] as String?)?.trim().isNotEmpty == true) ? (c['grp'] as String).trim() : _ungrouped;
    final items = <String>{...groups, current, _ungrouped}.toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(children: [
        Expanded(
          flex: 3,
          child: Row(children: [
            CircleAvatar(radius: 13, backgroundColor: Color((c['color'] as int?) ?? 0xFF9E9E9E), child: Icon(iconOf(c['icon']), size: 13, color: Colors.white)),
            const SizedBox(width: 10),
            Expanded(child: Text(c['name'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
        ),
        Expanded(
          flex: 2,
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              isDense: true,
              value: current,
              style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
              items: [
                for (final g in items)
                  DropdownMenuItem(value: g, child: Text(g, overflow: TextOverflow.ellipsis)),
                const DropdownMenuItem(value: '__new__', child: Text('\u2795 New group\u2026', style: TextStyle(fontStyle: FontStyle.italic))),
              ],
              onChanged: (v) => _changeGroup(c, v),
            ),
          ),
        ),
      ]),
    );
  }
}
