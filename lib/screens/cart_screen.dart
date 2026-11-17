import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../models/app_user.dart';
import '../services/auth_service.dart';
import '../services/db.dart';
import '../state/cart.dart';
import '../utils.dart';
import '../widgets/common.dart';
import '../widgets/product_image.dart';
import 'checkout_screen.dart';

class CartScreen extends StatelessWidget {
  final AppUser? user;
  const CartScreen({super.key, required this.user});

  Future<void> _checkout(BuildContext context) async {
    var u = user;
    final uid = AuthService.current?.uid;
    if (u == null && uid != null) u = await Db.userStream(uid).first;
    if (!context.mounted) return;
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CheckoutScreen(user: u)));
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<Cart>();
    return Scaffold(
      appBar: AppBar(title: const Text('Mon panier')),
      body: cart.isEmpty
          ? EmptyState(
              icon: Icons.shopping_bag_outlined,
              title: 'Votre panier est vide',
              message: 'Ajoutez des services depuis l\'accueil.',
              action: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Découvrir nos services'),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: cart.lines.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) {
                final l = cart.lines[i];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: ProductImage(l.item.imageUrl, size: 72),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l.item.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700, fontSize: 15)),
                              if (l.note.isNotEmpty)
                                Text(l.note,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Colors.black54, fontSize: 13)),
                              const SizedBox(height: 4),
                              Text(
                                  l.item.onQuote ? 'Sur devis' : fcfa(l.subtotal),
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: l.item.onQuote
                                          ? const Color(0xFFEF6C00)
                                          : AppConfig.green)),
                              const SizedBox(height: 6),
                              Row(children: [
                                _small(Icons.remove,
                                    () => cart.setQty(l.key, l.qty - 1)),
                                SizedBox(
                                  width: 36,
                                  child: Text('${l.qty}',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800)),
                                ),
                                _small(Icons.add,
                                    () => cart.setQty(l.key, l.qty + 1)),
                                const Spacer(),
                                IconButton(
                                  tooltip: 'Retirer',
                                  onPressed: () => cart.remove(l.key),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ]),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      bottomNavigationBar: cart.isEmpty
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                color: Colors.white,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (cart.needsQuote)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Certains services sont sur devis : le prix final vous sera communiqué.',
                        style: TextStyle(color: Colors.black54, fontSize: 13),
                      ),
                    ),
                  Row(children: [
                    const Text('Sous-total',
                        style: TextStyle(fontSize: 15, color: Colors.black54)),
                    const Spacer(),
                    Text(fcfa(cart.subtotal),
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => _checkout(context),
                      child: const Text('Passer la commande'),
                    ),
                  ),
                ]),
              ),
            ),
    );
  }

  Widget _small(IconData icon, VoidCallback onTap) => Material(
        color: AppConfig.paleGreen,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(
              width: 34, height: 34, child: Icon(icon, size: 18, color: AppConfig.green)),
        ),
      );
}
