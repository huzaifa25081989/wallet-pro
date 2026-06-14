import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'db.dart';

/// Public key (Ed25519) that verifies activation codes. The matching private
/// key lives only in the owner's offline key-generator, so codes cannot be forged.
const _publicKeyB64Url = 'Xnk78pH8ivPQpd4lsdDehDNMQ7w2insJuVku67dke40';

List<int> _b64urlDecode(String s) {
  var t = s.replaceAll('-', '+').replaceAll('_', '/');
  while (t.length % 4 != 0) {
    t += '=';
  }
  return base64.decode(t);
}

int _todayInt() {
  final n = DateTime.now();
  return n.year * 10000 + n.month * 100 + n.day;
}

String _fmtExpiry(int yyyymmdd) {
  if (yyyymmdd >= 99991231) return 'Lifetime';
  final s = yyyymmdd.toString().padLeft(8, '0');
  return '${s.substring(6, 8)}-${s.substring(4, 6)}-${s.substring(0, 4)}';
}

class ProController extends ChangeNotifier {
  bool isPro = false;
  String tier = '';
  int expiry = 0; // yyyymmdd
  String deviceId = '';

  String get expiryLabel => expiry == 0 ? '' : _fmtExpiry(expiry);

  Future<void> load() async {
    deviceId = await DB.settingGet('deviceId') ?? '';
    if (deviceId.isEmpty) {
      final r = Random.secure();
      deviceId = List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join();
      await DB.settingSet('deviceId', deviceId);
    }
    final code = await DB.settingGet('proKey');
    if (code != null && code.isNotEmpty) {
      final res = await verify(code);
      if (res != null) {
        isPro = true;
        tier = res.$1;
        expiry = res.$2;
      } else {
        isPro = false;
      }
    }
    notifyListeners();
  }

  /// Returns (tier, expiryInt) if the code is valid for THIS device & not expired.
  Future<(String, int)?> verify(String code) async {
    try {
      final parts = code.trim().split('.');
      if (parts.length != 2) return null;
      final msgBytes = _b64urlDecode(parts[0]);
      final sigBytes = _b64urlDecode(parts[1]);
      final msg = utf8.decode(msgBytes);
      final fields = msg.split('|');
      if (fields.length != 3) return null;
      final dev = fields[0];
      final t = fields[1];
      final exp = int.tryParse(fields[2]) ?? 0;

      final algorithm = Ed25519();
      final pub = SimplePublicKey(_b64urlDecode(_publicKeyB64Url),
          type: KeyPairType.ed25519);
      final ok = await algorithm.verify(msgBytes,
          signature: Signature(sigBytes, publicKey: pub));
      if (!ok) return null;
      if (dev != deviceId) return null; // bound to this device
      if (exp < _todayInt()) return null; // expired
      return (t, exp);
    } catch (_) {
      return null;
    }
  }

  /// Activate with a code. Throws a friendly message on failure.
  Future<void> activate(String code) async {
    final res = await verify(code);
    if (res == null) {
      // Distinguish reasons for a clearer message.
      final parts = code.trim().split('.');
      if (parts.length == 2) {
        try {
          final msg = utf8.decode(_b64urlDecode(parts[0]));
          final f = msg.split('|');
          if (f.length == 3 && f[0] != deviceId) {
            throw 'This code was issued for a different device.';
          }
          if (f.length == 3 && (int.tryParse(f[2]) ?? 0) < _todayInt()) {
            throw 'This code has expired.';
          }
        } catch (e) {
          if (e is String) rethrow;
        }
      }
      throw 'Invalid activation code.';
    }
    await DB.settingSet('proKey', code.trim());
    isPro = true;
    tier = res.$1;
    expiry = res.$2;
    notifyListeners();
  }

  Future<void> deactivate() async {
    await DB.settingSet('proKey', '');
    isPro = false;
    tier = '';
    expiry = 0;
    notifyListeners();
  }
}

final pro = ProController();
