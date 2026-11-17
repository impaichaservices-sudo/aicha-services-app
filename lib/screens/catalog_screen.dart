import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../models/catalog_item.dart';
import '../models/shop_settings.dart';
import '../services/db.dart';
import '../utils.dart';
import '../widgets/product_image.dart';
import 'item_detail_screen.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  late final Stream<List<CatalogItem>> _items = Db.catalogItems();
  late final Stream<ShopSettings> _settings = Db.settings();
  String _query = '';
  String? _type;

  List<CatalogItem> _filter(List<CatalogItem> all) {
    final q = _query.trim().toLowerCase();
    return all.where((i) {
      if (_type != null && i.type != _type) return false;
      if (q.isEmpty) return true;
      return i.name.toLowerCase().contains(q) ||
          i.description.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConfig.shopName,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          StreamBuilder<ShopSettings>(
            stream: _settings,
            builder: (context, snap) {
              final wa = snap.data?.whatsapp ?? '';
              if (wa.isEmpty) return const SizedBox.shrink();
              return IconButton(
                tooltip: 'Nous écrire sur WhatsApp',
                icon: const Icon(Icons.chat),
                onPressed: () => launchUrl(
                  whatsappUri(wa, 'Bonjour ${AppConfig.shopName}, '),
                  mode: LaunchMode.externalApplication,
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(AppConfig.logo, width: 72, height: 72),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppConfig.tagline,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  'Commandez vos impressions et inscrivez-vous à nos '
                  'formations, en livraison ou en retrait.',
                  style: TextStyle(color: scheme.onPrimaryContainer),
                ),
              ],
            )),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Rechercher (carte de visite, flyer, Excel…)',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final t in <String?>[null, ...itemTypes.keys])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(t == null ? 'Tout' : itemTypes[t]!),
                      selected: _type == t,
                      onSelected: (_) => setState(() => _type = t),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<CatalogItem>>(
              stream: _items,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text('Erreur : ${snap.error}'));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final list = _filter(snap.data!);
                if (list.isEmpty) {
                  return const Center(child: Text('Aucun service pour le moment.'));
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _ItemCard(item: list[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  final CatalogItem item;
  const _ItemCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ItemDetailScreen(item: item),
        )),
        child: Row(
          children: [
            ProductImage(item.imageUrl, size: 96),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(itemTypes[item.type] ?? item.type,
                        style: t.labelSmall?.copyWith(color: scheme.primary)),
                    Text(item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.titleSmall),
                    if (item.isTraining && item.schedule.isNotEmpty)
                      Text('📅 ${item.schedule}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodySmall),
                    const SizedBox(height: 4),
                    Text(item.priceLabel,
                        style: t.titleSmall?.copyWith(
                            color: scheme.primary, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
            const Icon(Icons.chevron_right),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
