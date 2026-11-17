import 'package:flutter/material.dart';

/// Réglages de la marque : changez ici le nom, le slogan ou la couleur.
class AppConfig {
  static const shopName = 'AICHA SERVICES MARKET';
  static const shortName = 'Aicha Services';
  static const tagline = 'Multi prestations • Imprimerie • Formation';
  static const logo = 'assets/logo.png';
  // Couleurs du logo
  static const green = Color(0xFF1E8B09);
  static const lightGreen = Color(0xFF36BE19);
  static const black = Color(0xFF111111);

  /// Identifiants (UID) des comptes « patron ». Ajouter un UID ici
  /// ET dans firestore.rules / storage.rules pour donner l'accès Gestion.
  static const adminUids = <String>{
    'JJj2RolSbmVlWc3n4qT6NvAhxZ63',
  };
}

const itemTypes = {
  'impression': 'Impression',
  'formation': 'Formation',
  'autre': 'Autres services',
};
