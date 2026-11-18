import 'package:flutter/material.dart';

import '../config.dart';
import '../models/shop.dart';
import '../services/db.dart';
import '../services/session.dart';

/// « Choisissez votre boutique AÏCHA SERVICES ».
class ShopPickerScreen extends StatelessWidget {
  final bool firstTime;
  const ShopPickerScreen({super.key, this.firstTime = false});

  Future<void> _choose(BuildContext context, Session s, Shop shop) async {
    await Db.updateProfile(s.uid, {'shopId': shop.id});
    // La discussion générale suit la nouvelle boutique.
    try {
      await Db.conversations
          .doc(Db.generalConversationId(s.uid))
          .update({'shopId': shop.id});
    } catch (_) {}
    if (!firstTime && context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = sessionOf(context);
    return Scaffold(
      appBar: firstTime ? null : AppBar(title: const Text('Changer de boutique')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (firstTime) ...[
              const SizedBox(height: 12),
              Center(child: Image.asset(AppConfig.logo, height: 110)),
              const SizedBox(height: 12),
            ],
            const Text('Choisissez votre boutique AÏCHA SERVICES',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            const Text(
              'Vos commandes et vos discussions seront traitées par cette boutique.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 20),
            for (final shop in s.shops)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: shop.id == s.user?.shopId
                          ? AppConfig.green
                          : const Color(0xFFE6EAE4),
                      width: shop.id == s.user?.shopId ? 2 : 1,
                    ),
                  ),
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    leading: const CircleAvatar(
                      radius: 24,
                      backgroundColor: AppConfig.paleGreen,
                      child: Icon(Icons.storefront_rounded, color: AppConfig.green),
                    ),
                    title: Text(shop.name,
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text([
                      if (shop.locality.isNotEmpty) shop.locality,
                      if (shop.address.isNotEmpty) shop.address,
                      if (shop.hours.isNotEmpty) shop.hours,
                    ].join('\n')),
                    trailing: shop.id == s.user?.shopId
                        ? const Icon(Icons.check_circle, color: AppConfig.green)
                        : const Icon(Icons.chevron_right),
                    onTap: () => _choose(context, s, shop),
                  ),
                ),
              ),
            if (s.shops.isEmpty)
              const Text('Aucune boutique disponible pour le moment.',
                  textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
