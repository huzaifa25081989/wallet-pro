import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Simple local app lock: a PIN, lock-on-open, and delete protection.
class LockController extends ChangeNotifier {
  String? _pin;
  bool lockOnOpen = false;
  bool lockDelete = false;
  bool unlocked = true;

  bool get hasPin => _pin != null && _pin!.isNotEmpty;
  bool get needsUnlock => lockOnOpen && hasPin && !unlocked;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _pin = p.getString('lockPin');
    lockOnOpen = p.getBool('lockOnOpen') ?? false;
    lockDelete = p.getBool('lockDelete') ?? false;
    unlocked = !(lockOnOpen && hasPin);
    notifyListeners();
  }

  bool verify(String pin) {
    if (hasPin && pin == _pin) {
      unlocked = true;
      notifyListeners();
      return true;
    }
    return false;
  }

  void lockNow() {
    if (lockOnOpen && hasPin) {
      unlocked = false;
      notifyListeners();
    }
  }

  Future<void> setPin(String? pin) async {
    final p = await SharedPreferences.getInstance();
    _pin = pin;
    if (pin == null || pin.isEmpty) {
      await p.remove('lockPin');
      lockOnOpen = false;
      lockDelete = false;
      await p.setBool('lockOnOpen', false);
      await p.setBool('lockDelete', false);
    } else {
      await p.setString('lockPin', pin);
    }
    unlocked = true;
    notifyListeners();
  }

  Future<void> setLockOnOpen(bool v) async {
    final p = await SharedPreferences.getInstance();
    lockOnOpen = v;
    await p.setBool('lockOnOpen', v);
    notifyListeners();
  }

  Future<void> setLockDelete(bool v) async {
    final p = await SharedPreferences.getInstance();
    lockDelete = v;
    await p.setBool('lockDelete', v);
    notifyListeners();
  }
}

final lock = LockController();
