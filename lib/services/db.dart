import 'package:cloud_firestore/cloud_firestore.dart';

import '../config.dart';
import '../models/app_user.dart';
import '../models/catalog_item.dart';
import '../models/order.dart';
import '../models/shop_settings.dart';

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
  static DocumentReference<Map<String, dynamic>> get settingsDoc =>
      _fs.collection('settings').doc('shop');

  static int _newestFirst(DateTime? a, DateTime? b) =>
      (b ?? DateTime(2100)).compareTo(a ?? DateTime(2100));

  // ---------- Utilisateurs ----------
  static Stream<AppUser?> userStream(String uid) => users
      .doc(uid)
      .snapshots()
      .map((d) => d.exists ? AppUser.fromDoc(d) : null);

  /// Le patron = un document admins/{uid} créé dans la console Firebase.
  static Stream<bool> isAdmin(String uid) => AppConfig.adminUids.contains(uid)
      ? Stream<bool>.value(true)
      : admins
      .doc(uid)
      .snapshots()
      .map((d) => d.exists)
      .handleError((_) => false);

  // ---------- Réglages boutique ----------
  static Stream<ShopSettings> settings() =>
      settingsDoc.snapshots().map(ShopSettings.fromDoc);

  static Future<void> saveSettings(ShopSettings s) =>
      settingsDoc.set(s.toMap(), SetOptions(merge: true));

  // ---------- Catalogue ----------
  static Stream<List<CatalogItem>> catalogItems({bool onlyActive = true}) {
    Query<Map<String, dynamic>> q = catalog;
    if (onlyActive) q = q.where('active', isEqualTo: true);
    return q.snapshots().map((s) => s.docs.map(CatalogItem.fromDoc).toList()
      ..sort((a, b) => _newestFirst(a.createdAt, b.createdAt)));
  }

  // ---------- Commandes ----------
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

  static Future<String> createOrder(ShopOrder o) async {
    final ref = await orders.add(o.toNewMap());
    return ref.id;
  }

  static Future<void> setOrderStatus(String orderId, String status) =>
      orders.doc(orderId).update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  static Future<void> setQuote(String orderId, int amount, String note) =>
      orders.doc(orderId).update({
        'quotedTotal': amount,
        'adminNote': note,
        'updatedAt': FieldValue.serverTimestamp(),
      });
}
