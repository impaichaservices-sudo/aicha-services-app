import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils.dart';

/// Un service du catalogue : impression, personnalisation, formation ou autre.
class CatalogItem {
  final String id;
  final String shopId;
  final String type;
  final String name;
  final String description;
  final String extraInfo; // informations supplémentaires
  final int price; // 0 = sur devis
  final String unit; // ex : "l'unité", "la page", "par personne"
  final bool fromPrice; // afficher « À partir de »
  final String imageUrl;
  final bool active; // visible dans l'appli
  final bool available; // Disponible / Indisponible
  final bool popular; // affiché dans « Services populaires »
  final bool requiresFile;
  final String schedule; // formation : dates / horaires
  final int places; // formation : places (0 = illimité)
  final int booked; // formation : places réservées
  final DateTime? createdAt;

  const CatalogItem({
    required this.id,
    required this.shopId,
    required this.type,
    required this.name,
    required this.description,
    required this.extraInfo,
    required this.price,
    required this.unit,
    required this.fromPrice,
    required this.imageUrl,
    required this.active,
    required this.available,
    required this.popular,
    required this.requiresFile,
    required this.schedule,
    required this.places,
    required this.booked,
    this.createdAt,
  });

  bool get onQuote => price <= 0;
  bool get isTraining => type == 'formation';
  bool get acceptsFile =>
      type == 'impression' || type == 'personnalisation' || requiresFile;
  int get placesLeft =>
      places > 0 ? (places - booked).clamp(0, places).toInt() : 0;
  bool get isFull => isTraining && places > 0 && placesLeft == 0;
  bool get canOrder => available && !isFull;

  String get priceLabel {
    if (onQuote) return 'Sur devis';
    final p = '${fromPrice ? 'À partir de ' : ''}${fcfa(price)}';
    return unit.isEmpty ? p : '$p / $unit';
  }

  String get shortPrice => onQuote ? 'Sur devis' : fcfa(price);

  factory CatalogItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? <String, dynamic>{};
    return CatalogItem(
      id: doc.id,
      shopId: (d['shopId'] ?? 'main') as String,
      type: (d['type'] ?? 'impression') as String,
      name: (d['name'] ?? '') as String,
      description: (d['description'] ?? '') as String,
      extraInfo: (d['extraInfo'] ?? '') as String,
      price: (d['price'] as num?)?.toInt() ?? 0,
      unit: (d['unit'] ?? '') as String,
      fromPrice: (d['fromPrice'] ?? false) as bool,
      imageUrl: (d['imageUrl'] ?? '') as String,
      active: (d['active'] ?? true) as bool,
      available: (d['available'] ?? true) as bool,
      popular: (d['popular'] ?? false) as bool,
      requiresFile: (d['requiresFile'] ?? false) as bool,
      schedule: (d['schedule'] ?? '') as String,
      places: (d['places'] as num?)?.toInt() ?? 0,
      booked: (d['booked'] as num?)?.toInt() ?? 0,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
