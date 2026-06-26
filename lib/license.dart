import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Public verification key (safe to ship). Private seed is kept by the owner.
const String kLicensePublicKey = 'sWf9tJyTP374ynePrEuPAWWYJ8Jdsco3FmdrZMQ8Np0=';
const String kOwnerEmail = 'muhammadhuzaifa2010@gmail.com';
const int kTrialDays = 30;

class Plan {
  final String code;
  final String label;
  final int days;
  final int priceUsd;
  const Plan(this.code, this.label, this.days, this.priceUsd);
}

const kPlans = <Plan>[
  Plan('1M', '1 Month', 30, 10),
  Plan('1Y', '1 Year', 365, 30),
  Plan('2Y', '2 Years', 730, 50),
];

class LicenseController extends ChangeNotifier {
  String appId = '';
  int installEpoch = 0;
  String? plan; // active premium plan code
  int premiumExpiry = 0; // epoch seconds

  final _algo = Ed25519();

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    appId = p.getString('lic_appId') ?? '';
    if (appId.isEmpty) {
      appId = _genId();
      await p.setString('lic_appId', appId);
    }
    installEpoch = p.getInt('lic_install') ?? 0;
    if (installEpoch == 0) {
      installEpoch = _now();
      await p.setInt('lic_install', installEpoch);
    }
    plan = p.getString('lic_plan');
    premiumExpiry = p.getInt('lic_expiry') ?? 0;
    notifyListeners();
  }

  int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  String _genId() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(8, (_) => chars[r.nextInt(chars.length)]).join();
  }

  int get trialEndEpoch => installEpoch + kTrialDays * 86400;
  bool get isTrial => _now() < trialEndEpoch && !isPremium;
  bool get isPremium => premiumExpiry > _now();
  bool get isActive => isTrial || isPremium;

  int get trialDaysLeft {
    final d = ((trialEndEpoch - _now()) / 86400).ceil();
    return d < 0 ? 0 : d;
  }

  int get premiumDaysLeft {
    final d = ((premiumExpiry - _now()) / 86400).ceil();
    return d < 0 ? 0 : d;
  }

  DateTime get premiumExpiryDate =>
      DateTime.fromMillisecondsSinceEpoch(premiumExpiry * 1000);

  String planLabel(String? code) {
    for (final pl in kPlans) {
      if (pl.code == code) return pl.label;
    }
    return code ?? '';
  }

  /// Called by the billing service when a Play subscription is active/restored.
  Future<void> applyBillingPurchase(String planCode, int expiryEpoch) async {
    final changed = expiryEpoch > premiumExpiry || plan != planCode;
    if (!changed) return;
    plan = planCode;
    if (expiryEpoch > premiumExpiry) premiumExpiry = expiryEpoch;
    final p = await SharedPreferences.getInstance();
    await p.setString('lic_plan', planCode);
    await p.setInt('lic_expiry', premiumExpiry);
    notifyListeners();
  }

  /// Activation code format: base64url(payload) + "." + base64url(signature)
  /// payload = "appId|planCode|expiryEpoch"
  Future<String?> activate(String rawCode) async {
    try {
      final code = rawCode.trim().replaceAll(RegExp(r'\s'), '');
      final dot = code.indexOf('.');
      if (dot <= 0) return 'Invalid code format';
      final payloadBytes = base64Url.decode(_pad(code.substring(0, dot)));
      final sigBytes = base64Url.decode(_pad(code.substring(dot + 1)));
      final payload = utf8.decode(payloadBytes);
      final parts = payload.split('|');
      if (parts.length != 3) return 'Invalid code payload';
      final codeAppId = parts[0];
      final planCode = parts[1];
      final expiry = int.tryParse(parts[2]) ?? 0;

      if (codeAppId != appId) return 'This code is for a different App ID';
      if (expiry <= _now()) return 'This code has already expired';

      final pub = SimplePublicKey(base64.decode(kLicensePublicKey), type: KeyPairType.ed25519);
      final ok = await _algo.verify(payloadBytes,
          signature: Signature(sigBytes, publicKey: pub));
      if (!ok) return 'Code signature is not valid';

      plan = planCode;
      premiumExpiry = expiry;
      final p = await SharedPreferences.getInstance();
      await p.setString('lic_plan', planCode);
      await p.setInt('lic_expiry', expiry);
      notifyListeners();
      return null; // success
    } catch (e) {
      return 'Could not read code';
    }
  }

  String _pad(String s) {
    final m = s.length % 4;
    return m == 0 ? s : s + '=' * (4 - m);
  }

  /// Owner-only: sign a license for a given appId + plan using the private seed.
  Future<String?> signLicense(String seedB64, String forAppId, Plan pl) async {
    try {
      final seed = base64.decode(seedB64.trim());
      if (seed.length != 32) return null;
      final kp = await _algo.newKeyPairFromSeed(seed);
      final expiry = _now() + pl.days * 86400;
      final payload = '${forAppId.trim().toUpperCase()}|${pl.code}|$expiry';
      final payloadBytes = utf8.encode(payload);
      final sig = await _algo.sign(payloadBytes, keyPair: kp);
      final code = '${base64Url.encode(payloadBytes).replaceAll('=', '')}'
          '.${base64Url.encode(sig.bytes).replaceAll('=', '')}';
      return code;
    } catch (_) {
      return null;
    }
  }
}

final license = LicenseController();
