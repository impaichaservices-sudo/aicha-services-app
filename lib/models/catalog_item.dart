import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils.dart';

/// Un service du catalogue : impression, formation ou autre.
class CatalogItem {
  final String id;
  final String type; // 'impression' | 'formation' | 'autre'
  final String name;
  final String description;
  final int price; // 0 = sur devis
  final String unit; // ex : "l'unité", "la page", "par personne"
  final String imageUrl;
  final bool active;
  final bool requiresFile; // le client doit joindre un fichier
  final String schedule; // formation : dates / horaires
  final int places; // formation : places disponibles (0 = illimité)
  final DateTime? createdAt;

  const CatalogItem({
    required this.id,
    required this.type,
    required this.name,
    required this.description,
    required this.price,
    required this.unit,
    required this.imageUrl,
    required this.active,
    required this.requiresFile,
    required this.schedule,
    required this.places,
    this.createdAt,
  });

  bool get onQuote => price <= 0;
  bool get isTraining => type == 'formation';
  bool get acceptsFile => type == 'impression' || requiresFile;

  String get priceLabel => onQuote
      ? 'Sur devis'
      : '${fcfa(price)}${unit.isEmpty ? '' : ' / $unit'}';

  factory CatalogItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? <String, dynamic>{};
    return CatalogItem(
      id: doc.id,
      type: (d['type'] ?? 'impression') as String,
      name: (d['name'] ?? '') as String,
      description: (d['description'] ?? '') as String,
      price: (d['price'] as num?)?.toInt() ?? 0,
      unit: (d['unit'] ?? '') as String,
      imageUrl: (d['imageUrl'] ?? '') as String,
      active: (d['active'] ?? true) as bool,
      requiresFile: (d['requiresFile'] ?? false) as bool,
      schedule: (d['schedule'] ?? '') as String,
      places: (d['places'] as num?)?.toInt() ?? 0,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
