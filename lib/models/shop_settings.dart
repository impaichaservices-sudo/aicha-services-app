import 'package:cloud_firestore/cloud_firestore.dart';

/// Paramètres généraux (document settings/shop), modifiables par le Super Admin.
/// Contient aussi les infos de la boutique par défaut et la configuration
/// des fichiers (Cloudinary) et des notifications (serveur Cloudflare).
class ShopSettings {
  final String phone;
  final String whatsapp;
  final String address;
  final String hours;
  final int deliveryFee;
  final String cloudinaryCloud;
  final String cloudinaryPreset;
  final String notifyUrl;

  const ShopSettings({
    this.phone = '',
    this.whatsapp = '',
    this.address = '',
    this.hours = '',
    this.deliveryFee = 0,
    this.cloudinaryCloud = '',
    this.cloudinaryPreset = '',
    this.notifyUrl = '',
  });

  bool get filesEnabled => cloudinaryCloud.isNotEmpty && cloudinaryPreset.isNotEmpty;
  bool get pushEnabled => notifyUrl.startsWith('https://');

  factory ShopSettings.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? <String, dynamic>{};
    return ShopSettings(
      phone: (d['phone'] ?? '') as String,
      whatsapp: (d['whatsapp'] ?? '') as String,
      address: (d['address'] ?? '') as String,
      hours: (d['hours'] ?? '') as String,
      deliveryFee: (d['deliveryFee'] as num?)?.toInt() ?? 0,
      cloudinaryCloud: (d['cloudinaryCloud'] ?? '') as String,
      cloudinaryPreset: (d['cloudinaryPreset'] ?? '') as String,
      notifyUrl: (d['notifyUrl'] ?? '') as String,
    );
  }

  Map<String, dynamic> toMap() => {
        'phone': phone,
        'whatsapp': whatsapp,
        'address': address,
        'hours': hours,
        'deliveryFee': deliveryFee,
        'cloudinaryCloud': cloudinaryCloud,
        'cloudinaryPreset': cloudinaryPreset,
        'notifyUrl': notifyUrl,
      };
}
