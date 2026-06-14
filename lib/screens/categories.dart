import 'package:flutter/material.dart';
import '../db.dart';
import '../widgets.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});
  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  String typeF = 'all';
  List<Map<String, Object?>> cats = [];

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
    final c = await DB.all('cats', orderBy: 'type, name');
    if (!mounted) return;
    setState(() => cats = c);
  }

  @override
  Widget build(BuildContext context) {
    final filtered =
        cats.where((c) => typeF == 'all' || c['type'] == typeF).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: FloatingActionButton(
        heroTag: 'cats_fab',
        onPressed: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const CatEdit())),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final f in const [
                  ['all', 'All'],
                  ['expense', 'Expense'],
                  ['income', 'Income'],
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(f[1]),
                      selected: typeF == f[0],
                      onSelected: (_) => setState(() => typeF = f[0]),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final c in filtered)
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          Color((c['color'] as int?) ?? Colors.grey.value),
                      child: Icon(iconOf(c['icon']), color: Colors.white, size: 20),
                    ),
                    title: Text(c['name'] as String? ?? ''),
                    subtitle: Text(
                        c['type'] == 'income' ? 'Income' : 'Expense',
                        style: TextStyle(
                            color: c['type'] == 'income'
                                ? Colors.green
                                : Colors.red,
                            fontSize: 12)),
                    trailing: const Icon(Icons.edit_outlined, size: 18),
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => CatEdit(cat: c))),
                  ),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CatEdit extends StatefulWidget {
  final Map<String, Object?>? cat;
  const CatEdit({super.key, this.cat});
  @override
  State<CatEdit> createState() => _CatEditState();
}

class _CatEditState extends State<CatEdit> {
  final nameCtl = TextEditingController();
  String type = 'expense';
  int icon = Icons.category.codePoint;
  int color = Colors.blueGrey.value;

  @override
  void initState() {
    super.initState();
    final c = widget.cat;
    if (c != null) {
      nameCtl.text = c['name'] as String? ?? '';
      type = c['type'] as String? ?? 'expense';
      icon = (c['icon'] as int?) ?? icon;
      color = (c['color'] as int?) ?? color;
    }
  }

  Future<void> _save() async {
    if (nameCtl.text.trim().isEmpty) {
      snack(context, 'Enter a category name');
      return;
    }
    final m = <String, Object?>{
      'name': nameCtl.text.trim(),
      'type': type,
      'icon': icon,
      'color': color,
    };
    if (widget.cat == null) {
      await DB.insert('cats', m);
    } else {
      m['id'] = widget.cat!['id'];
      await DB.update('cats', m);
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    if (!await confirm(context, 'Delete category?',
        'Records using it will show as Uncategorized. Continue?')) {
      return;
    }
    await DB.delete('cats', widget.cat!['id'] as int);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.cat == null ? 'Add category' : 'Edit category'),
          actions: [
            if (widget.cat != null)
              IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: nameCtl,
              decoration: const InputDecoration(
                  labelText: 'Category name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'expense', label: Text('Expense')),
                ButtonSegment(value: 'income', label: Text('Income')),
              ],
              selected: {type},
              onSelectionChanged: (s) => setState(() => type = s.first),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: Card(
                  child: ListTile(
                    leading: Icon(iconOf(icon), color: Color(color)),
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
              child: const Text('Save category'),
            ),
          ],
        ),
      );
}
