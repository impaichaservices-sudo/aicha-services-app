import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../models/catalog_item.dart';
import '../models/promotion.dart';
import '../services/db.dart';
import '../services/session.dart';
import '../state/cart.dart';
import '../widgets/common.dart';
import '../widgets/item_card.dart';
import '../widgets/product_image.dart';
import 'cart_screen.dart';
import 'inbox_screen.dart';
import 'shop_picker_screen.dart';

/// Accueil : en-tête, recherche, catégories, Nos offres, Services populaires,
/// tous les services.
class CatalogScreen extends StatefulWidget {
  final VoidCallback onOpenChat;
  const CatalogScreen({super.key, required this.onOpenChat});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  late final Stream<List<CatalogItem>> _items = Db.catalogItems();
  late final Stream<List<Promotion>> _promos = Db.livePromotions();
  final _search = TextEditingController();
  String _query = '';
  String? _type;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool get _filtering => _query.trim().isNotEmpty || _type != null;

  List<CatalogItem> _filter(List<CatalogItem> all) {
    final q = _query.trim().toLowerCase();
    return all.where((i) {
      if (_type != null && i.type != _type) return false;
      if (q.isEmpty) return true;
      return i.name.toLowerCase().contains(q) ||
          i.description.toLowerCase().contains(q);
    }).toList();
  }

  void _openCart() => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CartScreen(user: sessionOf(context, listen: false).user)));

  @override
  Widget build(BuildContext context) {
    final cartCount = context.watch<Cart>().count;
    final session = sessionOf(context);
    final shopId = session.clientShopId;
    return Scaffold(
      body: StreamBuilder<List<CatalogItem>>(
        stream: _items,
        builder: (context, snap) {
          final all = (snap.data ?? const <CatalogItem>[])
              .where((i) => shopId.isEmpty || i.availableIn(shopId))
              .toList();
          final filtered = _filter(all);
          final popular = all.where((i) => i.popular).toList();
          final popularList = popular.isNotEmpty ? popular : all.take(6).toList();

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _header(cartCount, session)),
              SliverToBoxAdapter(child: _categories()),
              if (!snap.hasData)
                const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()))
              else if (_filtering) ...[
                SliverToBoxAdapter(
                  child: SectionTitle(
                    _type != null ? itemTypes[_type] ?? 'Résultats' : 'Résultats',
                    action: 'Effacer',
                    onAction: () => setState(() {
                      _type = null;
                      _query = '';
                      _search.clear();
                    }),
                  ),
                ),
                _grid(filtered),
              ] else ...[
                SliverToBoxAdapter(child: _offers(shopId)),
                if (popularList.isNotEmpty) ...[
                  const SliverToBoxAdapter(child: SectionTitle('Services populaires')),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 292,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: popularList.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (_, i) =>
                            ItemCard(item: popularList[i], width: 170),
                      ),
                    ),
                  ),
                ],
                const SliverToBoxAdapter(child: SectionTitle('Tous nos services')),
                _grid(all),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          );
        },
      ),
    );
  }

  Widget _header(int cartCount, Session session) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppConfig.green, Color(0xFF156B05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
          16, MediaQuery.of(context).padding.top + 12, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 46,
              height: 46,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Image.asset(AppConfig.logo, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppConfig.shopName,
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5)),
                  Text(AppConfig.slogan,
                      style: TextStyle(color: Colors.white70, fontSize: 12.5)),
                ],
              ),
            ),
            InboxBell(
              uid: session.uid,
              seenAt: session.user?.inboxSeenAt,
              color: Colors.white,
            ),
            IconButton(
              onPressed: _openCart,
              icon: Badge(
                isLabelVisible: cartCount > 0,
                label: Text('$cartCount'),
                backgroundColor: Colors.black,
                child: const Icon(Icons.shopping_bag_outlined,
                    color: Colors.white, size: 28),
              ),
            ),
          ]),
          const SizedBox(height: 14),
          if (session.shops.isNotEmpty) ...[
            InkWell(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const ShopPickerScreen())),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.place_rounded, color: Colors.white70, size: 16),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    session.clientShopId.isEmpty
                        ? 'Choisir ma boutique'
                        : session.myShop.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
                const Icon(Icons.expand_more, color: Colors.white70),
              ]),
            ),
            const SizedBox(height: 10),
          ],
          TextField(
            controller: _search,
            onChanged: (v) => setState(() => _query = v),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Rechercher un service...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() {
                        _query = '';
                        _search.clear();
                      }),
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _categories() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
      child: Row(
        children: [
          for (final e in itemTypes.entries)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () =>
                    setState(() => _type = _type == e.key ? null : e.key),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: _type == e.key ? AppConfig.green : Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE0E6DC)),
                      ),
                      child: Icon(itemTypeIcons[e.key],
                          color:
                              _type == e.key ? Colors.white : AppConfig.green,
                          size: 28),
                    ),
                    const SizedBox(height: 6),
                    Text(e.value,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: const TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _offers(String shopId) {
    return StreamBuilder<List<Promotion>>(
      stream: _promos,
      builder: (context, snap) {
        final promos = (snap.data ?? const <Promotion>[])
            .where((p) => shopId.isEmpty || p.visibleIn(shopId))
            .toList();
        if (promos.isEmpty) {
          // Bandeau d'accueil par défaut quand aucune offre n'est publiée.
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: _WelcomeBanner(onChat: widget.onOpenChat),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('Nos offres'),
            SizedBox(
              height: 170,
              child: PageView.builder(
                controller: PageController(viewportFraction: 0.9),
                itemCount: promos.length,
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _PromoCard(promo: promos[i]),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _grid(List<CatalogItem> list) {
    if (list.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: EmptyState(
              icon: Icons.search_off_rounded,
              title: 'Aucun service trouvé',
              message: 'Essayez un autre mot ou une autre catégorie.'),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          mainAxisExtent: 292,
        ),
        delegate: SliverChildBuilderDelegate(
          (_, i) => ItemCard(item: list[i]),
          childCount: list.length,
        ),
      ),
    );
  }
}

class _WelcomeBanner extends StatelessWidget {
  final VoidCallback onChat;
  const _WelcomeBanner({required this.onChat});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppConfig.black,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Une question, un devis ?',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800)),
              SizedBox(height: 4),
              Text('Notre équipe vous répond directement dans l\'application.',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: AppConfig.lightGreen,
              minimumSize: const Size(0, 44)),
          onPressed: onChat,
          child: const Text('Discuter'),
        ),
      ]),
    );
  }
}

class _PromoCard extends StatelessWidget {
  final Promotion promo;
  const _PromoCard({required this.promo});

  Future<void> _open(BuildContext context) async {
    if (promo.itemId.isNotEmpty) {
      final item = await Db.catalogItem(promo.itemId);
      if (item != null && context.mounted) openItem(context, item);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(promoKinds[promo.kind] ?? '',
                style: const TextStyle(
                    color: AppConfig.green, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(promo.title,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(promo.description),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => _open(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(fit: StackFit.expand, children: [
          promo.imageUrl.isEmpty
              ? Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                        colors: [AppConfig.black, Color(0xFF2E3B2A)]),
                  ),
                )
              : ProductImage(promo.imageUrl),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black87],
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: AppConfig.lightGreen,
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(promoKinds[promo.kind] ?? 'Offre',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 6),
                Text(promo.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
                if (promo.description.isNotEmpty)
                  Text(promo.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
