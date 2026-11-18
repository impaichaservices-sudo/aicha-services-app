import 'package:cloud_firestore/cloud_firestore.dart';

import 'shop_settings.dart';

/// Une boutique AÏCHA SERVICES (Djidian, Kéniéba, Bamako…).
class Shop {
  final String id;
  final String name; // ex : "Aïcha Services Djidian"
  final String code; // ex : "DJD" (numéros AS-DJD-00125)
  final String locality;
  final String address;
  final String phone;
  final String whatsapp;
  final String hours;
  final int deliveryFee;
  final bool active;
  final DateTime? createdAt;

  const Shop({
    required this.id,
    required this.name,
    required this.code,
    required this.locality,
    required this.address,
    required this.phone,
    required this.whatsapp,
    required this.hours,
    required this.deliveryFee,
    required this.active,
    this.createdAt,
  });

  /// Boutique par défaut (avant la création des boutiques) : infos des Réglages.
  factory Shop.fromSettings(ShopSettings s) => Shop(
        id: 'main',
        name: 'Aïcha Services',
        code: '',
        locality: '',
        address: s.address,
        phone: s.phone,
        whatsapp: s.whatsapp,
        hours: s.hours,
        deliveryFee: s.deliveryFee,
        active: true,
      );

  String get contact => whatsapp.isNotEmpty ? whatsapp : phone;

  factory Shop.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? <String, dynamic>{};
    return Shop(
      id: doc.id,
      name: (d['name'] ?? '') as String,
      code: (d['code'] ?? '') as String,
      locality: (d['locality'] ?? '') as String,
      address: (d['address'] ?? '') as String,
      phone: (d['phone'] ?? '') as String,
      whatsapp: (d['whatsapp'] ?? '') as String,
      hours: (d['hours'] ?? '') as String,
      deliveryFee: (d['deliveryFee'] as num?)?.toInt() ?? 0,
      active: (d['active'] ?? true) as bool,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'code': code,
        'locality': locality,
        'address': address,
        'phone': phone,
        'whatsapp': whatsapp,
        'hours': hours,
        'deliveryFee': deliveryFee,
        'active': active,
      };
}
