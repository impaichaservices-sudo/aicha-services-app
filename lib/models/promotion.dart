import 'package:cloud_firestore/cloud_firestore.dart';

/// Une offre affichée dans « Nos offres » : promotion, nouveauté, annonce…
class Promotion {
  final String id;
  final String kind;
  final String title;
  final String description;
  final String imageUrl;
  final String itemId; // service lié (facultatif)
  final DateTime? start;
  final DateTime? end;
  final bool active;
  final DateTime? createdAt;

  const Promotion({
    required this.id,
    required this.kind,
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.itemId,
    required this.start,
    required this.end,
    required this.active,
    this.createdAt,
  });

  /// Visible aujourd'hui ?
  bool get isLive {
    if (!active) return false;
    final now = DateTime.now();
    if (start != null && now.isBefore(start!)) return false;
    if (end != null && now.isAfter(end!.add(const Duration(days: 1)))) {
      return false;
    }
    return true;
  }

  factory Promotion.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? <String, dynamic>{};
    return Promotion(
      id: doc.id,
      kind: (d['kind'] ?? 'annonce') as String,
      title: (d['title'] ?? '') as String,
      description: (d['description'] ?? '') as String,
      imageUrl: (d['imageUrl'] ?? '') as String,
      itemId: (d['itemId'] ?? '') as String,
      start: (d['start'] as Timestamp?)?.toDate(),
      end: (d['end'] as Timestamp?)?.toDate(),
      active: (d['active'] ?? true) as bool,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
