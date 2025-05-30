import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAny1rNZ7D52rrmfKdB6nKVzET7g_9HzVw',
    appId: '1:221130199477:web:1ceb76b13e536123af49fc',
    messagingSenderId: '221130199477',
    projectId: 'psadb-91239',
    authDomain: 'psadb-91239.firebaseapp.com',
    storageBucket: 'psadb-91239.firebasestorage.app',
    measurementId: 'G-8DE08FFRC5',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAspDiiVoO43wKWNRGCNnoADNoOJBF-bsE',
    appId: '1:221130199477:android:52b26bddc8b33c53af49fc',
    messagingSenderId: '221130199477',
    projectId: 'psadb-91239',
    storageBucket: 'psadb-91239.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAFa9BdARMFwavbgVNWzw4U3OFJg-NXcKI',
    appId: '1:221130199477:ios:5f516b0070294592af49fc',
    messagingSenderId: '221130199477',
    projectId: 'psadb-91239',
    storageBucket: 'psadb-91239.firebasestorage.app',
    iosBundleId: 'com.example.testProject',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyAFa9BdARMFwavbgVNWzw4U3OFJg-NXcKI',
    appId: '1:221130199477:ios:5f516b0070294592af49fc',
    messagingSenderId: '221130199477',
    projectId: 'psadb-91239',
    storageBucket: 'psadb-91239.firebasestorage.app',
    iosBundleId: 'com.example.testProject',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyAny1rNZ7D52rrmfKdB6nKVzET7g_9HzVw',
    appId: '1:221130199477:web:935d64952ffaf89caf49fc',
    messagingSenderId: '221130199477',
    projectId: 'psadb-91239',
    authDomain: 'psadb-91239.firebaseapp.com',
    storageBucket: 'psadb-91239.firebasestorage.app',
    measurementId: 'G-TBS96TH3WV',
  );
}
