import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'db.dart';

class AuthService {
  static final _auth = FirebaseAuth.instance;

  static Stream<User?> get changes => _auth.authStateChanges();
  static User? get current => _auth.currentUser;

  static Future<void> signIn(String email, String password) =>
      _auth.signInWithEmailAndPassword(email: email.trim(), password: password);

  static Future<void> register({
    required String name,
    required String phone,
    required String email,
    required String password,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await Db.users.doc(cred.user!.uid).set({
      'name': name.trim(),
      'phone': phone.trim(),
      'email': email.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> resetPassword(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());

  static Future<void> signOut() => _auth.signOut();

  static String message(Object e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'invalid-email':
          return 'Adresse e-mail invalide.';
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-credential':
          return 'E-mail ou mot de passe incorrect.';
        case 'email-already-in-use':
          return 'Un compte existe déjà avec cet e-mail.';
        case 'weak-password':
          return 'Mot de passe trop faible (6 caractères minimum).';
        case 'network-request-failed':
          return 'Pas de connexion Internet.';
        case 'too-many-requests':
          return 'Trop de tentatives. Réessayez plus tard.';
      }
      return e.message ?? 'Erreur de connexion.';
    }
    return 'Une erreur est survenue : $e';
  }
}
