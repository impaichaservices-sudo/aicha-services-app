import 'package:cloud_firestore/cloud_firestore.dart';

/// Infos de la boutique, modifiables par le patron dans l'appli.
class ShopSettings {
  final String phone;
  final String whatsapp;
  final String address;
  final String hours;
  final int deliveryFee;

  const ShopSettings({
    this.phone = '',
    this.whatsapp = '',
    this.address = '',
    this.hours = '',
    this.deliveryFee = 0,
  });

  factory ShopSettings.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? <String, dynamic>{};
    return ShopSettings(
      phone: (d['phone'] ?? '') as String,
      whatsapp: (d['whatsapp'] ?? '') as String,
      address: (d['address'] ?? '') as String,
      hours: (d['hours'] ?? '') as String,
      deliveryFee: (d['deliveryFee'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'phone': phone,
        'whatsapp': whatsapp,
        'address': address,
        'hours': hours,
        'deliveryFee': deliveryFee,
      };
}
