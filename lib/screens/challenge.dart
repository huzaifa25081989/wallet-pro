import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../db.dart';
import '../theme.dart';
import '../widgets.dart';

String _dayKey(DateTime d) => DateFormat('yyyy-MM-dd').format(DateTime(d.year, d.month, d.day));

class DailyChallengeScreen extends StatefulWidget {
  const DailyChallengeScreen({super.key});
  @override
  State<DailyChallengeScreen> createState() => _DailyChallengeScreenState();
}

class _DailyChallengeScreenState extends State<DailyChallengeScreen> {
  double amount = 0;
  int? fromId, toId;
  Set<String> saved = {};
  bool loaded = false;
  List<Map<String, Object?>> accounts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    accounts = await DB.accounts();
    final raw = await DB.settingGet('dailyChallenge');
    if (raw != null && raw.isNotEmpty) {
      try {
        final m = jsonDecode(raw) as Map<String, Object?>;
        amount = ((m['amount'] as num?) ?? 0).toDouble();
        fromId = m['fromId'] as int?;
        toId = m['toId'] as int?;
        saved = {...((m['saved'] as List?) ?? []).map((e) => '$e')};
      } catch (_) {}
    }
    if (mounted) setState(() => loaded = true);
  }

  Future<void> _persist() async {
    await DB.settingSet('dailyChallenge', jsonEncode({
      'amount': amount,
      'fromId': fromId,
      'toId': toId,
      'saved': saved.toList(),
    }));
  }

  bool get isSetup => amount > 0;
  bool get savedToday => saved.contains(_dayKey(DateTime.now()));

  int get streak {
    int s = 0;
    var day = DateTime.now();
    if (!saved.contains(_dayKey(day))) day = day.subtract(const Duration(days: 1));
    while (saved.contains(_dayKey(day))) {
      s++;
      day = day.subtract(const Duration(days: 1));
    }
    return s;
  }

  int get bestStreak {
    if (saved.isEmpty) return 0;
    final days = saved.map((k) => DateTime.parse(k)).toList()..sort();
    int best = 1, cur = 1;
    for (int i = 1; i < days.length; i++) {
      if (days[i].difference(days[i - 1]).inDays == 1) {
        cur++;
        best = cur > best ? cur : best;
      } else {
        cur = 1;
      }
    }
    return best;
  }

  Future<void> _saveToday() async {
    if (savedToday) return;
    saved.add(_dayKey(DateTime.now()));
    // optionally move real money
    if (fromId != null && toId != null && fromId != toId) {
      await DB.insert('txns', {
        'type': 'transfer',
        'amount': amount,
        'accountId': fromId,
        'toAccountId': toId,
        'categoryId': null,
        'date': DateTime.now().toIso8601String(),
        'note': 'Daily Save Challenge',
      });
      bus.ping();
    }
    await _persist();
    if (mounted) {
      setState(() {});
      final s = streak;
      showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(s >= 2 ? '\u{1F525} $s-day streak!' : 'Saved! \u{1F389}'),
          content: Text(s >= 2
              ? 'Awesome \u2014 you\u2019ve saved $s days in a row. Keep the fire alive, come back tomorrow!'
              : 'You put ${money(amount)} aside today. Come back tomorrow to start a streak!'),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Nice'))],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: const Text('Daily Save Challenge'), actions: [
        if (isSetup)
          IconButton(icon: const Icon(Icons.settings), onPressed: _setupSheet),
      ]),
      body: isSetup ? _active() : _intro(),
    );
  }

  Widget _intro() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 10),
          const Center(child: Text('\u{1F525}', style: TextStyle(fontSize: 64))),
          const SizedBox(height: 12),
          Text('Build a saving habit', style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text('Pick a small amount to set aside every single day. Keep your streak alive \u2014 miss a day and it resets to zero. Small drops fill the bucket!',
              textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _setupSheet,
            icon: const Icon(Icons.flag),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            label: const Text('Start my challenge'),
          ),
        ],
      );

  Widget _active() {
    final cs = Theme.of(context).colorScheme;
    final total = saved.length * amount;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(gradient: headerGradient(context), borderRadius: BorderRadius.circular(20)),
          child: Column(children: [
            const Text('\u{1F525}', style: TextStyle(fontSize: 40)),
            Text('$streak', style: const TextStyle(color: Colors.white, fontSize: 52, fontWeight: FontWeight.bold, height: 1)),
            const Text('day streak', style: TextStyle(color: Colors.white70)),
          ]),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: _stat('Best streak', '$bestStreak days')),
          const SizedBox(width: 12),
          Expanded(child: _stat('Days saved', '${saved.length}')),
          const SizedBox(width: 12),
          Expanded(child: _stat('Total set aside', money(total))),
        ]),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: savedToday ? null : _saveToday,
          icon: Icon(savedToday ? Icons.check_circle : Icons.savings),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            backgroundColor: savedToday ? Colors.green : null,
          ),
          label: Text(savedToday ? 'Saved today \u2014 see you tomorrow!' : 'I saved ${money(amount)} today'),
        ),
        const SizedBox(height: 20),
        Text('Last 5 weeks', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        _grid(cs),
        const SizedBox(height: 10),
        Text('Each square is a day. Green = you saved. Keep them all green!',
            style: TextStyle(fontSize: 12, color: cs.outline)),
      ],
    );
  }

  Widget _stat(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant, borderRadius: BorderRadius.circular(14)),
        child: Column(children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 2),
          Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 10.5, color: Theme.of(context).colorScheme.outline)),
        ]),
      );

  Widget _grid(ColorScheme cs) {
    final today = DateTime.now();
    final days = List.generate(35, (i) => today.subtract(Duration(days: 34 - i)));
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final d in days)
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: saved.contains(_dayKey(d))
                  ? Colors.green
                  : (d.isAfter(today) ? Colors.transparent : cs.surfaceVariant),
              borderRadius: BorderRadius.circular(6),
              border: _dayKey(d) == _dayKey(today) ? Border.all(color: cs.primary, width: 2) : null,
            ),
            alignment: Alignment.center,
            child: Text('${d.day}', style: TextStyle(fontSize: 10, color: saved.contains(_dayKey(d)) ? Colors.white : cs.outline)),
          ),
      ],
    );
  }

  Future<void> _setupSheet() async {
    final amtCtl = TextEditingController(text: amount > 0 ? (amount == amount.roundToDouble() ? amount.toStringAsFixed(0) : '$amount') : '');
    int? f = fromId, t = toId;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
        child: StatefulBuilder(
          builder: (c, setSheet) => Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Challenge settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              TextField(
                controller: amtCtl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Save this much every day', prefixText: '$kCur ', border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              Text('Optional: actually move the money each day', style: TextStyle(fontSize: 12.5, color: Theme.of(c).colorScheme.outline)),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                value: f,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'From account', border: OutlineInputBorder()),
                items: [const DropdownMenuItem(value: null, child: Text('Just track (no transfer)')), for (final a in accounts) DropdownMenuItem(value: a['id'] as int, child: Text(a['name'] as String? ?? ''))],
                onChanged: (v) => setSheet(() => f = v),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                value: t,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Into savings account', border: OutlineInputBorder()),
                items: [const DropdownMenuItem(value: null, child: Text('Just track (no transfer)')), for (final a in accounts) DropdownMenuItem(value: a['id'] as int, child: Text(a['name'] as String? ?? ''))],
                onChanged: (v) => setSheet(() => t = v),
              ),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: () async {
                  final a = double.tryParse(amtCtl.text.replaceAll(',', '').trim()) ?? 0;
                  if (a <= 0) {
                    snack(c, 'Enter a daily amount');
                    return;
                  }
                  amount = a;
                  fromId = f;
                  toId = t;
                  await _persist();
                  if (c.mounted) Navigator.pop(c);
                  if (mounted) setState(() {});
                },
                child: const Text('Save settings'),
              ),
              if (isSetup)
                TextButton(
                  onPressed: () async {
                    final ok = await confirm(c, 'Reset challenge?', 'This clears your streak and saved days.');
                    if (!ok) return;
                    amount = 0;
                    saved.clear();
                    fromId = null;
                    toId = null;
                    await DB.settingSet('dailyChallenge', '');
                    if (c.mounted) Navigator.pop(c);
                    if (mounted) setState(() {});
                  },
                  child: const Text('Reset challenge', style: TextStyle(color: Colors.red)),
                ),
              const SizedBox(height: 8),
            ]),
          ),
        ),
      ),
    );
  }
}
