import 'dart:async';
import 'dart:convert';

import 'package:aicha_media/aicha_media.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/shop_settings.dart';
import '../nav.dart';
import '../screens/admin/admin_orders_screen.dart';
import '../screens/chat_screen.dart';
import '../screens/order_detail_screen.dart';
import '../widgets/item_card.dart';
import 'db.dart';
import 'session.dart';

/// Message reçu quand l'application est fermée ou en arrière-plan.
/// Appel entrant : notification plein écran avec sonnerie (s'affiche aussi
/// sur l'écran verrouillé) qui ouvre l'application sur l'appel.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage m) async {
  if (m.data['type'] == 'incoming_call') {
    final name = (m.data['callerName'] ?? '').toString();
    try {
      await AichaMedia.showIncomingCall(
        (m.data['callId'] ?? '').toString(),
        'Appel vocal${name.isEmpty ? '' : ' — $name'}',
        'Aïcha Services • touchez pour répondre',
      );
    } catch (_) {}
  } else if (m.data['type'] == 'call_ended') {
    try {
      await AichaMedia.cancelIncomingCall();
    } catch (_) {}
  }
}

/// Envoi des notifications push via le serveur gratuit (Cloudflare Worker),
/// qui les transmet à Firebase Cloud Messaging.
/// Tant que l'adresse du serveur n'est pas renseignée dans
/// Gestion → Paramètres, rien n'est envoyé (l'appli fonctionne quand même).
class NotifyService {
  static String? _url;

  static void resetCache() => _url = null;

  static Future<String> _endpoint() async {
    if (_url != null) return _url!;
    try {
      final s = ShopSettings.fromDoc(await Db.settingsDoc.get());
      _url = s.pushEnabled ? s.notifyUrl : '';
    } catch (_) {
      _url = '';
    }
    return _url!;
  }

  static Future<bool> _post(Map<String, dynamic> body) async {
    try {
      final url = await _endpoint();
      if (url.isEmpty) return false;
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) return false;
      final res = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Map<String, String> _strings(Map<String, dynamic> m) =>
      m.map((k, v) => MapEntry(k, v.toString()));

  /// Prévenir l'équipe d'une boutique (et le Super Admin).
  static String get _me => FirebaseAuth.instance.currentUser?.uid ?? '';

  static void toStaff({
    required String shopId,
    required String title,
    required String body,
    Map<String, dynamic> data = const {},
  }) {
    Db.addInbox({
      'audience': 'staff',
      'toUid': '',
      'shopId': shopId,
      'fromUid': _me,
      'title': title,
      'body': body,
      'data': _strings({...data, 'audience': 'staff'}),
    }).catchError((_) {});
    _post({
      'action': 'to_staff',
      'shopId': shopId,
      'title': title,
      'body': body,
      'data': _strings({...data, 'audience': 'staff'}),
    });
  }

  /// Prévenir un seul membre de l'équipe (discussion attribuée / transférée).
  static void toMember({
    required String uid,
    required String shopId,
    required String title,
    required String body,
    Map<String, dynamic> data = const {},
  }) {
    if (uid.isEmpty) return;
    Db.addInbox({
      'audience': 'member',
      'toUid': uid,
      'shopId': shopId,
      'fromUid': _me,
      'title': title,
      'body': body,
      'data': _strings({...data, 'audience': 'staff'}),
    }).catchError((_) {});
    _post({
      'action': 'to_user',
      'uid': uid,
      'kind': 'messages',
      'title': title,
      'body': body,
      'data': _strings({...data, 'audience': 'staff'}),
    });
  }

  /// Faire sonner le(s) téléphone(s) appelé(s), même application fermée.
  /// Le serveur vérifie que l'appelant a le droit d'appeler.
  static void incomingCall({required String callId}) {
    _post({'action': 'incoming_call', 'callId': callId});
  }

  /// Arrêter la sonnerie chez les autres (appel pris, annulé ou terminé).
  static void callEnded({required String callId}) {
    _post({'action': 'call_ended', 'callId': callId});
  }

  /// Prévenir un client (kind : 'orders' ou 'messages', selon ses réglages).
  static void toUser({
    required String uid,
    required String kind,
    required String title,
    required String body,
    Map<String, dynamic> data = const {},
  }) {
    if (uid.isEmpty) return;
    Db.addInbox({
      'audience': 'client',
      'toUid': uid,
      'shopId': '',
      'fromUid': _me,
      'title': title,
      'body': body,
      'data': _strings({...data, 'audience': 'client'}),
    }).catchError((_) {});
    _post({
      'action': 'to_user',
      'uid': uid,
      'kind': kind,
      'title': title,
      'body': body,
      'data': _strings({...data, 'audience': 'client'}),
    });
  }

  /// Nouveautés / promotions : toutes les boutiques (['all']) ou certaines.
  static Future<bool> toShops({
    required List<String> shops,
    required String title,
    required String body,
    Map<String, dynamic> data = const {},
  }) =>
      _post({
        'action': 'to_topic',
        'shops': shops,
        'title': title,
        'body': body,
        'data': _strings({...data, 'audience': 'client'}),
      });
}

/// Réception : jeton du téléphone, abonnements, ouverture au toucher.
class PushService {
  static Session? _session;
  static String _lastSync = '';
  static bool _listening = false;

  static String _topicSafe(String s) =>
      s.replaceAll(RegExp(r'[^a-zA-Z0-9\-_.~%]'), '_');

  /// À appeler quand la session change (connexion, boutique, rôle, réglages).
  static Future<void> sync(Session s) async {
    _session = s;
    final p = s.user?.notif;
    final key = [
      s.uid,
      s.clientShopId,
      s.isSuper,
      s.staff?.shopId ?? '',
      s.staff?.active ?? false,
      p?.promos ?? true,
    ].join('|');
    if (key == _lastSync) return;
    _lastSync = key;
    try {
      final fm = FirebaseMessaging.instance;
      await fm.requestPermission();
      final token = await fm.getToken();
      if (token != null) await _saveToken(s.uid, token);
      if (!_listening) {
        _listening = true;
        fm.onTokenRefresh.listen((t) {
          final uid = FirebaseAuth.instance.currentUser?.uid;
          if (uid != null) _saveToken(uid, t);
        });
        FirebaseMessaging.onMessage.listen(_onForeground);
        FirebaseMessaging.onMessageOpenedApp.listen(_open);
        final initial = await fm.getInitialMessage();
        if (initial != null) _open(initial);
      }
      // Abonnements aux sujets
      final promos = p?.promos ?? true;
      final shopTopic = _topicSafe('promos_${s.clientShopId.isEmpty ? 'main' : s.clientShopId}');
      if (promos) {
        await fm.subscribeToTopic('promos_all');
        await fm.subscribeToTopic(shopTopic);
      } else {
        await fm.unsubscribeFromTopic('promos_all');
        await fm.unsubscribeFromTopic(shopTopic);
      }
      if (s.isSuper) await fm.subscribeToTopic('staff_all');
      if (s.isStaff) await fm.subscribeToTopic(_topicSafe('staff_${s.staff!.shopId}'));
    } catch (_) {
      // Notifications indisponibles sur cet appareil : on continue sans.
    }
  }

  /// À la déconnexion : ne plus recevoir les notifications de ce compte.
  static Future<void> signOut(String uid) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await Db.users.doc(uid).set({
          'fcmTokens': FieldValue.arrayRemove([token])
        }, SetOptions(merge: true));
      }
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
    _lastSync = '';
  }

  static Future<void> _saveToken(String uid, String token) =>
      Db.users.doc(uid).set({
        'fcmTokens': FieldValue.arrayUnion([token])
      }, SetOptions(merge: true));

  static void _onForeground(RemoteMessage m) {
    final n = m.notification;
    if (n == null) return;
    messengerKey.currentState?.showSnackBar(SnackBar(
      duration: const Duration(seconds: 5),
      content: Text('${n.title ?? ''}\n${n.body ?? ''}'.trim()),
      action: SnackBarAction(label: 'Voir', onPressed: () => _open(m)),
    ));
  }

  static Future<void> _open(RemoteMessage m) => openData(m.data);

  /// Ouvre l'écran lié à une notification (push ou cloche).
  static Future<void> openData(Map<String, dynamic> d) async {
    final nav = navigatorKey.currentState;
    final s = _session;
    if (nav == null || s == null) return;
    final asStaff = d['audience'] == 'staff' && s.canManage;
    switch (d['type']) {
      case 'order':
        final id = d['orderId'] ?? '';
        if (id.isEmpty) return;
        nav.push(MaterialPageRoute(
          builder: (_) => asStaff
              ? AdminOrderDetailScreen(orderId: id, me: s.me)
              : OrderDetailScreen(orderId: id),
        ));
        break;
      case 'chat':
        final id = d['conversationId'] ?? '';
        if (id.isEmpty) return;
        final conv = await Db.conversationStream(id).first;
        if (conv == null) return;
        nav.push(MaterialPageRoute(
          builder: (_) => ChatScreen(
            conversationId: id,
            createIfMissing: const {},
            title: asStaff
                ? conv.clientName
                : (conv.isOrder ? 'Commande #${conv.orderNumber}' : conv.title),
            subtitle: asStaff && conv.isOrder ? 'Commande #${conv.orderNumber}' : null,
            asShop: asStaff,
            me: s.me,
            shopId: conv.shopId,
            orderId: conv.orderId,
            clientPhone: asStaff ? conv.clientPhone : '',
          ),
        ));
        break;
      case 'promo':
        final itemId = d['itemId'] ?? '';
        if (itemId.isEmpty) return;
        final item = await Db.catalogItem(itemId);
        final ctx = navigatorKey.currentContext;
        if (item != null && ctx != null && ctx.mounted) openItem(ctx, item);
        break;
    }
  }
}
