import 'package:cloud_firestore/cloud_firestore.dart';

import '../config.dart';
import '../models/app_user.dart';
import '../models/catalog_item.dart';
import '../models/chat.dart';
import '../models/order.dart';
import '../models/promotion.dart';
import '../models/shop_settings.dart';

/// Accès à la base Firestore.
/// Les tris se font dans l'application pour éviter de créer des index composites.
class Db {
  static final _fs = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get users =>
      _fs.collection('users');
  static CollectionReference<Map<String, dynamic>> get admins =>
      _fs.collection('admins');
  static CollectionReference<Map<String, dynamic>> get catalog =>
      _fs.collection('catalog');
  static CollectionReference<Map<String, dynamic>> get orders =>
      _fs.collection('orders');
  static CollectionReference<Map<String, dynamic>> get promotions =>
      _fs.collection('promotions');
  static CollectionReference<Map<String, dynamic>> get conversations =>
      _fs.collection('conversations');
  static DocumentReference<Map<String, dynamic>> get settingsDoc =>
      _fs.collection('settings').doc('shop');
  static DocumentReference<Map<String, dynamic>> get orderCounter =>
      _fs.collection('counters').doc('orders');

  static int _newestFirst(DateTime? a, DateTime? b) =>
      (b ?? DateTime(2100)).compareTo(a ?? DateTime(2100));

  // ---------------- Utilisateurs ----------------
  static Stream<AppUser?> userStream(String uid) => users
      .doc(uid)
      .snapshots()
      .map((d) => d.exists ? AppUser.fromDoc(d) : null);

  static Stream<List<AppUser>> allUsers() => users.snapshots().map((s) =>
      s.docs.map(AppUser.fromDoc).toList()
        ..sort((a, b) => _newestFirst(a.createdAt, b.createdAt)));

  static Future<void> updateProfile(String uid, Map<String, dynamic> data) =>
      users.doc(uid).set(data, SetOptions(merge: true));

  /// Super Admin = UID inscrit dans config.dart, ou document admins/{uid}.
  static Stream<bool> isAdmin(String uid) => AppConfig.adminUids.contains(uid)
      ? Stream<bool>.value(true)
      : admins
          .doc(uid)
          .snapshots()
          .map((d) => d.exists)
          .handleError((_) => false);

  // ---------------- Réglages boutique ----------------
  static Stream<ShopSettings> settings() =>
      settingsDoc.snapshots().map(ShopSettings.fromDoc);

  static Future<void> saveSettings(ShopSettings s) =>
      settingsDoc.set(s.toMap(), SetOptions(merge: true));

  // ---------------- Catalogue ----------------
  static Stream<List<CatalogItem>> catalogItems({bool onlyActive = true}) {
    Query<Map<String, dynamic>> q = catalog;
    if (onlyActive) q = q.where('active', isEqualTo: true);
    return q.snapshots().map((s) => s.docs.map(CatalogItem.fromDoc).toList()
      ..sort((a, b) => _newestFirst(a.createdAt, b.createdAt)));
  }

  static Future<CatalogItem?> catalogItem(String id) async {
    final d = await catalog.doc(id).get();
    return d.exists ? CatalogItem.fromDoc(d) : null;
  }

  // ---------------- Offres / nouveautés ----------------
  static Stream<List<Promotion>> allPromotions() => promotions.snapshots().map(
      (s) => s.docs.map(Promotion.fromDoc).toList()
        ..sort((a, b) => _newestFirst(a.createdAt, b.createdAt)));

  static Stream<List<Promotion>> livePromotions() => allPromotions()
      .map((l) => l.where((p) => p.isLive).toList());

  // ---------------- Commandes ----------------
  static Stream<List<ShopOrder>> buyerOrders(String uid) => orders
      .where('buyerId', isEqualTo: uid)
      .snapshots()
      .map((s) => s.docs.map(ShopOrder.fromDoc).toList()
        ..sort((a, b) => _newestFirst(a.createdAt, b.createdAt)));

  static Stream<List<ShopOrder>> allOrders() => orders
      .orderBy('createdAt', descending: true)
      .limit(300)
      .snapshots()
      .map((s) => s.docs.map(ShopOrder.fromDoc).toList());

  static Stream<ShopOrder?> orderStream(String id) => orders
      .doc(id)
      .snapshots()
      .map((d) => d.exists ? ShopOrder.fromDoc(d) : null);

  /// Crée la commande avec un numéro AS-00001, AS-00002… et réserve les
  /// places des formations, en une seule opération.
  static Future<String> createOrder(ShopOrder o,
      {Map<String, int> bookings = const {}}) {
    return _fs.runTransaction<String>((tx) async {
      final counter = await tx.get(orderCounter);
      final next = ((counter.data()?['next'] as num?)?.toInt() ?? 0) + 1;
      final ref = orders.doc();
      tx.set(orderCounter, {'next': next});
      tx.set(ref, {
        ...o.toNewMap(),
        'number': 'AS-${next.toString().padLeft(5, '0')}',
      });
      for (final e in bookings.entries) {
        tx.update(catalog.doc(e.key), {'booked': FieldValue.increment(e.value)});
      }
      return ref.id;
    });
  }

  /// Change le statut et prévient le client dans la discussion de la commande.
  static Future<void> setOrderStatus(ShopOrder o, String status,
      {String senderId = '', String senderName = ''}) async {
    await orders.doc(o.id).update({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    final msg = orderStatusMessages[status];
    if (msg != null && senderId.isNotEmpty) {
      await sendMessage(
        conversationId: orderConversationId(o.id),
        createIfMissing: orderConversationData(o),
        senderId: senderId,
        senderRole: 'shop',
        senderName: senderName,
        text: 'Commande ${o.displayNumber} : $msg',
        type: 'system',
      );
    }
  }

  static Future<void> cancelOrder(String orderId) => orders.doc(orderId).update({
        'status': 'annulee',
        'updatedAt': FieldValue.serverTimestamp(),
      });

  static Future<void> setQuote(String orderId, int amount, String note) =>
      orders.doc(orderId).update({
        'quotedTotal': amount,
        'adminNote': note,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  // ---------------- Discussions ----------------
  static String generalConversationId(String clientUid) => 'c_$clientUid';
  static String orderConversationId(String orderId) => 'o_$orderId';

  static Map<String, dynamic> generalConversationData(AppUser u) => {
        'shopId': u.shopId,
        'clientId': u.uid,
        'clientName': u.name,
        'clientPhone': u.phone,
        'orderId': '',
        'orderNumber': '',
        'title': 'Équipe ${AppConfig.shopName}',
      };

  static Map<String, dynamic> orderConversationData(ShopOrder o) => {
        'shopId': o.shopId,
        'clientId': o.buyerId,
        'clientName': o.buyerName,
        'clientPhone': o.phone,
        'orderId': o.id,
        'orderNumber': o.displayNumber,
        'title': 'Commande ${o.displayNumber}',
      };

  static Stream<List<Conversation>> clientConversations(String uid) =>
      conversations.where('clientId', isEqualTo: uid).snapshots().map((s) =>
          s.docs.map(Conversation.fromDoc).toList()
            ..sort((a, b) => _newestFirst(a.lastAt, b.lastAt)));

  static Stream<List<Conversation>> allConversations() => conversations
      .orderBy('lastAt', descending: true)
      .limit(300)
      .snapshots()
      .map((s) => s.docs.map(Conversation.fromDoc).toList());

  static Stream<Conversation?> conversationStream(String id) => conversations
      .doc(id)
      .snapshots()
      .map((d) => d.exists ? Conversation.fromDoc(d) : null);

  static Stream<List<ChatMessage>> messages(String conversationId) =>
      conversations
          .doc(conversationId)
          .collection('messages')
          .orderBy('createdAt')
          .limitToLast(300)
          .snapshots()
          .map((s) => s.docs.map(ChatMessage.fromDoc).toList());

  /// Envoie un message ; crée la conversation si besoin (même opération).
  static Future<void> sendMessage({
    required String conversationId,
    required Map<String, dynamic> createIfMissing,
    required String senderId,
    required String senderRole,
    required String senderName,
    required String text,
    String type = 'text',
    String itemId = '',
    String itemName = '',
    String fileUrl = '',
    String fileName = '',
  }) async {
    final convRef = conversations.doc(conversationId);
    final exists = (await convRef.get()).exists;
    final batch = _fs.batch();
    final preview = type == 'service'
        ? 'Service proposé : $itemName'
        : type == 'file'
            ? 'Fichier : $fileName'
            : text;
    final convUpdate = <String, dynamic>{
      'lastMessage': preview.length > 120 ? '${preview.substring(0, 120)}…' : preview,
      'lastAt': FieldValue.serverTimestamp(),
      if (senderRole == 'client') 'unreadForShop': FieldValue.increment(1),
      if (senderRole == 'shop') 'unreadForClient': FieldValue.increment(1),
    };
    if (exists) {
      batch.update(convRef, convUpdate);
    } else {
      batch.set(convRef, {
        ...createIfMissing,
        'unreadForClient': 0,
        'unreadForShop': 0,
        'createdAt': FieldValue.serverTimestamp(),
        ...convUpdate,
      });
    }
    batch.set(convRef.collection('messages').doc(), {
      'senderId': senderId,
      'senderRole': senderRole,
      'senderName': senderName,
      'type': type,
      'text': text,
      'itemId': itemId,
      'itemName': itemName,
      'fileUrl': fileUrl,
      'fileName': fileName,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  /// Remet à zéro le compteur de messages non lus (côté client ou boutique).
  static Future<void> markRead(String conversationId, {required bool asShop}) =>
      conversations
          .doc(conversationId)
          .update({asShop ? 'unreadForShop' : 'unreadForClient': 0})
          .catchError((_) {});
}
