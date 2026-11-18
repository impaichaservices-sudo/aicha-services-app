import 'package:cloud_firestore/cloud_firestore.dart';

/// Fichier envoyé (photo, PDF, Word…) rattaché à une discussion / commande.
class FileRecord {
  final String id;
  final String ownerId;
  final String shopId;
  final String conversationId;
  final String orderId;
  final String name;
  final String url;
  final int size;
  final DateTime? createdAt;

  const FileRecord({
    required this.id,
    required this.ownerId,
    required this.shopId,
    required this.conversationId,
    required this.orderId,
    required this.name,
    required this.url,
    required this.size,
    this.createdAt,
  });

  factory FileRecord.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? <String, dynamic>{};
    return FileRecord(
      id: doc.id,
      ownerId: (d['ownerId'] ?? '') as String,
      shopId: (d['shopId'] ?? '') as String,
      conversationId: (d['conversationId'] ?? '') as String,
      orderId: (d['orderId'] ?? '') as String,
      name: (d['name'] ?? '') as String,
      url: (d['url'] ?? '') as String,
      size: (d['size'] as num?)?.toInt() ?? 0,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
