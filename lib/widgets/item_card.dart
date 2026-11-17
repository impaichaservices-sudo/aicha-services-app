import 'package:flutter/material.dart';

import '../config.dart';
import '../models/catalog_item.dart';
import '../screens/item_detail_screen.dart';
import 'common.dart';
import 'product_image.dart';

void openItem(BuildContext context, CatalogItem item) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => ItemDetailScreen(item: item),
  ));
}

/// Carte de service : photo, nom, prix ou « Sur devis », bouton Commander.
class ItemCard extends StatelessWidget {
  final CatalogItem item;
  final double? width;
  const ItemCard({super.key, required this.item, this.width});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openItem(context, item),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(fit: StackFit.expand, children: [
                  ProductImage(item.imageUrl),
                  if (!item.canOrder)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(8)),
                        child: Text(item.isFull ? 'Complet' : 'Indisponible',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14, height: 1.2)),
                    const SizedBox(height: 4),
                    item.onQuote
                        ? const Pill('Sur devis',
                            color: Color(0xFFEF6C00), icon: Icons.request_quote)
                        : Text(item.shortPrice,
                            style: const TextStyle(
                                color: AppConfig.green,
                                fontWeight: FontWeight.w800,
                                fontSize: 15)),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 36,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 36),
                          padding: EdgeInsets.zero,
                          textStyle: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                        onPressed: item.canOrder ? () => openItem(context, item) : null,
                        child: Text(item.onQuote ? 'Demander un devis' : 'Commander'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
