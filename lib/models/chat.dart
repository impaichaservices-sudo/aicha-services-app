import 'package:cloud_firestore/cloud_firestore.dart';

/// Une conversation entre un client et l'équipe AÏCHA SERVICES.
/// - générale : id "c_<uid du client>"
/// - liée à une commande : id "o_<id de la commande>"
class Conversation {
  final String id;
  final String shopId;
  final String clientId;
  final String clientName;
  final String clientPhone;
  final String orderId;
  final String orderNumber;
  final String title;
  final String lastMessage;
  final DateTime? lastAt;
  final int unreadForClient;
  final int unreadForShop;

  const Conversation({
    required this.id,
    required this.shopId,
    required this.clientId,
    required this.clientName,
    required this.clientPhone,
    required this.orderId,
    required this.orderNumber,
    required this.title,
    required this.lastMessage,
    required this.lastAt,
    required this.unreadForClient,
    required this.unreadForShop,
  });

  bool get isOrder => orderId.isNotEmpty;

  factory Conversation.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? <String, dynamic>{};
    return Conversation(
      id: doc.id,
      shopId: (d['shopId'] ?? 'main') as String,
      clientId: (d['clientId'] ?? '') as String,
      clientName: (d['clientName'] ?? '') as String,
      clientPhone: (d['clientPhone'] ?? '') as String,
      orderId: (d['orderId'] ?? '') as String,
      orderNumber: (d['orderNumber'] ?? '') as String,
      title: (d['title'] ?? '') as String,
      lastMessage: (d['lastMessage'] ?? '') as String,
      lastAt: (d['lastAt'] as Timestamp?)?.toDate(),
      unreadForClient: (d['unreadForClient'] as num?)?.toInt() ?? 0,
      unreadForShop: (d['unreadForShop'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Un message. type : 'text' | 'service' (carte « Commander ce service »)
/// | 'file' (fichier, étape 3) | 'system' (changement de statut).
class ChatMessage {
  final String id;
  final String senderId;
  final String senderRole; // 'client' | 'shop'
  final String senderName;
  final String type;
  final String text;
  final String itemId;
  final String itemName;
  final String fileUrl;
  final String fileName;
  final DateTime? createdAt;

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderRole,
    required this.senderName,
    required this.type,
    required this.text,
    required this.itemId,
    required this.itemName,
    required this.fileUrl,
    required this.fileName,
    required this.createdAt,
  });

  bool get fromShop => senderRole == 'shop';

  factory ChatMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? <String, dynamic>{};
    return ChatMessage(
      id: doc.id,
      senderId: (d['senderId'] ?? '') as String,
      senderRole: (d['senderRole'] ?? 'client') as String,
      senderName: (d['senderName'] ?? '') as String,
      type: (d['type'] ?? 'text') as String,
      text: (d['text'] ?? '') as String,
      itemId: (d['itemId'] ?? '') as String,
      itemName: (d['itemName'] ?? '') as String,
      fileUrl: (d['fileUrl'] ?? '') as String,
      fileName: (d['fileName'] ?? '') as String,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
