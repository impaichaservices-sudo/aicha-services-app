import 'package:flutter/material.dart';

import '../config.dart';
import '../models/promotion.dart';
import '../services/db.dart';
import '../utils.dart';
import '../widgets/item_card.dart';
import '../widgets/product_image.dart';

/// Page d'une annonce (ouverte depuis la bande de l'accueil).
class AnnouncementScreen extends StatelessWidget {
  final Promotion promo;
  const AnnouncementScreen({super.key, required this.promo});

  Future<void> _openService(BuildContext context) async {
    final item = await Db.catalogItem(promo.itemId);
    if (!context.mounted) return;
    if (item == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ce service n\'est plus disponible.')));
      return;
    }
    openItem(context, item);
  }

  @override
  Widget build(BuildContext context) {
    final p = promo;
    final dates = [
      if (p.start != null) 'Du ${shortDate(p.start).split(' ').first}',
      if (p.end != null) 'au ${shortDate(p.end).split(' ').first}',
    ].join(' ');
    return Scaffold(
      appBar: AppBar(title: const Text('Annonce')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (p.imageUrl.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: AspectRatio(
                aspectRatio: 16 / 10,
                child: ProductImage(p.imageUrl),
              ),
            ),
          const SizedBox(height: 16),
          Row(children: [
            const Icon(Icons.campaign_rounded, color: AppConfig.green),
            const SizedBox(width: 6),
            Text(promoKinds[p.kind] ?? 'Annonce',
                style: const TextStyle(
                    color: AppConfig.green, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 6),
          Text(p.title,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          if (dates.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(dates, style: const TextStyle(color: Colors.black54)),
          ],
          const SizedBox(height: 14),
          Text(p.description,
              style: const TextStyle(fontSize: 16, height: 1.45)),
          const SizedBox(height: 24),
          if (p.itemId.isNotEmpty)
            FilledButton.icon(
              onPressed: () => _openService(context),
              icon: const Icon(Icons.shopping_bag_rounded),
              label: const Text('Voir le service'),
            ),
        ],
      ),
    );
  }
}
