import 'package:flutter/material.dart';

import '../../config.dart';
import '../../models/catalog_item.dart';
import '../../services/db.dart';
import '../../services/session.dart';
import '../../widgets/common.dart';
import '../../widgets/product_image.dart';
import 'item_form_screen.dart';

/// Gestion → Catalogue.
class AdminCatalogScreen extends StatefulWidget {
  final String? shopId; // null = Super Admin (toutes les boutiques)
  const AdminCatalogScreen({super.key, this.shopId});

  @override
  State<AdminCatalogScreen> createState() => _AdminCatalogScreenState();
}

class _AdminCatalogScreenState extends State<AdminCatalogScreen> {
  late final Stream<List<CatalogItem>> _items = Db.catalogItems(onlyActive: false);

  void _open([CatalogItem? item]) {
    if (item != null && widget.shopId != null && item.shopId != widget.shopId) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Ce service est commun à toutes les boutiques : '
              'seule l\'administration peut le modifier.')));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ItemFormScreen(item: item, shopId: widget.shopId)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Catalogue')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(),
        icon: const Icon(Icons.add),
        label: const Text('Nouveau service'),
      ),
      body: StreamBuilder<List<CatalogItem>>(
        stream: _items,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Erreur : ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final list = snap.data!
              .where((i) => widget.shopId == null || i.availableIn(widget.shopId!))
              .toList();
          final session = sessionOf(context);
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.grid_view_rounded,
              title: 'Catalogue vide',
              message:
                  'Ajoutez vos services : cartes de visite, t-shirts personnalisés, formation Excel…',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final item = list[i];
              return Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(10),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: ProductImage(item.imageUrl, size: 56),
                  ),
                  title: Text(item.name,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${itemTypes[item.type] ?? item.type} • ${item.priceLabel}'),
                      const SizedBox(height: 4),
                      Wrap(spacing: 6, runSpacing: 4, children: [
                        if (!item.active)
                          const Pill('Masqué', color: Colors.grey),
                        if (!item.available)
                          const Pill('Indisponible', color: Color(0xFFC62828)),
                        if (item.popular)
                          const Pill('Populaire', color: AppConfig.green),
                        if (session.shops.isNotEmpty)
                          Pill(
                              item.shopId == 'all' || item.shopId == 'main'
                                  ? 'Toutes les boutiques'
                                  : session.shopById(item.shopId).name,
                              color: const Color(0xFF455A64)),
                        if (item.isTraining && item.places > 0)
                          Pill('${item.placesLeft}/${item.places} places',
                              color: const Color(0xFF6A1B9A)),
                      ]),
                    ],
                  ),
                  trailing: Switch(
                    value: item.active,
                    onChanged: widget.shopId != null && item.shopId != widget.shopId
                        ? null
                        : (v) => Db.catalog.doc(item.id).update({'active': v}),
                  ),
                  onTap: () => _open(item),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
