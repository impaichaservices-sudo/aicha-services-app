import 'package:firebase_core/firebase_core.dart';

/// Les clés Firebase sont injectées au moment de la compilation
/// (--dart-define), depuis les "Secrets" GitHub. Rien de secret dans le code.
class DefaultFirebaseOptions {
  static const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const _appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const _senderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const _bucket = String.fromEnvironment('FIREBASE_STORAGE_BUCKET');

  static bool get isConfigured =>
      _apiKey.isNotEmpty && _appId.isNotEmpty && _projectId.isNotEmpty;

  static FirebaseOptions get currentPlatform => FirebaseOptions(
        apiKey: _apiKey,
        appId: _appId,
        messagingSenderId: _senderId,
        projectId: _projectId,
        storageBucket: _bucket.isEmpty ? null : _bucket,
      );
}
