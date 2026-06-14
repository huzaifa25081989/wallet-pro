import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Simple event bus so every screen refreshes after any data change.
class Bus extends ChangeNotifier {
  void ping() => notifyListeners();
}

final bus = Bus();

class DB {
  static Database? _db;

  static Future<Database> get db async => _db ??= await _open();

  static Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), 'wallet_pro.db');
    return openDatabase(path, version: 3, onCreate: _create, onUpgrade: _upgrade);
  }

  static Future<void> _create(Database d, int v) async {
    await d.execute(
        'CREATE TABLE accounts(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, type TEXT, icon INTEGER, color INTEGER, opening REAL DEFAULT 0, archived INTEGER DEFAULT 0, phone TEXT, grp TEXT)');
    await d.execute(
        'CREATE TABLE cats(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, type TEXT, icon INTEGER, color INTEGER, archived INTEGER DEFAULT 0)');
    await d.execute(
        'CREATE TABLE txns(id INTEGER PRIMARY KEY AUTOINCREMENT, type TEXT, amount REAL, accountId INTEGER, toAccountId INTEGER, categoryId INTEGER, date TEXT, note TEXT)');
    await d.execute(
        'CREATE TABLE loans(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, type TEXT, principal REAL, rate REAL, dueDate TEXT, paid REAL DEFAULT 0, note TEXT)');
    await d.execute(
        'CREATE TABLE budgets(id INTEGER PRIMARY KEY AUTOINCREMENT, categoryId INTEGER, limitAmt REAL)');
    await _createV2(d);
    await _seed(d);
  }

  static Future<void> _createV2(Database d) async {
    await d.execute('CREATE TABLE IF NOT EXISTS settings(k TEXT PRIMARY KEY, v TEXT)');
    await d.execute(
        'CREATE TABLE IF NOT EXISTS goals(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, target REAL, saved REAL DEFAULT 0, icon INTEGER, color INTEGER, dueDate TEXT, note TEXT)');
    // Recurring rules + planned payments.
    // autoPost 1 = post automatically on/after nextDate; 0 = reminder only.
    await d.execute('''CREATE TABLE IF NOT EXISTS recurring(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT, type TEXT, amount REAL,
        accountId INTEGER, toAccountId INTEGER, categoryId INTEGER, note TEXT,
        freq TEXT, dayOfMonth INTEGER, nextDate TEXT,
        autoPost INTEGER DEFAULT 1, active INTEGER DEFAULT 1)''');
  }

  static Future<void> _upgrade(Database d, int from, int to) async {
    if (from < 2) {
      // add new columns to existing tables (safe if column is new)
      for (final sql in [
        'ALTER TABLE accounts ADD COLUMN archived INTEGER DEFAULT 0',
        'ALTER TABLE accounts ADD COLUMN phone TEXT',
        'ALTER TABLE cats ADD COLUMN archived INTEGER DEFAULT 0',
      ]) {
        try {
          await d.execute(sql);
        } catch (_) {}
      }
      await _createV2(d);
    }
    if (from < 3) {
      try {
        await d.execute("ALTER TABLE accounts ADD COLUMN grp TEXT DEFAULT 'main'");
      } catch (_) {}
      try {
        await d.execute(
            "UPDATE accounts SET grp = CASE WHEN type='Investment' THEN 'investment' WHEN type='Person' THEN 'people' ELSE 'main' END");
      } catch (_) {}
    }
  }

  static Future<void> _seed(Database d) async {
    Future<void> cat(String n, String t, IconData i, Color c) =>
        d.insert('cats', {'name': n, 'type': t, 'icon': i.codePoint, 'color': c.value});

    await cat('Food & Dining', 'expense', Icons.restaurant, Colors.deepOrange);
    await cat('Groceries', 'expense', Icons.shopping_cart, Colors.green);
    await cat('Transport', 'expense', Icons.directions_car, Colors.blue);
    await cat('Fuel', 'expense', Icons.local_gas_station, Colors.brown);
    await cat('Bills & Utilities', 'expense', Icons.receipt_long, Colors.indigo);
    await cat('Rent', 'expense', Icons.home, Colors.teal);
    await cat('Shopping', 'expense', Icons.shopping_bag, Colors.purple);
    await cat('Health', 'expense', Icons.local_hospital, Colors.red);
    await cat('Education', 'expense', Icons.school, Colors.cyan);
    await cat('Entertainment', 'expense', Icons.movie, Colors.pink);
    await cat('Charity & Zakat', 'expense', Icons.volunteer_activism, Colors.lightGreen);
    await cat('Family', 'expense', Icons.family_restroom, Colors.amber);
    await cat('Pocket Money', 'expense', Icons.payments, Colors.deepPurple);
    await cat('Loan Payment', 'expense', Icons.account_balance, Colors.blueGrey);
    await cat('Other Expense', 'expense', Icons.category, Colors.grey);
    await cat('Salary', 'income', Icons.payments, Colors.green);
    await cat('Business', 'income', Icons.storefront, Colors.teal);
    await cat('Investment Income', 'income', Icons.trending_up, Colors.indigo);
    await cat('Loan Received', 'income', Icons.account_balance, Colors.blueGrey);
    await cat('Gifts', 'income', Icons.card_giftcard, Colors.pink);
    await cat('Other Income', 'income', Icons.attach_money, Colors.grey);

    await d.insert('accounts', {
      'name': 'Cash',
      'type': 'Cash',
      'icon': Icons.account_balance_wallet.codePoint,
      'color': Colors.teal.value,
      'opening': 0.0,
    });
  }

  // ---------- generic CRUD ----------
  static Future<List<Map<String, Object?>>> all(String table,
          {String? where, List<Object?>? args, String? orderBy}) async =>
      (await db).query(table, where: where, whereArgs: args, orderBy: orderBy);

  static Future<int> insert(String t, Map<String, Object?> m) async {
    final r = await (await db).insert(t, m);
    bus.ping();
    return r;
  }

  static Future<void> update(String t, Map<String, Object?> m) async {
    await (await db).update(t, m, where: 'id=?', whereArgs: [m['id']]);
    bus.ping();
  }

  static Future<void> delete(String t, int id) async {
    await (await db).delete(t, where: 'id=?', whereArgs: [id]);
    bus.ping();
  }

  /// Active (non-archived) accounts.
  static Future<List<Map<String, Object?>>> accounts({bool includeArchived = false}) async =>
      (await db).query('accounts',
          where: includeArchived ? null : 'archived=0', orderBy: 'name');

  /// Active (non-archived) categories, optionally by type.
  static Future<List<Map<String, Object?>>> categories(
      {String? type, bool includeArchived = false}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (!includeArchived) where.add('archived=0');
    if (type != null) {
      where.add('type=?');
      args.add(type);
    }
    return (await db).query('cats',
        where: where.isEmpty ? null : where.join(' AND '),
        whereArgs: args.isEmpty ? null : args,
        orderBy: 'name');
  }

  // ---------- balances ----------
  static Future<Map<int, double>> balances() async {
    final d = await db;
    final accts = await d.query('accounts');
    final map = <int, double>{
      for (final a in accts) a['id'] as int: ((a['opening'] as num?) ?? 0).toDouble()
    };
    final rows = await d.rawQuery(
        'SELECT type, accountId, toAccountId, SUM(amount) s FROM txns GROUP BY type, accountId, toAccountId');
    for (final r in rows) {
      final s = ((r['s'] as num?) ?? 0).toDouble();
      final t = r['type'] as String?;
      final a = r['accountId'] as int?;
      final b = r['toAccountId'] as int?;
      if (t == 'income' && a != null && map.containsKey(a)) map[a] = map[a]! + s;
      if (t == 'expense' && a != null && map.containsKey(a)) map[a] = map[a]! - s;
      if (t == 'transfer') {
        if (a != null && map.containsKey(a)) map[a] = map[a]! - s;
        if (b != null && map.containsKey(b)) map[b] = map[b]! + s;
      }
    }
    return map;
  }

  /// Full ledger for one account, oldest first, with signed delta + running balance.
  /// Each row: {txn fields..., catName, catIcon, catColor, otherName, delta, running}
  static Future<List<Map<String, Object?>>> accountLedger(int accountId) async {
    final d = await db;
    final acc = await d.query('accounts', where: 'id=?', whereArgs: [accountId]);
    final opening = acc.isEmpty ? 0.0 : ((acc.first['opening'] as num?) ?? 0).toDouble();
    final rows = await d.rawQuery('''
      SELECT t.*, c.name catName, c.icon catIcon, c.color catColor,
             af.name fromName, at.name toName
      FROM txns t
      LEFT JOIN cats c ON c.id=t.categoryId
      LEFT JOIN accounts af ON af.id=t.accountId
      LEFT JOIN accounts at ON at.id=t.toAccountId
      WHERE t.accountId=? OR t.toAccountId=?
      ORDER BY t.date ASC, t.id ASC''', [accountId, accountId]);
    double running = opening;
    final out = <Map<String, Object?>>[];
    for (final r in rows) {
      final amt = ((r['amount'] as num?) ?? 0).toDouble();
      final type = r['type'] as String?;
      double delta = 0;
      String label;
      if (type == 'income') {
        delta = amt;
        label = r['catName'] as String? ?? 'Income';
      } else if (type == 'expense') {
        delta = -amt;
        label = r['catName'] as String? ?? 'Expense';
      } else {
        // transfer
        if ((r['accountId'] as int?) == accountId) {
          delta = -amt;
          label = 'Transfer to ${r['toName'] ?? ''}';
        } else {
          delta = amt;
          label = 'Transfer from ${r['fromName'] ?? ''}';
        }
      }
      running += delta;
      out.add({...r, 'delta': delta, 'running': running, 'label': label});
    }
    return out.reversed.toList(); // newest first for display
  }

  // ---------- report queries ----------
  static Future<double> totalFor(String type, String fromIso, String toIso) async {
    final r = await (await db).rawQuery(
        'SELECT SUM(amount) s FROM txns WHERE type=? AND date>=? AND date<?',
        [type, fromIso, toIso]);
    return ((r.first['s'] as num?) ?? 0).toDouble();
  }

  static Future<List<Map<String, Object?>>> catTotals(
      String type, String fromIso, String toIso) async {
    return (await db).rawQuery('''
      SELECT c.name n, c.color col, c.icon ic, SUM(t.amount) s
      FROM txns t LEFT JOIN cats c ON c.id = t.categoryId
      WHERE t.type=? AND t.date>=? AND t.date<?
      GROUP BY t.categoryId ORDER BY s DESC''', [type, fromIso, toIso]);
  }

  static Future<List<Map<String, Object?>>> monthlyTotals(String fromIso) async {
    return (await db).rawQuery(
        "SELECT substr(date,1,7) m, type, SUM(amount) s FROM txns WHERE date>=? AND type IN ('income','expense') GROUP BY m, type",
        [fromIso]);
  }

  static Future<Map<int, double>> spentByCat(String fromIso) async {
    final rows = await (await db).rawQuery(
        "SELECT categoryId, SUM(amount) s FROM txns WHERE type='expense' AND date>=? GROUP BY categoryId",
        [fromIso]);
    return {
      for (final r in rows)
        if (r['categoryId'] != null)
          r['categoryId'] as int: ((r['s'] as num?) ?? 0).toDouble()
    };
  }

  /// Suggest most-used categories for a type (recency + frequency), for quick pick.
  static Future<List<int>> suggestedCats(String type, {int limit = 4}) async {
    final rows = await (await db).rawQuery('''
      SELECT categoryId, COUNT(*) c, MAX(date) last FROM txns
      WHERE type=? AND categoryId IS NOT NULL
      GROUP BY categoryId ORDER BY c DESC, last DESC LIMIT ?''', [type, limit]);
    return [for (final r in rows) r['categoryId'] as int];
  }

  // ---------- settings ----------
  static Future<String?> settingGet(String k) async {
    final r = await (await db).query('settings', where: 'k=?', whereArgs: [k]);
    return r.isEmpty ? null : r.first['v'] as String?;
  }

  static Future<void> settingSet(String k, String v) async {
    await (await db)
        .insert('settings', {'k': k, 'v': v}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---------- recurring / planned ----------
  static DateTime _advance(DateTime from, String freq, int dom) {
    switch (freq) {
      case 'weekly':
        return from.add(const Duration(days: 7));
      case 'yearly':
        return DateTime(from.year + 1, from.month, from.day);
      default: // monthly
        var y = from.year, m = from.month + 1;
        if (m > 12) {
          m = 1;
          y++;
        }
        final lastDay = DateTime(y, m + 1, 0).day;
        return DateTime(y, m, dom.clamp(1, lastDay));
    }
  }

  /// Posts all due auto rules up to [now]. Returns number of txns created.
  static Future<int> runRecurring([DateTime? at]) async {
    final d = await db;
    final now = at ?? DateTime.now();
    final rules = await d.query('recurring', where: 'active=1 AND autoPost=1');
    int posted = 0;
    for (final r in rules) {
      var next = DateTime.tryParse(r['nextDate'] as String? ?? '');
      if (next == null) continue;
      final freq = r['freq'] as String? ?? 'monthly';
      final dom = (r['dayOfMonth'] as int?) ?? next.day;
      var guard = 0;
      while (!next!.isAfter(now) && guard < 60) {
        await d.insert('txns', {
          'type': r['type'],
          'amount': r['amount'],
          'accountId': r['accountId'],
          'toAccountId': r['toAccountId'],
          'categoryId': r['categoryId'],
          'date': next.toIso8601String(),
          'note': '${r['note'] ?? ''}${(r['note'] ?? '').toString().isEmpty ? '' : ' '}(auto)',
        });
        posted++;
        next = _advance(next, freq, dom);
        guard++;
      }
      await d.update('recurring', {'nextDate': next!.toIso8601String()},
          where: 'id=?', whereArgs: [r['id']]);
    }
    if (posted > 0) bus.ping();
    return posted;
  }

  /// Bank-statement style data for [accountId] (or whole book if null),
  /// for the date range [fromIso, toIso). Returns opening, dated rows
  /// (date, desc, dr=outflow, cr=inflow, bal=running), closing and totals.
  static Future<Map<String, Object?>> statement(
      int? accountId, String fromIso, String toIso) async {
    final d = await db;
    double opening = 0;
    List<Map<String, Object?>> raw;
    if (accountId != null) {
      final acc = await d.query('accounts', where: 'id=?', whereArgs: [accountId]);
      opening = acc.isEmpty ? 0 : ((acc.first['opening'] as num?) ?? 0).toDouble();
      // opening = account opening + net effect of everything before fromIso
      final before = await d.rawQuery('''
        SELECT t.* FROM txns t
        WHERE (t.accountId=? OR t.toAccountId=?) AND t.date < ?''',
          [accountId, accountId, fromIso]);
      for (final r in before) {
        opening += _delta(r, accountId);
      }
      raw = await d.rawQuery('''
        SELECT t.*, c.name catName, af.name fromName, at.name toName
        FROM txns t
        LEFT JOIN cats c ON c.id=t.categoryId
        LEFT JOIN accounts af ON af.id=t.accountId
        LEFT JOIN accounts at ON at.id=t.toAccountId
        WHERE (t.accountId=? OR t.toAccountId=?) AND t.date>=? AND t.date<?
        ORDER BY t.date ASC, t.id ASC''',
          [accountId, accountId, fromIso, toIso]);
    } else {
      // whole book: opening = sum of account openings + net income/expense before from
      final accs = await d.query('accounts');
      for (final a in accs) opening += ((a['opening'] as num?) ?? 0).toDouble();
      final before = await d.rawQuery(
          "SELECT type, SUM(amount) s FROM txns WHERE date<? AND type IN ('income','expense') GROUP BY type",
          [fromIso]);
      for (final r in before) {
        final s = ((r['s'] as num?) ?? 0).toDouble();
        opening += r['type'] == 'income' ? s : -s;
      }
      raw = await d.rawQuery('''
        SELECT t.*, c.name catName, af.name fromName, at.name toName
        FROM txns t
        LEFT JOIN cats c ON c.id=t.categoryId
        LEFT JOIN accounts af ON af.id=t.accountId
        LEFT JOIN accounts at ON at.id=t.toAccountId
        WHERE t.date>=? AND t.date<? AND t.type IN ('income','expense')
        ORDER BY t.date ASC, t.id ASC''', [fromIso, toIso]);
    }

    double running = opening, totalDr = 0, totalCr = 0;
    final rows = <Map<String, Object?>>[];
    for (final r in raw) {
      final delta = accountId != null ? _delta(r, accountId) : _bookDelta(r);
      final desc = _describe(r, accountId);
      final cr = delta > 0 ? delta : 0.0;
      final dr = delta < 0 ? -delta : 0.0;
      running += delta;
      totalCr += cr;
      totalDr += dr;
      rows.add({'date': r['date'], 'desc': desc, 'dr': dr, 'cr': cr, 'bal': running});
    }
    return {
      'opening': opening,
      'rows': rows,
      'closing': running,
      'totalDr': totalDr,
      'totalCr': totalCr,
    };
  }

  static double _delta(Map<String, Object?> r, int accountId) {
    final amt = ((r['amount'] as num?) ?? 0).toDouble();
    switch (r['type']) {
      case 'income':
        return amt;
      case 'expense':
        return -amt;
      default: // transfer
        if ((r['accountId'] as int?) == accountId) return -amt;
        if ((r['toAccountId'] as int?) == accountId) return amt;
        return 0;
    }
  }

  static double _bookDelta(Map<String, Object?> r) {
    final amt = ((r['amount'] as num?) ?? 0).toDouble();
    return r['type'] == 'income' ? amt : -amt;
  }

  static String _describe(Map<String, Object?> r, int? accountId) {
    final note = (r['note'] as String?)?.trim() ?? '';
    switch (r['type']) {
      case 'transfer':
        final base = accountId != null && (r['accountId'] as int?) == accountId
            ? 'Transfer to ${r['toName'] ?? ''}'
            : 'Transfer from ${r['fromName'] ?? ''}';
        return note.isEmpty ? base : '$base - $note';
      default:
        final cat = r['catName'] as String? ?? (r['type'] as String? ?? '');
        return note.isEmpty ? cat : '$cat - $note';
    }
  }

  // ---------- get-or-create (used by CSV import) ----------
  static Future<int> accountByName(String name) async {
    final d = await db;
    final r = await d.query('accounts', where: 'name=?', whereArgs: [name]);
    if (r.isNotEmpty) return r.first['id'] as int;
    return d.insert('accounts', {
      'name': name,
      'type': 'Bank',
      'icon': Icons.account_balance.codePoint,
      'color': Colors.blueGrey.value,
      'opening': 0.0,
    });
  }

  static Future<int> catByName(String name, String type) async {
    final d = await db;
    final r = await d.query('cats', where: 'name=? AND type=?', whereArgs: [name, type]);
    if (r.isNotEmpty) return r.first['id'] as int;
    return d.insert('cats', {
      'name': name,
      'type': type,
      'icon': Icons.label.codePoint,
      'color': Colors.grey.value,
    });
  }

  // ---------- backup / restore ----------
  static const _tables = ['accounts', 'cats', 'txns', 'loans', 'budgets', 'goals', 'recurring', 'settings'];

  static Future<Map<String, Object?>> dump() async {
    final d = await db;
    return {for (final t in _tables) t: await d.query(t)};
  }

  static Future<void> restore(Map data) async {
    final d = await db;
    await d.transaction((tx) async {
      for (final t in _tables) {
        if (!data.containsKey(t)) continue;
        await tx.delete(t);
        for (final row in (data[t] as List? ?? const [])) {
          await tx.insert(t, Map<String, Object?>.from(row as Map));
        }
      }
    });
    bus.ping();
  }
}
