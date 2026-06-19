import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'db.dart';
import 'firebase_options.dart';

/// Handles optional cloud backup: email/password sign-in and automatic
/// syncing of the whole database to Firestore on every change.
class CloudSync extends ChangeNotifier {
  bool ready = false;
  bool autoSync = true;
  String? error;
  DateTime? lastSynced;
  Timer? _debounce;
  bool _busy = false;

  User? get user => ready ? FirebaseAuth.instance.currentUser : null;
  bool get signedIn => user != null;
  String? get email => user?.email;

  Future<void> init() async {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      ready = true;
      final p = await SharedPreferences.getInstance();
      autoSync = p.getBool('cloudAuto') ?? true;
      bus.addListener(_onChange);
      FirebaseAuth.instance.authStateChanges().listen((_) => notifyListeners());
    } catch (e) {
      error = e.toString();
      ready = false;
    }
    notifyListeners();
  }

  void _onChange() {
    if (!signedIn || !autoSync) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), backup);
  }

  Future<void> setAuto(bool v) async {
    autoSync = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool('cloudAuto', v);
    notifyListeners();
    if (v && signedIn) backup();
  }

  Future<String?> signUp(String em, String pass) async {
    try {
      await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: em.trim(), password: pass);
      notifyListeners();
      await backup();
      return null;
    } on FirebaseAuthException catch (e) {
      return _msg(e);
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> signIn(String em, String pass) async {
    try {
      await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: em.trim(), password: pass);
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      return _msg(e);
    } catch (e) {
      return e.toString();
    }
  }

  Future<void> signOut() async {
    await FirebaseAuth.instance.signOut();
    notifyListeners();
  }

  String _msg(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'That email already has an account — try Sign in instead.';
      case 'invalid-email':
        return 'That email address looks invalid.';
      case 'weak-password':
        return 'Password too weak — use at least 6 characters.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Wrong email or password.';
      case 'network-request-failed':
        return 'No internet connection.';
      case 'operation-not-allowed':
        return 'Email sign-in is not enabled in Firebase yet (enable Email/Password).';
      default:
        return e.message ?? e.code;
    }
  }

  Future<bool> backup() async {
    if (!signedIn || _busy) return false;
    _busy = true;
    try {
      final dump = await DB.dump();
      final json = jsonEncode(dump);
      final gz = base64Encode(gzip.encode(utf8.encode(json)));
      await FirebaseFirestore.instance.collection('users').doc(user!.uid).set({
        'dump': gz,
        'updatedAt': FieldValue.serverTimestamp(),
        'app': 'wallet_pro',
      });
      lastSynced = DateTime.now();
      error = null;
      notifyListeners();
      return true;
    } catch (e) {
      error = e.toString();
      notifyListeners();
      return false;
    } finally {
      _busy = false;
    }
  }

  Future<String?> restore() async {
    if (!signedIn) return 'Not signed in';
    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(user!.uid).get();
      if (!doc.exists || doc.data()?['dump'] == null) {
        return 'No cloud backup found yet for this account.';
      }
      final gz = doc.data()!['dump'] as String;
      final json = utf8.decode(gzip.decode(base64Decode(gz)));
      await DB.restore(jsonDecode(json) as Map);
      bus.ping();
      return null;
    } catch (e) {
      return e.toString();
    }
  }
}

final cloud = CloudSync();
