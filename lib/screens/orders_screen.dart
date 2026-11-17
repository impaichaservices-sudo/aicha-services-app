import 'package:flutter/material.dart';

import '../models/order.dart';
import '../services/db.dart';
import '../services/payment_service.dart';
import '../widgets/order_card.dart';

class OrdersScreen extends StatefulWidget {
  final String uid;
  const OrdersScreen({super.key, required this.uid});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  late final Stream<List<ShopOrder>> _orders = Db.buyerOrders(widget.uid);

  Future<void> _pay(ShopOrder o) async {
    try {
      await PaymentService.pay(orderIds: [o.id], method: o.paymentMethod);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(PaymentService.message(e))));
    }
  }

  Future<void> _cancel(ShopOrder o) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Annuler la commande ?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Non')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Oui, annuler')),
        ],
      ),
    );
    if (ok == true) await Db.setOrderStatus(o.id, 'annulee');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mes commandes')),
      body: StreamBuilder<List<ShopOrder>>(
        stream: _orders,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Erreur : ${snap.error}'));
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snap.data!;
          if (list.isEmpty) {
            return const Center(child: Text('Aucune commande pour le moment.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            itemBuilder: (_, i) {
              final o = list[i];
              return OrderCard(
                order: o,
                actions: [
                  if (o.canPay)
                    FilledButton.icon(
                      onPressed: () => _pay(o),
                      icon: const Icon(Icons.payment),
                      label: const Text('Payer maintenant'),
                    ),
                  if (o.status == 'nouvelle' && o.paymentStatus != 'paye')
                    OutlinedButton(
                      onPressed: () => _cancel(o),
                      child: const Text('Annuler'),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
