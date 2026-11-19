import 'package:flutter/material.dart';
import '../utils.dart';

import '../models/app_user.dart';
import '../models/order.dart';
import '../services/db.dart';
import '../widgets/common.dart';
import '../widgets/order_card.dart';
import 'order_detail_screen.dart';

const _filters = {
  'toutes': 'Toutes',
  'nouvelles': 'Nouvelles',
  'confirmees': 'Confirmées',
  'en_cours': 'En cours',
  'pretes': 'Prêtes',
  'terminees': 'Terminées',
  'devis': 'Mes devis',
};

bool orderMatches(ShopOrder o, String filter) {
  switch (filter) {
    case 'nouvelles':
      return o.status == 'nouvelle';
    case 'confirmees':
      return o.status == 'confirmee';
    case 'en_cours':
      return o.status == 'en_cours';
    case 'pretes':
      return o.status == 'prete';
    case 'terminees':
      return o.isClosed;
    case 'devis':
      return o.quoteNeeded;
  }
  return true;
}

/// Mes commandes : filtres + cartes avec progression.
class OrdersScreen extends StatefulWidget {
  final String uid;
  final AppUser? user;
  final String initialFilter;
  final bool standalone;
  final VoidCallback? onExplore;
  const OrdersScreen({
    super.key,
    required this.uid,
    required this.user,
    this.initialFilter = 'toutes',
    this.standalone = false,
    this.onExplore,
  });

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  late final Stream<List<ShopOrder>> _orders = Db.buyerOrders(widget.uid);
  late String _filter = widget.initialFilter;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_filter == 'devis' && widget.standalone
            ? 'Mes devis'
            : 'Mes commandes'),
        automaticallyImplyLeading: widget.standalone,
      ),
      body: Column(children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            children: [
              for (final f in _filters.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(f.value),
                    selected: _filter == f.key,
                    onSelected: (_) => setState(() => _filter = f.key),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<ShopOrder>>(
            stream: _orders,
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(child: Text(friendlyError(snap.error), textAlign: TextAlign.center));
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final list =
                  snap.data!.where((o) => orderMatches(o, _filter)).toList();
              if (list.isEmpty) {
                return EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: _filter == 'toutes' ? 'Aucune commande.' : 'Aucune commande ici',
                  message: 'Vous n\'avez encore aucune commande.',
                  action: widget.onExplore == null
                      ? null
                      : FilledButton(
                          onPressed: widget.onExplore,
                          child: const Text('Découvrir nos services')),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) => OrderCard(
                  order: list[i],
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => OrderDetailScreen(orderId: list[i].id))),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}
