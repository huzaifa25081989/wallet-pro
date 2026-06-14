import 'package:flutter/foundation.dart';
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
    return openDatabase(path, version: 1, onCreate: _create);
  }

  static Future<void> _create(Database d, int v) async {
    await d.execute(
        'CREATE TABLE accounts(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, type TEXT, icon INTEGER, color INTEGER, opening REAL DEFAULT 0)');
    await d.execute(
        'CREATE TABLE cats(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, type TEXT, icon INTEGER, color INTEGER)');
    await d.execute(
        'CREATE TABLE txns(id INTEGER PRIMARY KEY AUTOINCREMENT, type TEXT, amount REAL, accountId INTEGER, toAccountId INTEGER, categoryId INTEGER, date TEXT, note TEXT)');
    await d.execute(
        'CREATE TABLE loans(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, type TEXT, principal REAL, rate REAL, dueDate TEXT, paid REAL DEFAULT 0, note TEXT)');
    await d.execute(
        'CREATE TABLE budgets(id INTEGER PRIMARY KEY AUTOINCREMENT, categoryId INTEGER, limitAmt REAL)');

    Future<void> cat(String n, String t, IconData i, Color c) =>
        d.insert('cats', {'name': n, 'type': t, 'icon': i.codePoint, 'color': c.value});

    // Expense categories
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
    await cat('Loan Payment', 'expense', Icons.account_balance, Colors.blueGrey);
    await cat('Other Expense', 'expense', Icons.category, Colors.grey);
    // Income categories
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
  static Future<Map<String, Object?>> dump() async {
    final d = await db;
    return {
      for (final t in ['accounts', 'cats', 'txns', 'loans', 'budgets']) t: await d.query(t)
    };
  }

  static Future<void> restore(Map data) async {
    final d = await db;
    await d.transaction((tx) async {
      for (final t in ['accounts', 'cats', 'txns', 'loans', 'budgets']) {
        await tx.delete(t);
        for (final row in (data[t] as List? ?? const [])) {
          await tx.insert(t, Map<String, Object?>.from(row as Map));
        }
      }
    });
    bus.ping();
  }
}
