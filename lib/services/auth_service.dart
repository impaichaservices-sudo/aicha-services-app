import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'db.dart';

/// Connexion par numéro de téléphone + mot de passe (sans SMS).
/// En coulisse, Firebase utilise la méthode "E-mail/Mot de passe" avec une
/// adresse interne construite à partir du numéro : 22370000000@clients.aichaservices.app
class AuthService {
  static final _auth = FirebaseAuth.instance;
  static const _domain = 'clients.aichaservices.app';

  static Stream<User?> get changes => _auth.authStateChanges();
  static User? get current => _auth.currentUser;

  /// "70 00 00 00" / "+223 70000000" / "0022370000000" -> "22370000000"
  static String normalizePhone(String input) {
    var d = input.replaceAll(RegExp(r'\D'), '');
    if (d.startsWith('00')) d = d.substring(2);
    if (d.length == 8) d = '223$d';
    return d;
  }

  static bool isValidPhone(String input) {
    final d = normalizePhone(input);
    return d.length >= 10 && d.length <= 15;
  }

  /// "22370000000" -> "+223 70 00 00 00"
  static String displayPhone(String input) {
    final d = normalizePhone(input);
    if (d.startsWith('223') && d.length == 11) {
      final n = d.substring(3);
      return '+223 ${n.substring(0, 2)} ${n.substring(2, 4)} '
          '${n.substring(4, 6)} ${n.substring(6, 8)}';
    }
    return '+$d';
  }

  static String _emailFor(String phone) => '${normalizePhone(phone)}@$_domain';

  static Future<void> signIn(String phone, String password) =>
      _auth.signInWithEmailAndPassword(
          email: _emailFor(phone), password: password);

  static Future<void> register({
    required String name,
    required String phone,
    required String password,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: _emailFor(phone),
      password: password,
    );
    await Db.users.doc(cred.user!.uid).set({
      'name': name.trim(),
      'phone': displayPhone(phone),
      'email': '',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> signOut() => _auth.signOut();

  static String message(Object e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'invalid-email':
          return 'Numéro de téléphone invalide.';
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-credential':
          return 'Numéro ou mot de passe incorrect.';
        case 'email-already-in-use':
          return 'Un compte existe déjà avec ce numéro. Connectez-vous.';
        case 'weak-password':
          return 'Mot de passe trop faible (6 caractères minimum).';
        case 'network-request-failed':
          return 'Pas de connexion Internet.';
        case 'too-many-requests':
          return 'Trop de tentatives. Réessayez plus tard.';
        case 'operation-not-allowed':
          return 'Connexion non activée dans Firebase (voir le guide).';
      }
      return e.message ?? 'Erreur de connexion.';
    }
    return 'Une erreur est survenue : $e';
  }
}
