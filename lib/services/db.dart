import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../config.dart';
import '../models/app_user.dart';
import '../models/catalog_item.dart';
import '../models/chat.dart';
import '../models/file_record.dart';
import '../models/inbox_item.dart';
import '../models/order.dart';
import '../models/promotion.dart';
import '../models/shop.dart';
import '../models/shop_settings.dart';
import '../models/staff.dart';
import 'notify_service.dart';
import 'offline_queue.dart';

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
  static CollectionReference<Map<String, dynamic>> get shops =>
      _fs.collection('shops');
  static CollectionReference<Map<String, dynamic>> get staff =>
      _fs.collection('staff');
  static CollectionReference<Map<String, dynamic>> get files =>
      _fs.collection('files');
  static CollectionReference<Map<String, dynamic>> get notifications =>
      _fs.collection('notifications');
  static CollectionReference<Map<String, dynamic>> get inbox =>
      _fs.collection('inbox');
  static DocumentReference<Map<String, dynamic>> counterFor(String shopId) =>
      _fs.collection('counters').doc(shopId == 'main' ? 'orders' : shopId);

  static int _newestFirst(DateTime? a, DateTime? b) =>
      (b ?? DateTime(2100)).compareTo(a ?? DateTime(2100));

  // ---------------- Utilisateurs ----------------
  static Stream<AppUser?> userStream(String uid) => users
      .doc(uid)
      .snapshots()
      .map((d) => d.exists ? AppUser.fromDoc(d) : null);

  /// Nombre de comptes, sans télécharger toute la liste (économise le quota).
  static Future<int> usersCount() async {
    try {
      final r = await users.count().get();
      return r.count ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Supprime les notifications de la cloche de plus de 30 jours.
  static Future<void> cleanOldInbox(String uid) async {
    try {
      final limit = DateTime.now().subtract(const Duration(days: 30));
      final all = await inbox.where('toUid', isEqualTo: uid).limit(300).get();
      for (final d in all.docs) {
        final at = d.data()['createdAt'];
        if (at is Timestamp && at.toDate().isBefore(limit)) {
          await d.reference.delete();
        }
      }
    } catch (_) {}
  }

  static Stream<List<AppUser>> allUsers({int limit = 300}) =>
      users.limit(limit).snapshots().map((s) =>
      s.docs.map(AppUser.fromDoc).toList()
        ..sort((a, b) => _newestFirst(a.createdAt, b.createdAt)));

  static Stream<List<AppUser>> shopUsers(String shopId, {int limit = 300}) => users
      .where('shopId', isEqualTo: shopId)
      .limit(limit)
      .snapshots()
      .map((s) => s.docs.map(AppUser.fromDoc).toList()
        ..sort((a, b) => _newestFirst(a.createdAt, b.createdAt)));

  /// Trouve un compte par numéro de téléphone (pour l'ajouter à l'équipe).
  static Future<AppUser?> userByPhone(String displayPhone) async {
    final q = await users.where('phone', isEqualTo: displayPhone).limit(1).get();
    return q.docs.isEmpty ? null : AppUser.fromDoc(q.docs.first);
  }

  // ---------------- Mots de passe oubliés ----------------
  static CollectionReference<Map<String, dynamic>> get resetRequests =>
      _fs.collection('resetRequests');

  /// Demande envoyée depuis l'écran de connexion (sans être connecté).
  static Future<void> addResetRequest(
          {required String phone, required String name, required String message}) =>
      resetRequests.add({
        'phone': phone,
        'name': name,
        'message': message,
        'status': 'en_attente',
        'createdAt': FieldValue.serverTimestamp(),
      });

  /// Demandes en attente (Super Admin).
  static Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> pendingResets() =>
      resetRequests
          .where('status', isEqualTo: 'en_attente')
          .snapshots()
          .map((s) => s.docs);

  static Future<void> closeReset(String id, String by) => resetRequests
      .doc(id)
      .update({'status': 'traitee', 'doneBy': by, 'doneAt': FieldValue.serverTimestamp()});

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

  // ---------------- Boutiques ----------------
  static Stream<List<Shop>> allShops() => shops.snapshots().map((s) =>
      s.docs.map(Shop.fromDoc).toList()..sort((a, b) => a.name.compareTo(b.name)));

  static Future<void> saveShop(String? id, Map<String, dynamic> data) => id == null
      ? shops.add({...data, 'createdAt': FieldValue.serverTimestamp()})
      : shops.doc(id).set(data, SetOptions(merge: true));

  // ---------------- Équipe (responsables, agents) ----------------
  static Stream<StaffMember?> staffStream(String uid) => staff
      .doc(uid)
      .snapshots()
      .map((d) => d.exists ? StaffMember.fromDoc(d) : null)
      .handleError((_) {});

  static Stream<List<StaffMember>> allStaff({String? shopId}) {
    Query<Map<String, dynamic>> q = staff;
    if (shopId != null) q = q.where('shopId', isEqualTo: shopId);
    return q.snapshots().map((s) => s.docs.map(StaffMember.fromDoc).toList()
      ..sort((a, b) => a.name.compareTo(b.name)));
  }

  static Future<void> saveStaff(StaffMember m) =>
      staff.doc(m.uid).set(m.toMap());

  static Future<void> removeStaff(String uid) => staff.doc(uid).delete();

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

  /// Toutes les commandes (Super Admin) ou celles d'une boutique (équipe).
  static Stream<List<ShopOrder>> allOrders({String? shopId}) {
    if (shopId != null) {
      return orders.where('shopId', isEqualTo: shopId).snapshots().map((s) =>
          s.docs.map(ShopOrder.fromDoc).toList()
            ..sort((a, b) => _newestFirst(a.createdAt, b.createdAt)));
    }
    return orders
        .orderBy('createdAt', descending: true)
        .limit(500)
        .snapshots()
        .map((s) => s.docs.map(ShopOrder.fromDoc).toList());
  }

  static Stream<ShopOrder?> orderStream(String id) => orders
      .doc(id)
      .snapshots()
      .map((d) => d.exists ? ShopOrder.fromDoc(d) : null);

  /// Crée la commande avec un numéro AS-00001, AS-00002… et réserve les
  /// places des formations, en une seule opération.
  static Future<String> createOrder(ShopOrder o,
      {Map<String, int> bookings = const {},
      String shopCode = '',
      String orderId = ''}) async {
    final id = orderId.isEmpty ? orders.doc().id : orderId;
    await createOrderFromMap(
        orderId: id, data: o.toNewMap(), bookings: bookings, shopCode: shopCode);
    return id;
  }

  /// Identifiant d'une nouvelle commande (choisi avant l'envoi, pour pouvoir
  /// la renvoyer sans doublon après une coupure).
  static String newOrderId() => orders.doc().id;

  /// Crée la commande (numéro AS-00001…). Si elle existe déjà (envoi déjà
  /// passé avant une coupure), rien n'est recréé. Renvoie le numéro.
  static Future<String> createOrderFromMap({
    required String orderId,
    required Map<String, dynamic> data,
    Map<String, int> bookings = const {},
    String shopCode = '',
  }) async {
    final shopId = (data['shopId'] ?? 'main').toString();
    final counterRef = counterFor(shopId);
    final orderRef = orders.doc(orderId);
    var created = false;
    final number = await _fs.runTransaction<String>((tx) async {
      final existing = await tx.get(orderRef);
      if (existing.exists) return (existing.data()?['number'] ?? '') as String;
      final counter = await tx.get(counterRef);
      final next = ((counter.data()?['next'] as num?)?.toInt() ?? 0) + 1;
      final n = shopCode.isEmpty
          ? 'AS-${next.toString().padLeft(5, '0')}'
          : 'AS-$shopCode-${next.toString().padLeft(5, '0')}';
      tx.set(counterRef, {'next': next});
      tx.set(orderRef, {
        ...data,
        'createdAt': FieldValue.serverTimestamp(),
        'number': n,
      });
      for (final e in bookings.entries) {
        tx.update(catalog.doc(e.key),
            {'booked': FieldValue.increment(e.value), 'lastOrderId': orderId});
      }
      created = true;
      return n;
    });
    if (!created) return number;
    final buyerName = (data['buyerName'] ?? 'Client').toString();
    final items = ((data['items'] as List?) ?? const [])
        .map((e) => (e as Map)['name']?.toString() ?? '')
        .where((e) => e.isNotEmpty)
        .join(', ');
    NotifyService.toStaff(
      shopId: shopId,
      title: 'Nouvelle commande $number',
      body: '$buyerName • $items',
      data: {'type': 'order', 'orderId': orderId},
    );
    // Premier événement de la discussion de la commande
    try {
      await sendMessage(
        conversationId: orderConversationId(orderId),
        createIfMissing: {
          'shopId': shopId,
          'clientId': (data['buyerId'] ?? '').toString(),
          'clientName': buyerName,
          'clientPhone': (data['phone'] ?? '').toString(),
          'orderId': orderId,
          'orderNumber': number,
          'title': 'Commande $number',
        },
        senderId: (data['buyerId'] ?? '').toString(),
        senderRole: 'client',
        senderName: buyerName,
        text: '🧾 Commande $number créée. L\'équipe va la confirmer.',
        type: 'system',
        notify: false,
      );
    } catch (_) {}
    return number;
  }

  /// Change le statut et prévient le client dans la discussion de la commande.
  static Future<void> setOrderStatus(ShopOrder o, String status,
      {String senderId = '', String senderName = '', String agentName = ''}) async {
    await orders.doc(o.id).update({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
      if (senderId.isNotEmpty) 'handledBy': senderId,
      if (agentName.isNotEmpty) 'handledByName': agentName,
    });
    final msg = orderStatusMessages[status];
    if (msg != null && senderId.isNotEmpty) {
      try {
        await sendMessage(
          conversationId: orderConversationId(o.id),
          createIfMissing: orderConversationData(o),
          senderId: senderId,
          senderRole: 'shop',
          senderName: senderName,
          text: 'Commande ${o.displayNumber} : $msg',
          type: 'system',
          notify: false,
        );
      } catch (_) {
        // discussion attribuée à un autre agent : le client est quand même prévenu
      }
      NotifyService.toUser(
        uid: o.buyerId,
        kind: 'orders',
        title: 'AÏCHA SERVICES',
        body: 'Votre commande #${o.displayNumber} : $msg',
        data: {'type': 'order', 'orderId': o.id},
      );
    }
  }

  static Future<void> cancelOrder(String orderId) => orders.doc(orderId).update({
        'status': 'annulee',
        'updatedAt': FieldValue.serverTimestamp(),
      });

  static Future<void> setQuote(String orderId, int amount, String note,
          {String agentId = '', String agentName = ''}) =>
      orders.doc(orderId).update({
        'quotedTotal': amount,
        'adminNote': note,
        if (agentId.isNotEmpty) 'handledBy': agentId,
        if (agentName.isNotEmpty) 'handledByName': agentName,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  // ---------------- Discussions ----------------
  static String generalConversationId(String clientUid) => 'c_$clientUid';
  static String orderConversationId(String orderId) => 'o_$orderId';

  static Map<String, dynamic> generalConversationData(AppUser u,
          {String? shopId}) =>
      {
        'shopId': shopId ?? u.shopId,
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

  static Stream<List<Conversation>> allConversations(
      {String? shopId, String? agentUid}) {
    if (agentUid != null) {
      // Agent : ses discussions + les nouvelles pas encore attribuées.
      final base = conversations.where('shopId', isEqualTo: shopId ?? 'main');
      final mine = base.where('assignedTo', isEqualTo: agentUid).snapshots();
      final free = base.where('assignedTo', isEqualTo: '').snapshots();
      return _merge2(mine, free).map((pair) {
        final map = <String, Conversation>{};
        for (final s in pair) {
          for (final d in s.docs) {
            map[d.id] = Conversation.fromDoc(d);
          }
        }
        return map.values.toList()
          ..sort((a, b) => _newestFirst(a.lastAt, b.lastAt));
      });
    }
    if (shopId != null) {
      return conversations.where('shopId', isEqualTo: shopId).snapshots().map(
          (s) => s.docs.map(Conversation.fromDoc).toList()
            ..sort((a, b) => _newestFirst(a.lastAt, b.lastAt)));
    }
    return conversations
        .orderBy('lastAt', descending: true)
        .limit(500)
        .snapshots()
        .map((s) => s.docs.map(Conversation.fromDoc).toList());
  }

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
          .snapshots(includeMetadataChanges: true)
          .map((s) => s.docs.map(ChatMessage.fromDoc).toList());

  /// Combine deux flux : renvoie les deux derniers résultats ensemble.
  static Stream<List<QuerySnapshot<Map<String, dynamic>>>> _merge2(
      Stream<QuerySnapshot<Map<String, dynamic>>> a,
      Stream<QuerySnapshot<Map<String, dynamic>>> b) {
    late StreamController<List<QuerySnapshot<Map<String, dynamic>>>> c;
    QuerySnapshot<Map<String, dynamic>>? la, lb;
    StreamSubscription? sa, sb;
    void emit() {
      if (la != null && lb != null) c.add([la!, lb!]);
    }

    c = StreamController(
      onListen: () {
        sa = a.listen((v) {
          la = v;
          emit();
        }, onError: c.addError);
        sb = b.listen((v) {
          lb = v;
          emit();
        }, onError: c.addError);
      },
      onCancel: () async {
        await sa?.cancel();
        await sb?.cancel();
      },
    );
    return c.stream;
  }

  /// Ajoute le champ « attribuée à » aux anciennes discussions (responsable).
  static Future<void> backfillAssignment(String? shopId) async {
    try {
      Query<Map<String, dynamic>> q = conversations;
      if (shopId != null) q = q.where('shopId', isEqualTo: shopId);
      final snap = await q.get();
      final batch = _fs.batch();
      var n = 0;
      for (final d in snap.docs) {
        if (!d.data().containsKey('assignedTo')) {
          batch.update(d.reference, {'assignedTo': '', 'assignedName': ''});
          n++;
          if (n >= 450) break;
        }
      }
      if (n > 0) await batch.commit();
    } catch (_) {}
  }

  /// Transférer une discussion à un autre membre de l'équipe.
  static Future<void> transferConversation({
    required String conversationId,
    required String toUid,
    required String toName,
    required String byUid,
    required String byName,
    required String teamName,
  }) async {
    final ref = conversations.doc(conversationId);
    final data = (await ref.get()).data() ?? {};
    // 1. Trace dans la discussion (pendant qu'on y a encore accès)
    await sendMessage(
      conversationId: conversationId,
      createIfMissing: const {},
      senderId: byUid,
      senderRole: 'shop',
      senderName: teamName,
      text: '🔁 Discussion transférée à $toName par $byName',
      type: 'system',
      notify: false,
    );
    // 2. Nouveau responsable
    await ref.update({'assignedTo': toUid, 'assignedName': toName});
    // 3. Prévenir la personne
    NotifyService.toMember(
      uid: toUid,
      shopId: (data['shopId'] ?? 'main').toString(),
      title: 'Discussion transférée par $byName',
      body: '${data['clientName'] ?? 'Client'} : ${data['lastMessage'] ?? ''}',
      data: {'type': 'chat', 'conversationId': conversationId},
    );
  }

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
    bool notify = true,
    String agentName = '', // nom de l'agent (équipe) pour l'attribution
  }) async {
    final convRef = conversations.doc(conversationId);
    // Sans connexion : on lit la copie gardée sur le téléphone.
    DocumentSnapshot<Map<String, dynamic>>? convSnap;
    try {
      convSnap = await convRef.get().timeout(const Duration(seconds: 6));
    } catch (_) {
      try {
        convSnap = await convRef.get(const GetOptions(source: Source.cache));
      } catch (_) {
        convSnap = null; // inconnu : on fusionnera sans écraser
      }
    }
    final unknown = convSnap == null;
    final exists = convSnap?.exists ?? false;
    final convData = convSnap?.data() ?? createIfMissing;
    final batch = _fs.batch();
    final preview = type == 'service'
        ? (senderRole == 'client'
            ? '🛍 $itemName${text.isEmpty ? '' : ' : $text'}'
            : 'Service proposé : $itemName')
        : type == 'file'
            ? (text.isNotEmpty ? text : 'Fichier : $fileName')
            : text;
    final convUpdate = <String, dynamic>{
      'lastMessage': preview.length > 120 ? '${preview.substring(0, 120)}…' : preview,
      'lastAt': FieldValue.serverTimestamp(),
      if (senderRole == 'client') 'unreadForShop': FieldValue.increment(1),
      if (senderRole == 'shop') 'unreadForClient': FieldValue.increment(1),
    };
    final assigned = (convData['assignedTo'] ?? '').toString();
    if (senderRole == 'shop' && type != 'system' && assigned.isEmpty) {
      // Le premier membre de l'équipe qui répond prend la discussion.
      convUpdate['assignedTo'] = senderId;
      convUpdate['assignedName'] = agentName.isEmpty ? senderName : agentName;
    } else if (exists && !convData.containsKey('assignedTo')) {
      convUpdate['assignedTo'] = '';
      convUpdate['assignedName'] = '';
    }
    if (unknown) {
      // État inconnu (hors connexion, jamais ouverte) : fusion prudente.
      convUpdate.remove('assignedTo');
      convUpdate.remove('assignedName');
      batch.set(convRef, {...createIfMissing, ...convUpdate}, SetOptions(merge: true));
    } else if (exists) {
      batch.update(convRef, convUpdate);
    } else {
      batch.set(convRef, {
        'assignedTo': '',
        'assignedName': '',
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
      if (senderRole == 'shop' && agentName.isNotEmpty) 'agentName': agentName,
      'createdAt': FieldValue.serverTimestamp(),
    });
    // L'envoi part dès que la connexion est là ; on n'attend pas plus de 8 s.
    final commit = batch.commit();
    SyncStatus.trackWrite(commit);
    var sent = true;
    try {
      await commit.timeout(const Duration(seconds: 8));
    } on TimeoutException {
      sent = false; // en attente de synchronisation
    }
    if (!notify) return;
    if (!sent) {
      commit.then((_) => _notifyMessage(convData, conversationId, senderRole,
          senderName, preview, assigned)).catchError((_) {});
      return;
    }
    _notifyMessage(
        convData, conversationId, senderRole, senderName, preview, assigned);
  }

  static void _notifyMessage(Map<String, dynamic> convData, String conversationId,
      String senderRole, String senderName, String preview, String assigned) {
    final shopId = (convData['shopId'] ?? 'main').toString();
    final orderId = (convData['orderId'] ?? '').toString();
    final notifData = {'type': 'chat', 'conversationId': conversationId};
    if (senderRole == 'client' && assigned.isNotEmpty) {
      NotifyService.toMember(
        uid: assigned,
        shopId: shopId,
        title: 'Nouveau message de $senderName',
        body: preview,
        data: notifData,
      );
    } else if (senderRole == 'client') {
      NotifyService.toStaff(
        shopId: shopId,
        title: 'Nouveau message de $senderName',
        body: preview,
        data: notifData,
      );
    } else {
      NotifyService.toUser(
        uid: (convData['clientId'] ?? '').toString(),
        kind: 'messages',
        title: senderName,
        body: orderId.isEmpty ? preview : '${convData['title'] ?? ''} : $preview',
        data: notifData,
      );
    }
  }

  /// Remet à zéro le compteur de messages non lus (côté client ou boutique).
  static Future<void> markRead(String conversationId, {required bool asShop}) =>
      conversations
          .doc(conversationId)
          .update({asShop ? 'unreadForShop' : 'unreadForClient': 0})
          .catchError((_) {});

  // ---------------- Fichiers ----------------
  static Future<void> addFile(Map<String, dynamic> data) =>
      files.add({...data, 'createdAt': FieldValue.serverTimestamp()});

  static Stream<List<FileRecord>> myFiles(String uid) => files
      .where('ownerId', isEqualTo: uid)
      .snapshots()
      .map((s) => s.docs.map(FileRecord.fromDoc).toList()
        ..sort((a, b) => _newestFirst(a.createdAt, b.createdAt)));

  // ---------------- Journal des notifications commerciales ----------------
  static Future<void> logNotification(Map<String, dynamic> data) =>
      notifications.add({...data, 'createdAt': FieldValue.serverTimestamp()});

  // ---------------- Notifications dans l'application (cloche) ----------------
  static Future<void> addInbox(Map<String, dynamic> data) async {
    String cut(Object? v, int n) {
      final t = '${v ?? ''}';
      return t.length <= n ? t : '${t.substring(0, n - 1)}…';
    }
    try {
      await inbox.add({
        ...data,
        'title': cut(data['title'], 150),
        'body': cut(data['body'], 600),
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  static Stream<List<InboxItem>> clientInbox(String uid) => inbox
      .where('toUid', isEqualTo: uid)
      .snapshots()
      .map((s) => s.docs
          .map(InboxItem.fromDoc)
          .where((i) => i.audience != 'member')
          .toList()
        ..sort((a, b) => _newestFirst(a.createdAt, b.createdAt)));

  /// Notifications de l'équipe : une boutique, ou toutes (Super Admin).
  static Stream<List<InboxItem>> staffInbox({String? shopId, String? uid}) {
    Query<Map<String, dynamic>> q = inbox.where('audience', isEqualTo: 'staff');
    if (shopId != null) q = q.where('shopId', isEqualTo: shopId);
    if (uid == null) {
      return q.snapshots().map((s) => s.docs.map(InboxItem.fromDoc).toList()
        ..sort((a, b) => _newestFirst(a.createdAt, b.createdAt)));
    }
    // + les notifications adressées personnellement (discussions attribuées)
    final mine = inbox.where('toUid', isEqualTo: uid).snapshots();
    return _merge2(q.snapshots(), mine).map((pair) {
      final map = <String, InboxItem>{};
      for (final s in pair) {
        for (final d in s.docs) {
          final it = InboxItem.fromDoc(d);
          if (identical(s, pair[1]) && it.audience != 'member') continue;
          map[d.id] = it;
        }
      }
      return map.values.toList()
        ..sort((a, b) => _newestFirst(a.createdAt, b.createdAt));
    });
  }

  /// Marque comme vus (field : inboxSeenAt, ordersSeenAt ou staffSeenAt).
  static Future<void> markSeen(String uid, String field) =>
      users.doc(uid).set({field: FieldValue.serverTimestamp()}, SetOptions(merge: true));
}
