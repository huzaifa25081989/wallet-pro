import 'package:firebase_core/firebase_core.dart';

/// Firebase config for Wallet Pro (Android). Values from the project's
/// google-services.json. The API key here is a client identifier, not a
/// secret — security is enforced by Firestore rules.
class DefaultFirebaseOptions {
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBrWmAro3_yaetkvNXmtoeX-BBmooN6K3c',
    appId: '1:325102932153:android:44ff1cf31a4f2ba9f0cb68',
    messagingSenderId: '325102932153',
    projectId: 'wallet-pro-2a36a',
    storageBucket: 'wallet-pro-2a36a.firebasestorage.app',
  );

  static FirebaseOptions get currentPlatform => android;
}
