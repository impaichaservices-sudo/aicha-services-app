import 'package:flutter/material.dart';

import '../models/catalog_item.dart';
import '../models/order.dart';
import '../services/db.dart';
import '../utils.dart';

/// Contrôle des prix d'une commande (côté équipe) : alerte si un prix
/// commandé ne correspond pas au catalogue, ou si les montants ne collent pas.
class PriceCheck extends StatelessWidget {
  final ShopOrder order;
  const PriceCheck({super.key, required this.order});

  static final Map<String, Future<CatalogItem?>> _cache = {};

  Future<List<String>> _problems() async {
    final out = <String>[];
    var sum = 0;
    for (final i in order.items) {
      sum += i.price * i.qty;
      if (i.itemId.isEmpty) continue;
      final it = await (_cache[i.itemId] ??= Db.catalogItem(i.itemId));
      if (it != null && it.price > 0 && it.price != i.price) {
        out.add('${i.name} : commandé à ${fcfa(i.price)}, '
            'prix du catalogue ${fcfa(it.price)}');
      }
    }
    if (sum != order.subtotal) {
      out.add('Sous-total incohérent : ${fcfa(order.subtotal)} au lieu de ${fcfa(sum)}');
    }
    if (order.total != order.subtotal + order.deliveryFee) {
      out.add('Total incohérent : ${fcfa(order.total)}');
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<String>>(
      future: _problems(),
      builder: (_, snap) {
        final p = snap.data ?? const <String>[];
        if (p.isEmpty) return const SizedBox.shrink();
        return Card(
          color: const Color(0xFFFFF3E0),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.warning_amber_rounded, color: Color(0xFFE65100)),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Vérifiez les prix avant de confirmer',
                      style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFE65100))),
                ),
              ]),
              const SizedBox(height: 6),
              for (final x in p)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text('• $x'),
                ),
              const SizedBox(height: 6),
              const Text(
                'Le prix a peut-être changé depuis la commande. En cas de doute, '
                'fixez le prix final avec « Fixer le prix final ».',
                style: TextStyle(fontSize: 12.5, color: Colors.black54),
              ),
            ]),
          ),
        );
      },
    );
  }
}
