import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'cloud.dart';
import 'db.dart';

class FamilyService {
  FirebaseFirestore get _fs => FirebaseFirestore.instance;
  String? get _uid => cloud.user?.uid;
  String get _email => cloud.user?.email ?? '';

  bool get available => cloud.ready && cloud.signedIn;

  // ---- my share code ----
  Future<String> ensureCode() async {
    final me = _fs.collection('users').doc(_uid);
    final snap = await me.get();
    final existing = snap.data()?['connectCode'] as String?;
    if (existing != null && existing.isNotEmpty) return existing;
    final code = _gen();
    await me.set({'connectCode': code, 'email': _email}, SetOptions(merge: true));
    await _fs.collection('codes').doc(code).set({'uid': _uid});
    return code;
  }

  String _gen() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();
  }

  // ---- connect to someone else's code (I will see THEM after they approve) ----
  Future<String?> connect(String code, String name) async {
    final c = await _fs.collection('codes').doc(code.trim().toUpperCase()).get();
    if (!c.exists) return 'Code not found';
    final ownerUid = c.data()!['uid'] as String;
    if (ownerUid == _uid) return 'That is your own code';
    await _fs.collection('users').doc(ownerUid).collection('peers').doc(_uid).set({
      'email': _email,
      'name': name,
      'status': 'pending',
      'ts': FieldValue.serverTimestamp(),
    });
    // remember locally who I asked to follow, with the name I gave them
    final p = await SharedPreferences.getInstance();
    final links = p.getStringList('familyLinks') ?? [];
    final entry = jsonEncode({'uid': ownerUid, 'name': name});
    if (!links.any((e) => (jsonDecode(e)['uid']) == ownerUid)) {
      links.add(entry);
      await p.setStringList('familyLinks', links);
    }
    return null;
  }

  Future<List<Map<String, Object?>>> myLinks() async {
    final p = await SharedPreferences.getInstance();
    final links = p.getStringList('familyLinks') ?? [];
    final out = <Map<String, Object?>>[];
    for (final e in links) {
      final m = jsonDecode(e) as Map<String, Object?>;
      // check approval
      bool approved = false;
      try {
        final peer = await _fs.collection('users').doc(m['uid'] as String)
            .collection('peers').doc(_uid).get();
        approved = (peer.data()?['status']) == 'approved';
      } catch (_) {}
      out.add({...m, 'approved': approved});
    }
    return out;
  }

  // ---- people who want to see ME (I approve) ----
  Future<List<Map<String, Object?>>> incomingPeers() async {
    final q = await _fs.collection('users').doc(_uid).collection('peers').get();
    return [
      for (final d in q.docs) {'uid': d.id, ...d.data()},
    ];
  }

  Future<void> approvePeer(String peerUid) async {
    await _fs.collection('users').doc(_uid).collection('peers').doc(peerUid)
        .set({'status': 'approved'}, SetOptions(merge: true));
  }

  Future<void> removePeer(String peerUid) async {
    await _fs.collection('users').doc(_uid).collection('peers').doc(peerUid).delete();
  }

  // ---- view a family member's data (decoded from their backup dump) ----
  Future<Map<String, Object?>?> peerData(String ownerUid) async {
    final snap = await _fs.collection('users').doc(ownerUid).get();
    final gz = snap.data()?['dump'] as String?;
    if (gz == null) return null;
    final json = utf8.decode(gzip.decode(base64Decode(gz)));
    return jsonDecode(json) as Map<String, Object?>;
  }

  // ---- bill an expense to a family member ----
  Future<String?> billExpense({
    required String toUid,
    required String toName,
    required double amount,
    required String category,
    required String note,
    required DateTime date,
    required int payAccountId,
  }) async {
    // 1) my own side: I paid, so they owe me -> transfer payAccount -> their person account
    final theirAccount = await DB.accountByName(toName);
    await DB.insert('txns', {
      'type': 'transfer',
      'amount': amount,
      'accountId': payAccountId,
      'toAccountId': theirAccount,
      'categoryId': null,
      'date': date.toIso8601String(),
      'note': note.isEmpty ? 'Paid for $toName' : note,
    });
    bus.ping();
    // 2) send request to them
    await _fs.collection('users').doc(toUid).collection('inbox').add({
      'fromUid': _uid,
      'fromEmail': _email,
      'amount': amount,
      'category': category,
      'note': note,
      'date': date.toIso8601String(),
      'status': 'pending',
      'ts': FieldValue.serverTimestamp(),
    });
    return null;
  }

  // ---- inbox: expenses billed TO me ----
  Future<List<Map<String, Object?>>> inbox() async {
    final q = await _fs.collection('users').doc(_uid).collection('inbox')
        .where('status', isEqualTo: 'pending').get();
    return [for (final d in q.docs) {'id': d.id, ...d.data()}];
  }

  /// Approve: record the expense on my side, paid against the sender (I owe them).
  Future<void> approveInbox(Map<String, Object?> item, String fromName) async {
    final amount = (item['amount'] as num?)?.toDouble() ?? 0;
    final senderAccount = await DB.accountByName(fromName);
    final catName = (item['category'] as String?)?.isNotEmpty == true ? item['category'] as String : 'Other Expense';
    final catId = await DB.catByName(catName, 'expense');
    await DB.insert('txns', {
      'type': 'expense',
      'amount': amount,
      'accountId': senderAccount, // paying "from" the person I owe -> increases payable
      'toAccountId': null,
      'categoryId': catId,
      'date': item['date'] ?? DateTime.now().toIso8601String(),
      'note': (item['note'] as String?) ?? 'Billed by $fromName',
    });
    bus.ping();
    await _fs.collection('users').doc(_uid).collection('inbox').doc(item['id'] as String)
        .set({'status': 'approved'}, SetOptions(merge: true));
  }

  Future<void> declineInbox(String id) async {
    await _fs.collection('users').doc(_uid).collection('inbox').doc(id)
        .set({'status': 'declined'}, SetOptions(merge: true));
  }
}

final family = FamilyService();
