import 'package:flutter/material.dart';

import '../config.dart';
import '../models/order.dart';
import '../utils.dart';
import 'common.dart';

/// Carte de commande : numéro, service, quantité, montant, date, statut.
class OrderCard extends StatelessWidget {
  final ShopOrder order;
  final bool adminView;
  final VoidCallback? onTap;
  final List<Widget> actions;

  const OrderCard({
    super.key,
    required this.order,
    this.adminView = false,
    this.onTap,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final o = order;
    final due = o.amountDue;
    final color = statusColor(o.status);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text('#${o.displayNumber}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15)),
                const Spacer(),
                Pill(orderStatusLabels[o.status] ?? o.status, color: color),
              ]),
              const SizedBox(height: 6),
              if (adminView)
                Text(o.buyerName,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(o.itemsSummary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14.5)),
              const SizedBox(height: 2),
              Text(
                'Quantité : ${o.itemCount} • ${o.isDelivery ? 'Livraison' : 'Retrait'} • ${shortDate(o.createdAt)}',
                style: const TextStyle(color: Colors.black54, fontSize: 12.5),
              ),
              const SizedBox(height: 10),
              StatusProgress(status: o.status, compact: true),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: Text(
                    due == null ? 'Prix : devis en préparation' : fcfa(due),
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: due == null ? const Color(0xFFEF6C00) : AppConfig.black),
                  ),
                ),
                if (onTap != null) const Icon(Icons.chevron_right, color: Colors.black38),
              ]),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: actions),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
