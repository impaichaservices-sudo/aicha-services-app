import 'package:firebase_core/firebase_core.dart';

/// Configuration Firebase du projet "aicha-services" (issue de google-services.json).
/// Ces valeurs ne sont pas secrètes : la sécurité des données est assurée par
/// les règles Firestore / Storage. Une valeur passée à la compilation avec
/// --dart-define (non vide) remplace la valeur par défaut.
class DefaultFirebaseOptions {
  static const _envApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const _envAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const _envSenderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const _envProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const _envBucket = String.fromEnvironment('FIREBASE_STORAGE_BUCKET');

  static String _or(String env, String fallback) => env.isEmpty ? fallback : env;

  static String get _apiKey =>
      _or(_envApiKey, 'AIzaSyBfFY0wJmsbrmkH9XHv-TXQiQ58t3HBias');
  static String get _appId =>
      _or(_envAppId, '1:19122348849:android:8fa5e132bc4cc543094610');
  static String get _senderId => _or(_envSenderId, '19122348849');
  static String get _projectId => _or(_envProjectId, 'aicha-services');
  static String get _bucket =>
      _or(_envBucket, 'aicha-services.firebasestorage.app');

  static bool get isConfigured =>
      _apiKey.isNotEmpty && _appId.isNotEmpty && _projectId.isNotEmpty;

  static FirebaseOptions get currentPlatform => FirebaseOptions(
        apiKey: _apiKey,
        appId: _appId,
        messagingSenderId: _senderId,
        projectId: _projectId,
        storageBucket: _bucket,
      );
}
