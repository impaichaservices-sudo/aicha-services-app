import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_user.dart';
import '../state/cart.dart';
import '../utils.dart';
import '../widgets/product_image.dart';
import 'checkout_screen.dart';

class CartScreen extends StatelessWidget {
  final AppUser? user;
  const CartScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<Cart>();
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Mon panier')),
      body: cart.isEmpty
          ? const Center(child: Text('Votre panier est vide.'))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: cart.lines.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (_, i) {
                final l = cart.lines[i];
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: ProductImage(l.item.imageUrl, size: 60),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l.item.name, style: t.titleSmall),
                          if (l.fileName.isNotEmpty)
                            Text('📎 ${l.fileName}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.bodySmall),
                          if (l.note.isNotEmpty)
                            Text('📝 ${l.note}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: t.bodySmall),
                          Text(l.item.onQuote ? 'Sur devis' : fcfa(l.subtotal),
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    Column(children: [
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          onPressed: () => cart.setQty(l.key, l.qty - 1),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        Text('${l.qty}'),
                        IconButton(
                          onPressed: () => cart.setQty(l.key, l.qty + 1),
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ]),
                      TextButton(
                        onPressed: () => cart.remove(l.key),
                        child: const Text('Retirer'),
                      ),
                    ]),
                  ],
                );
              },
            ),
      bottomNavigationBar: cart.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (cart.needsQuote)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Certains articles sont sur devis : nous vous '
                          'communiquerons le prix final dans l\'appli.',
                          style: t.bodySmall,
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(cart.needsQuote ? 'Sous-total connu' : 'Sous-total'),
                              Text(fcfa(cart.subtotal), style: t.titleLarge),
                            ],
                          ),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => CheckoutScreen(user: user)),
                          ),
                          child: const Text('Commander'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
