// Firebase iOS app configuration. These are public app identifiers.
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) return ios;
    throw UnsupportedError('이 설정은 iOS용이에요. 다른 플랫폼은 FlutterFire CLI로 설정해 주세요.');
  }

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: "AIzaSyBhMNhEhFqod5HRuinlwFmf370AujnrwpY",
    appId: "1:53834652270:ios:f61c8223586a75d1e2647f",
    messagingSenderId: "53834652270",
    projectId: "mwomeogeo",
    storageBucket: "mwomeogeo.firebasestorage.app",
    iosBundleId: "com.chaen.mwomeogeo",
  );
}
