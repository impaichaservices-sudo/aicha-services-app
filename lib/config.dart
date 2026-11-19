import 'package:flutter/material.dart';

/// Identité AÏCHA SERVICES : nom, slogan, couleurs, logo.
class AppConfig {
  static const shopName = 'AÏCHA SERVICES';
  static const fullName = 'AÏCHA SERVICES MARKET';
  static const shortName = 'Aïcha Services';
  static const slogan = 'Votre satisfaction est notre engagement';
  /// Nom de version affiché aux utilisateurs (fixe pendant la phase de test).
  /// Le numéro interne de compilation, lui, augmente à chaque mise à jour
  /// (obligatoire pour Android) mais n'est plus affiché.
  static const versionName = '1.0 (bêta)';
  static const tagline = 'Impression • Personnalisation • Formation';
  static const logo = 'assets/logo.png';

  // Couleurs du logo
  static const green = Color(0xFF1E8B09);
  static const lightGreen = Color(0xFF36BE19);
  static const paleGreen = Color(0xFFEAF6E5);
  static const black = Color(0xFF111111);

  /// Boutique par défaut (le multi-boutiques arrive à l'étape 2).
  static const defaultShopId = 'main';

  /// Identifiants (UID) des comptes Super Admin. Ajouter un UID ici
  /// ET dans firestore.rules pour donner l'accès Gestion.
  static const adminUids = <String>{
    'JJj2RolSbmVlWc3n4qT6NvAhxZ63',
  };

  static const about =
      'AÏCHA SERVICES est une entreprise multi-prestations : impression, '
      'personnalisation (t-shirts, maillots, objets), formations et autres '
      'services. Commandez depuis l\'application, discutez avec notre équipe '
      'et suivez votre commande jusqu\'à la livraison ou au retrait.';
}

/// Catégories de services.
const itemTypes = {
  'impression': 'Impression',
  'personnalisation': 'Personnalisation',
  'formation': 'Formation',
  'autre': 'Autres services',
};

const itemTypeIcons = <String, IconData>{
  'impression': Icons.print_rounded,
  'personnalisation': Icons.checkroom_rounded,
  'formation': Icons.school_rounded,
  'autre': Icons.design_services_rounded,
};

/// Types d'offres affichées dans « Nos offres ».
const promoKinds = {
  'promotion': 'Promotion',
  'reduction': 'Réduction',
  'nouveau_service': 'Nouveau service',
  'nouvelle_formation': 'Nouvelle formation',
  'annonce': 'Annonce',
};
