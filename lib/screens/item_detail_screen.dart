import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../models/catalog_item.dart';
import '../services/auth_service.dart';
import '../services/db.dart';
import '../services/call_service.dart';
import '../services/session.dart';
import '../state/cart.dart';
import '../widgets/common.dart';
import '../widgets/product_image.dart';
import 'cart_screen.dart';
import 'chat_screen.dart';

/// Fiche service : grande image, prix, description, quantité, précisions.
class ItemDetailScreen extends StatefulWidget {
  final CatalogItem item;
  const ItemDetailScreen({super.key, required this.item});

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  final _note = TextEditingController();
  int _qty = 1;

  CatalogItem get item => widget.item;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _add() {
    context.read<Cart>().add(item, qty: _qty, note: _note.text.trim());
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(
      content: Text(item.onQuote
          ? 'Demande de devis ajoutée au panier'
          : 'Ajouté au panier'),
    ));
  }

  Future<void> _ask() async {
    final uid = AuthService.current?.uid;
    if (uid == null) return;
    final s = sessionOf(context, listen: false);
    final shopId = s.clientShopId.isEmpty ? 'main' : s.clientShopId;
    final user = await Db.userStream(uid).first;
    if (user == null || !mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatScreen(
        conversationId: Db.generalConversationId(uid),
        createIfMissing: Db.generalConversationData(user, shopId: shopId),
        title: 'Équipe ${s.teamName(shopId)}',
        asShop: false,
        me: user,
        shopId: shopId,
        aboutItem: item,
        initialText: 'Bonjour, je voudrais des informations sur cet article.',
      ),
    ));
  }

  Future<void> _call() async {
    final uid = AuthService.current?.uid;
    if (uid == null) return;
    final s = sessionOf(context, listen: false);
    final shopId = s.clientShopId.isEmpty ? 'main' : s.clientShopId;
    final user = await Db.userStream(uid).first;
    if (user == null || !mounted) return;
    CallService.openCall(
      context,
      conversationId: Db.generalConversationId(uid),
      createIfMissing: Db.generalConversationData(user, shopId: shopId),
      asShop: false,
      shopId: shopId,
      otherName: s.teamName(shopId),
      me: user,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cartCount = context.watch<Cart>().count;
    final maxQty = item.places > 0 ? item.placesLeft : 100000;
    final t = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: Colors.white,
            actions: [
              IconButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const CartScreen(user: null))),
                icon: Badge(
                  isLabelVisible: cartCount > 0,
                  label: Text('$cartCount'),
                  child: const Icon(Icons.shopping_bag_outlined),
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Hero(
                tag: 'item-${item.id}',
                child: ProductImage(item.imageUrl),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Pill(itemTypes[item.type] ?? item.type,
                        color: AppConfig.green, icon: itemTypeIcons[item.type]),
                    const SizedBox(width: 8),
                    item.canOrder
                        ? const Pill('Disponible',
                            color: AppConfig.green, icon: Icons.check_circle)
                        : Pill(item.isFull ? 'Complet' : 'Indisponible',
                            color: const Color(0xFFC62828),
                            icon: Icons.block),
                  ]),
                  const SizedBox(height: 12),
                  Text(item.name,
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.w800, height: 1.2)),
                  const SizedBox(height: 8),
                  Text(item.onQuote ? 'Prix sur devis' : item.priceLabel,
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: item.onQuote
                              ? const Color(0xFFEF6C00)
                              : AppConfig.green)),
                  if (item.onQuote)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                          'Envoyez votre demande : nous vous communiquerons le prix exact.',
                          style: TextStyle(color: Colors.black54)),
                    ),
                  if (item.isTraining) ...[
                    const SizedBox(height: 16),
                    _infoRow(Icons.event_rounded, 'Date',
                        item.schedule.isEmpty ? 'À confirmer' : item.schedule),
                    if (item.places > 0) ...[
                      _infoRow(Icons.groups_rounded, 'Places', '${item.places}'),
                      _infoRow(Icons.event_seat_rounded, 'Places restantes',
                          '${item.placesLeft}'),
                    ],
                  ],
                  if (item.description.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(item.description,
                        style: t.bodyLarge?.copyWith(height: 1.4)),
                  ],
                  if (item.extraInfo.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppConfig.paleGreen,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline, color: AppConfig.green),
                          const SizedBox(width: 8),
                          Expanded(child: Text(item.extraInfo)),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(
                      child: Text(item.isTraining ? 'Participants' : 'Quantité',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                    _qtyButton(Icons.remove,
                        _qty > 1 ? () => setState(() => _qty--) : null),
                    SizedBox(
                      width: 48,
                      child: Text('$_qty',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w800)),
                    ),
                    _qtyButton(Icons.add,
                        _qty < maxQty ? () => setState(() => _qty++) : null),
                  ]),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _note,
                    maxLines: 4,
                    minLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Précisions concernant votre commande',
                      alignLabelWithHint: true,
                      hintText: item.isTraining
                          ? 'Noms des participants, questions…'
                          : 'Couleur, taille, texte, noms, modèle, autres instructions…',
                    ),
                  ),
                  if (item.acceptsFile) ...[
                    const SizedBox(height: 12),
                    const Row(children: [
                      Icon(Icons.attach_file, size: 18, color: Colors.black54),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Vous pourrez envoyer votre fichier (logo, photo, PDF…) dans la discussion de votre commande.',
                          style: TextStyle(color: Colors.black54, fontSize: 13),
                        ),
                      ),
                    ]),
                  ],
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _ask,
                        icon: const Icon(Icons.chat_bubble_outline),
                        label: const Text('Discuter de ce service'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _call,
                      icon: const Icon(Icons.call),
                      label: const Text('Appeler'),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFE6EAE4))),
          ),
          child: FilledButton.icon(
            onPressed: item.canOrder ? _add : null,
            icon: Icon(item.onQuote
                ? Icons.request_quote_outlined
                : Icons.add_shopping_cart_rounded),
            label: Text(!item.canOrder
                ? (item.isFull
                    ? (item.isTraining ? 'Formation complète' : 'Complet')
                    : 'Indisponible')
                : item.onQuote
                    ? 'Demander un devis'
                    : item.isTraining
                        ? 'Réserver ma place'
                        : 'Ajouter au panier'),
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Icon(icon, size: 20, color: AppConfig.green),
          const SizedBox(width: 8),
          Text('$label : ', style: const TextStyle(color: Colors.black54)),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ]),
      );

  Widget _qtyButton(IconData icon, VoidCallback? onTap) => Material(
        color: onTap == null ? const Color(0xFFF0F2EE) : AppConfig.paleGreen,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon,
                color: onTap == null ? Colors.black26 : AppConfig.green),
          ),
        ),
      );
}
