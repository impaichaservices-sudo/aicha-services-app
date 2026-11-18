import 'package:cloud_firestore/cloud_firestore.dart';

/// Notification enregistrée dans l'application (cloche 🔔), en plus de la
/// notification push du téléphone.
/// audience 'client' : pour un client (toUid) ;
/// audience 'staff'  : pour l'équipe d'une boutique (shopId) et le Super Admin.
class InboxItem {
  final String id;
  final String audience;
  final String toUid;
  final String shopId;
  final String title;
  final String body;
  final Map<String, String> data;
  final DateTime? createdAt;

  const InboxItem({
    required this.id,
    required this.audience,
    required this.toUid,
    required this.shopId,
    required this.title,
    required this.body,
    required this.data,
    required this.createdAt,
  });

  String get type => data['type'] ?? '';

  bool isNewerThan(DateTime? seen) =>
      createdAt == null || seen == null || createdAt!.isAfter(seen);

  factory InboxItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? <String, dynamic>{};
    final raw = d['data'];
    return InboxItem(
      id: doc.id,
      audience: (d['audience'] ?? 'client') as String,
      toUid: (d['toUid'] ?? '') as String,
      shopId: (d['shopId'] ?? 'main') as String,
      title: (d['title'] ?? '') as String,
      body: (d['body'] ?? '') as String,
      data: raw is Map
          ? raw.map((k, v) => MapEntry(k.toString(), v.toString()))
          : <String, String>{},
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
