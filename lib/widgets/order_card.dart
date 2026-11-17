import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/order.dart';
import '../utils.dart';

/// Carte de commande, côté client et côté patron.
class OrderCard extends StatelessWidget {
  final ShopOrder order;
  final bool adminView;
  final List<Widget> actions;

  const OrderCard({
    super.key,
    required this.order,
    this.adminView = false,
    this.actions = const [],
  });

  Color _statusColor(BuildContext context) {
    switch (order.status) {
      case 'livree':
        return Colors.green;
      case 'annulee':
        return Theme.of(context).colorScheme.error;
      case 'prete':
        return Colors.teal;
      case 'nouvelle':
        return Theme.of(context).colorScheme.primary;
      default:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final o = order;
    final due = o.amountDue;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(
                  adminView ? o.buyerName : 'Commande n° ${o.shortId}',
                  style: t.titleMedium,
                ),
              ),
              Chip(
                label: Text(orderStatusLabels[o.status] ?? o.status),
                labelStyle: TextStyle(color: _statusColor(context)),
                side: BorderSide(color: _statusColor(context)),
                visualDensity: VisualDensity.compact,
              ),
            ]),
            Text(
              '${shortDate(o.createdAt)}'
              '${adminView ? ' • n° ${o.shortId}' : ''}'
              ' • ${o.isDelivery ? 'Livraison' : 'Retrait en boutique'}',
              style: t.bodySmall,
            ),
            const SizedBox(height: 8),
            for (final i in o.items) ...[
              Text('${i.qty} × ${i.name}  —  '
                  '${i.onQuote ? 'sur devis' : fcfa(i.price * i.qty)}'),
              if (i.note.isNotEmpty)
                Text('   📝 ${i.note}', style: t.bodySmall),
              if (i.fileUrl.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => launchUrl(Uri.parse(i.fileUrl),
                        mode: LaunchMode.externalApplication),
                    icon: const Icon(Icons.attach_file, size: 18),
                    label: Text(i.fileName.isEmpty ? 'Fichier' : i.fileName,
                        overflow: TextOverflow.ellipsis),
                  ),
                ),
            ],
            if (o.deliveryFee > 0) Text('Livraison : ${fcfa(o.deliveryFee)}'),
            const SizedBox(height: 6),
            Text(
              due == null ? 'Prix final : devis en préparation' : 'À payer : ${fcfa(due)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (o.adminNote.isNotEmpty)
              Text('💬 ${o.adminNote}', style: t.bodySmall),
            Text('${paymentMethodLabels[o.paymentMethod] ?? o.paymentMethod}'
                '${o.isOnlinePayment ? ' • ${paymentStatusLabels[o.paymentStatus] ?? o.paymentStatus}' : ''}'),
            if (adminView) ...[
              const SizedBox(height: 6),
              Text('📞 ${o.phone}'),
              if (o.isDelivery) Text('📍 ${o.address}, ${o.city}'),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: actions),
            ],
          ],
        ),
      ),
    );
  }
}
