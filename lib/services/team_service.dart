import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../config.dart';
import '../models/staff.dart';
import '../models/team_chat.dart';
import 'db.dart';
import 'notify_service.dart';
import 'session.dart';

/// Discussions internes de l'équipe : groupe de toute l'équipe, groupes de
/// réunion, messages privés entre collègues.
class TeamService {
  static final _fs = FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get chats =>
      _fs.collection('teamChats');

  static String directId(String a, String b) {
    final l = [a, b]..sort();
    return 'd_${l[0]}_${l[1]}';
  }

  static String shopChatId(String shopId) => 'g_$shopId';

  static List<TeamChat> _sort(Iterable<TeamChat> l) => l.toList()
    ..sort((a, b) => (b.lastAt ?? DateTime(2000)).compareTo(a.lastAt ?? DateTime(2000)));

  /// Discussions visibles par l'utilisateur.
  static Stream<List<TeamChat>> myChats(Session s) {
    if (s.isSuper) {
      return chats.limit(300).snapshots().map((q) => _sort(q.docs.map(TeamChat.fromDoc)));
    }
    final shopId = s.staff?.shopId ?? '';
    final a = chats.where('members', arrayContains: s.uid).snapshots();
    final b = chats
        .where('type', isEqualTo: 'shop')
        .where('shopId', isEqualTo: shopId)
        .snapshots();
    QuerySnapshot<Map<String, dynamic>>? la, lb;
    StreamSubscription? sa, sb;
    late StreamController<List<TeamChat>> c;
    void emit() {
      final m = <String, TeamChat>{};
      for (final d in [...?la?.docs, ...?lb?.docs]) {
        m[d.id] = TeamChat.fromDoc(d);
      }
      if (!c.isClosed) c.add(_sort(m.values));
    }

    c = StreamController<List<TeamChat>>(
      onListen: () {
        sa = a.listen((x) {
          la = x;
          emit();
        }, onError: (_) {});
        sb = b.listen((x) {
          lb = x;
          emit();
        }, onError: (_) {});
      },
      onCancel: () {
        sa?.cancel();
        sb?.cancel();
      },
    );
    return c.stream;
  }

  static Stream<TeamChat?> chatStream(String id) => chats
      .doc(id)
      .snapshots()
      .map((d) => d.exists ? TeamChat.fromDoc(d) : null)
      .handleError((_) {});

  static Stream<List<TeamMessage>> messages(String chatId) => chats
      .doc(chatId)
      .collection('messages')
      .orderBy('createdAt', descending: true)
      .limit(200)
      .snapshots(includeMetadataChanges: true)
      .map((q) => q.docs.map(TeamMessage.fromDoc).toList());

  /// Crée (si besoin) le groupe « Toute l'équipe » de chaque boutique gérée.
  static Future<void> ensureShopChats(Session s) async {
    final shops = s.isSuper
        ? s.shops
        : s.shops.where((x) => x.id == s.staff?.shopId).toList();
    for (final shop in shops) {
      try {
        final ref = chats.doc(shopChatId(shop.id));
        final d = await ref.get();
        if (d.exists) continue;
        await ref.set({
          'type': 'shop',
          'shopId': shop.id,
          'name': "Toute l'équipe · ${shop.name}",
          'members': <String>[],
          'memberNames': <String, String>{},
          'lastMessage': '',
          'lastSender': '',
          'lastAt': FieldValue.serverTimestamp(),
          'readBy': <String, dynamic>{},
          'createdBy': s.uid,
        });
      } catch (_) {}
    }
  }

  /// Personnes joignables : collègues (et Super Admin).
  static Stream<List<TeamPerson>> people(Session s) {
    final shopId = s.isSuper ? null : s.staff?.shopId;
    return Db.allStaff(shopId: shopId).map((list) {
      final out = <TeamPerson>[];
      for (final uid in AppConfig.adminUids) {
        if (uid != s.uid) {
          out.add(TeamPerson(uid, 'Super Admin', 'Super Admin', s.staff?.shopId ?? 'main'));
        }
      }
      for (final StaffMember m in list) {
        if (m.uid == s.uid || !m.active) continue;
        out.add(TeamPerson(m.uid, m.name, staffRoleLabels[m.role] ?? 'Agent', m.shopId));
      }
      return out;
    });
  }

  /// Ouvre (ou crée) la discussion privée avec un collègue.
  static Future<String> openDirect({
    required String me,
    required String myName,
    required TeamPerson other,
  }) async {
    final id = directId(me, other.uid);
    final ref = chats.doc(id);
    final d = await ref.get();
    if (!d.exists) {
      await ref.set({
        'type': 'direct',
        'shopId': other.shopId,
        'name': '',
        'members': [me, other.uid],
        'memberNames': {me: myName, other.uid: other.name},
        'lastMessage': '',
        'lastSender': '',
        'lastAt': FieldValue.serverTimestamp(),
        'readBy': <String, dynamic>{},
        'createdBy': me,
      });
    }
    return id;
  }

  /// Groupe de réunion (Super Admin ou responsable).
  static Future<String> createGroup({
    required String me,
    required String myName,
    required String name,
    required String shopId,
    required List<TeamPerson> members,
  }) async {
    final ref = chats.doc();
    await ref.set({
      'type': 'group',
      'shopId': shopId,
      'name': name,
      'members': [me, ...members.map((m) => m.uid)],
      'memberNames': {me: myName, for (final m in members) m.uid: m.name},
      'lastMessage': '👥 Groupe créé par $myName',
      'lastSender': me,
      'lastAt': FieldValue.serverTimestamp(),
      'readBy': {me: FieldValue.serverTimestamp()},
      'createdBy': me,
    });
    return ref.id;
  }

  static Future<void> send({
    required TeamChat chat,
    required String me,
    required String myName,
    String text = '',
    String type = 'text',
    String fileUrl = '',
    String fileName = '',
  }) async {
    final ref = chats.doc(chat.id);
    final msg = ref.collection('messages').doc();
    final preview = type == 'file' ? (text.isNotEmpty ? text : '📎 $fileName') : text;
    final batch = _fs.batch();
    batch.set(msg, {
      'senderId': me,
      'senderName': myName,
      'text': text,
      'type': type,
      'fileUrl': fileUrl,
      'fileName': fileName,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(ref, {
      'lastMessage': preview.length > 120 ? '${preview.substring(0, 119)}…' : preview,
      'lastSender': me,
      'lastAt': FieldValue.serverTimestamp(),
      'readBy.$me': FieldValue.serverTimestamp(),
    });
    final commit = batch.commit();
    // Hors connexion : envoyé automatiquement au retour d'internet.
    await commit.timeout(const Duration(seconds: 8), onTimeout: () {});
    final title = chat.isDirect ? '💬 $myName' : '👥 ${chat.name}';
    final body = chat.isDirect ? preview : '$myName : $preview';
    NotifyService.team(
      chatId: chat.id,
      shopId: chat.shopId,
      wholeShop: chat.isShop,
      uids: chat.members.where((u) => u != me).toList(),
      title: title,
      body: body,
    );
  }

  static Future<void> markRead(String chatId, String me) async {
    try {
      await chats.doc(chatId).update({'readBy.$me': FieldValue.serverTimestamp()});
    } catch (_) {}
  }
}
