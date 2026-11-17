import 'package:cloud_firestore/cloud_firestore.dart';

class NotifPrefs {
  final bool orders;
  final bool messages;
  final bool promos;
  const NotifPrefs({this.orders = true, this.messages = true, this.promos = true});

  factory NotifPrefs.fromMap(Map<String, dynamic>? m) => NotifPrefs(
        orders: (m?['orders'] ?? true) as bool,
        messages: (m?['messages'] ?? true) as bool,
        promos: (m?['promos'] ?? true) as bool,
      );

  Map<String, dynamic> toMap() =>
      {'orders': orders, 'messages': messages, 'promos': promos};
}

class AppUser {
  final String uid;
  final String name;
  final String phone;
  final String email;
  final String shopId;
  final NotifPrefs notif;
  final DateTime? createdAt;

  const AppUser({
    required this.uid,
    required this.name,
    required this.phone,
    required this.email,
    this.shopId = 'main',
    this.notif = const NotifPrefs(),
    this.createdAt,
  });

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? <String, dynamic>{};
    final n = d['notif'];
    return AppUser(
      uid: doc.id,
      name: (d['name'] ?? '') as String,
      phone: (d['phone'] ?? '') as String,
      email: (d['email'] ?? '') as String,
      shopId: (d['shopId'] ?? 'main') as String,
      notif: NotifPrefs.fromMap(n is Map ? Map<String, dynamic>.from(n) : null),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
