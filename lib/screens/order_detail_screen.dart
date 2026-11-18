import 'package:flutter/material.dart';

import '../config.dart';
import '../models/app_user.dart';
import '../models/order.dart';
import '../services/auth_service.dart';
import '../services/db.dart';
import '../utils.dart';
import '../widgets/common.dart';
import 'chat_screen.dart';

/// Détail d'une commande côté client : progression, récapitulatif, discussion.
class OrderDetailScreen extends StatelessWidget {
  final String orderId;
  final bool justCreated;
  const OrderDetailScreen(
      {super.key, required this.orderId, this.justCreated = false});

  Future<void> _openChat(BuildContext context, ShopOrder o) async {
    final uid = AuthService.current!.uid;
    final me = await Db.userStream(uid).first ??
        AppUser(uid: uid, name: o.buyerName, phone: o.phone, email: '');
    if (!context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatScreen(
        conversationId: Db.orderConversationId(o.id),
        createIfMissing: Db.orderConversationData(o),
        title: 'Commande #${o.displayNumber}',
        subtitle: o.itemsSummary,
        asShop: false,
        me: me,
        shopId: o.shopId,
        orderId: o.id,
      ),
    ));
  }

  Future<void> _cancel(BuildContext context, ShopOrder o) async {
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
    if (ok == true) await Db.cancelOrder(o.id);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ShopOrder?>(
      stream: Db.orderStream(orderId),
      builder: (context, snap) {
        final o = snap.data;
        return Scaffold(
          appBar: AppBar(
              title: Text(o == null ? 'Commande' : 'Commande #${o.displayNumber}')),
          body: o == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (justCreated)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppConfig.green,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Row(children: [
                          Icon(Icons.check_circle, color: Colors.white, size: 32),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Commande envoyée ! Notre équipe vous répond ici, dans la discussion de la commande.',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ]),
                      ),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              const Text('Suivi',
                                  style: TextStyle(
                                      fontSize: 16, fontWeight: FontWeight.w800)),
                              const Spacer(),
                              Pill(orderStatusLabels[o.status] ?? o.status,
                                  color: statusColor(o.status)),
                            ]),
                            const SizedBox(height: 14),
                            StatusProgress(status: o.status),
                            const SizedBox(height: 10),
                            Text('Passée le ${shortDate(o.createdAt)}',
                                style: const TextStyle(
                                    color: Colors.black54, fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => _openChat(context, o),
                      icon: const Icon(Icons.chat_bubble_rounded),
                      label: const Text('Discuter de cette commande'),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Récapitulatif',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 10),
                            for (final i in o.items) ...[
                              Row(children: [
                                Expanded(child: Text('${i.qty} × ${i.name}')),
                                Text(i.onQuote ? 'Sur devis' : fcfa(i.price * i.qty),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                              ]),
                              if (i.note.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2, bottom: 4),
                                  child: Text(i.note,
                                      style: const TextStyle(
                                          color: Colors.black54, fontSize: 13)),
                                ),
                              const SizedBox(height: 6),
                            ],
                            const Divider(),
                            _line('Sous-total', fcfa(o.subtotal)),
                            _line('Livraison',
                                o.isDelivery ? fcfa(o.deliveryFee) : 'Retrait'),
                            _line(
                                'Total',
                                o.amountDue == null
                                    ? 'Devis en préparation'
                                    : fcfa(o.amountDue!),
                                bold: true),
                            if (o.adminNote.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text('💬 ${o.adminNote}'),
                              ),
                            const SizedBox(height: 8),
                            _line('Paiement',
                                paymentMethodLabels[o.paymentMethod] ?? o.paymentMethod),
                            _line(
                                'Réception',
                                o.isDelivery
                                    ? 'Livraison : ${o.address}, ${o.city}'
                                    : 'Retrait en boutique'),
                          ],
                        ),
                      ),
                    ),
                    if (o.status == 'nouvelle') ...[
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () => _cancel(context, o),
                        child: const Text('Annuler la commande'),
                      ),
                    ],
                  ],
                ),
        );
      },
    );
  }

  Widget _line(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              child: Text(label,
                  style: TextStyle(
                      color: Colors.black54,
                      fontWeight: bold ? FontWeight.w800 : FontWeight.w400)),
            ),
            Expanded(
              child: Text(value,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                      fontSize: bold ? 17 : 14,
                      color: bold ? AppConfig.green : null)),
            ),
          ],
        ),
      );
}
