// Opciones de Firebase del proyecto "ridder-f7fb3".
// Generado a partir de android/app/google-services.json e
// ios/Runner/GoogleService-Info.plist. Si cambiás de proyecto Firebase,
// regeneralo con `flutterfire configure`.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDGanMck06iaTsODsHdhzVnSlsa3jBM1iI',
    appId: '1:552795712818:android:7baab0051f16c68446bb2b',
    messagingSenderId: '552795712818',
    projectId: 'ridder-f7fb3',
    storageBucket: 'ridder-f7fb3.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAUsoCC57i9iMxLqa3wCJJOl7xCMOapW8g',
    appId: '1:552795712818:ios:d69c14bda3a7c8d546bb2b',
    messagingSenderId: '552795712818',
    projectId: 'ridder-f7fb3',
    storageBucket: 'ridder-f7fb3.firebasestorage.app',
    iosBundleId: 'com.ridder.manager',
  );
}
