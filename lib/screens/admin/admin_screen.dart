import 'package:flutter/material.dart';

import '../../config.dart';
import '../../models/app_user.dart';
import '../../models/chat.dart';
import '../../models/order.dart';
import '../../services/db.dart';
import 'admin_catalog_screen.dart';
import 'admin_clients_screen.dart';
import 'admin_conversations_screen.dart';
import 'admin_orders_screen.dart';
import 'admin_promotions_screen.dart';
import 'admin_settings_screen.dart';

/// Espace Gestion : chiffres du jour + accès aux rubriques.
class AdminScreen extends StatefulWidget {
  final String uid;
  final AppUser? user;
  const AdminScreen({super.key, required this.uid, required this.user});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  late final Stream<List<ShopOrder>> _orders = Db.allOrders();
  late final Stream<List<Conversation>> _convs = Db.allConversations();

  AppUser get _me =>
      widget.user ?? AppUser(uid: widget.uid, name: 'Équipe', phone: '', email: '');

  void _push(Widget w) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text('Gestion'), automaticallyImplyLeading: false),
      body: StreamBuilder<List<ShopOrder>>(
        stream: _orders,
        builder: (context, os) {
          final orders = os.data ?? const <ShopOrder>[];
          final now = DateTime.now();
          final today = orders.where((o) =>
              o.createdAt != null &&
              o.createdAt!.year == now.year &&
              o.createdAt!.month == now.month &&
              o.createdAt!.day == now.day);
          final nouvelles = orders.where((o) => o.status == 'nouvelle').length;
          final enCours = orders
              .where((o) => o.status == 'confirmee' || o.status == 'en_cours')
              .length;
          final pretes = orders.where((o) => o.status == 'prete').length;
          final devis = orders
              .where((o) => o.quoteNeeded && o.quotedTotal == null && !o.isClosed)
              .length;
          return StreamBuilder<List<Conversation>>(
            stream: _convs,
            builder: (context, cs) {
              final unread = (cs.data ?? const <Conversation>[])
                  .fold<int>(0, (s, c) => s + c.unreadForShop);
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('Bonjour, ${AppConfig.shopName}',
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w900)),
                  Text('${today.length} commande${today.length > 1 ? 's' : ''} aujourd\'hui',
                      style: const TextStyle(color: Colors.black54)),
                  const SizedBox(height: 16),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.6,
                    children: [
                      _stat('Nouvelles commandes', nouvelles, Icons.fiber_new_rounded,
                          const Color(0xFF1565C0),
                          () => _push(AdminOrdersScreen(me: _me, initialFilter: 'nouvelles'))),
                      _stat('Commandes en cours', enCours, Icons.autorenew_rounded,
                          const Color(0xFFEF6C00),
                          () => _push(AdminOrdersScreen(me: _me, initialFilter: 'en_cours'))),
                      _stat('Commandes prêtes', pretes, Icons.inventory_2_rounded,
                          AppConfig.green,
                          () => _push(AdminOrdersScreen(me: _me, initialFilter: 'pretes'))),
                      _stat('Nouveaux messages', unread, Icons.mark_chat_unread_rounded,
                          const Color(0xFF6A1B9A),
                          () => _push(AdminConversationsScreen(me: _me))),
                    ],
                  ),
                  if (devis > 0) ...[
                    const SizedBox(height: 12),
                    Card(
                      color: const Color(0xFFFFF3E0),
                      child: ListTile(
                        leading: const Icon(Icons.request_quote_rounded,
                            color: Color(0xFFEF6C00)),
                        title: Text('$devis devis à préparer',
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () =>
                            _push(AdminOrdersScreen(me: _me, initialFilter: 'devis')),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  _menu(Icons.receipt_long_rounded, 'Commandes',
                      'Suivre et traiter les commandes',
                      () => _push(AdminOrdersScreen(me: _me))),
                  _menu(Icons.forum_rounded, 'Discussions',
                      'Répondre aux clients', () => _push(AdminConversationsScreen(me: _me)),
                      badge: unread),
                  _menu(Icons.grid_view_rounded, 'Catalogue',
                      'Services, prix, photos, formations',
                      () => _push(const AdminCatalogScreen())),
                  _menu(Icons.local_offer_rounded, 'Offres et nouveautés',
                      'Promotions, annonces, nouveaux services',
                      () => _push(const AdminPromotionsScreen())),
                  _menu(Icons.people_alt_rounded, 'Clients',
                      'Liste des clients inscrits',
                      () => _push(AdminClientsScreen(me: _me))),
                  _menu(Icons.settings_rounded, 'Réglages',
                      'Téléphone, WhatsApp, adresse, livraison',
                      () => _push(const AdminSettingsScreen())),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _stat(String label, int value, IconData icon, Color color,
      VoidCallback onTap) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                Icon(icon, color: color),
                const Spacer(),
                Text('$value',
                    style: TextStyle(
                        fontSize: 26, fontWeight: FontWeight.w900, color: color)),
              ]),
              Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13.5)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menu(IconData icon, String title, String subtitle, VoidCallback onTap,
      {int badge = 0}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: AppConfig.paleGreen,
                borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: AppConfig.green),
          ),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(subtitle),
          trailing: badge > 0
              ? Badge(label: Text('$badge'), child: const Icon(Icons.chevron_right))
              : const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      ),
    );
  }
}
