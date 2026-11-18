import 'package:flutter/material.dart';

import '../../config.dart';
import '../../models/app_user.dart';
import '../../models/chat.dart';
import '../../models/order.dart';
import '../../services/db.dart';
import '../../services/session.dart';
import 'admin_catalog_screen.dart';
import 'admin_clients_screen.dart';
import 'admin_conversations_screen.dart';
import 'admin_notifications_screen.dart';
import 'admin_orders_screen.dart';
import 'admin_promotions_screen.dart';
import 'admin_settings_screen.dart';
import 'admin_shops_screen.dart';
import 'admin_team_screen.dart';

/// Gestion : Super Admin (toute l'entreprise) ou équipe d'une boutique.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  String? _scope; // boutique gérée (null = toutes)
  Stream<List<ShopOrder>>? _orders;
  Stream<List<Conversation>>? _convs;
  Stream<List<AppUser>>? _users;

  void _ensureStreams(String? scope, bool isSuper) {
    if (_orders != null && scope == _scope) return;
    _scope = scope;
    _orders = Db.allOrders(shopId: scope);
    _convs = Db.allConversations(shopId: scope);
    _users = isSuper ? Db.allUsers() : null;
  }

  void _push(Widget w) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    final s = sessionOf(context);
    if (!s.canManage) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final scope = s.managedShopId;
    _ensureStreams(scope, s.isSuper);
    final me = s.me;
    final title = s.isSuper
        ? 'ADMINISTRATION AÏCHA SERVICES'
        : 'Bonjour, ${s.shopById(scope!).name}';

    return Scaffold(
      appBar: AppBar(
          title: Text(s.isSuper ? 'Administration' : 'Gestion'),
          automaticallyImplyLeading: false),
      body: StreamBuilder<List<ShopOrder>>(
        stream: _orders,
        builder: (context, os) {
          final orders = os.data ?? const <ShopOrder>[];
          final now = DateTime.now();
          final today = orders
              .where((o) =>
                  o.createdAt != null &&
                  o.createdAt!.year == now.year &&
                  o.createdAt!.month == now.month &&
                  o.createdAt!.day == now.day)
              .length;
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
                  .fold<int>(0, (a, c) => a + c.unreadForShop);
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 21, fontWeight: FontWeight.w900)),
                  Text('$today commande${today > 1 ? 's' : ''} aujourd\'hui',
                      style: const TextStyle(color: Colors.black54)),
                  const SizedBox(height: 16),
                  if (s.isSuper)
                    StreamBuilder<List<AppUser>>(
                      stream: _users,
                      builder: (context, us) => _grid([
                        _stat('Boutiques actives', s.shops.length,
                            Icons.storefront_rounded, AppConfig.green,
                            () => _push(const AdminShopsScreen())),
                        _stat('Commandes aujourd\'hui', today,
                            Icons.today_rounded, const Color(0xFF1565C0),
                            () => _push(AdminOrdersScreen(me: me, shopId: scope))),
                        _stat('Clients', us.data?.length ?? 0,
                            Icons.people_alt_rounded, const Color(0xFF00838F),
                            () => _push(AdminClientsScreen(me: me, shopId: scope))),
                        _stat('Messages non lus', unread,
                            Icons.mark_chat_unread_rounded,
                            const Color(0xFF6A1B9A),
                            () => _push(AdminConversationsScreen(me: me, shopId: scope))),
                      ]),
                    ),
                  if (s.isSuper) const SizedBox(height: 12),
                  _grid([
                    _stat('Nouvelles commandes', nouvelles, Icons.fiber_new_rounded,
                        const Color(0xFF1565C0),
                        () => _push(AdminOrdersScreen(
                            me: me, shopId: scope, initialFilter: 'nouvelles'))),
                    _stat('Commandes en cours', enCours, Icons.autorenew_rounded,
                        const Color(0xFFEF6C00),
                        () => _push(AdminOrdersScreen(
                            me: me, shopId: scope, initialFilter: 'en_cours'))),
                    _stat('Commandes prêtes', pretes, Icons.inventory_2_rounded,
                        AppConfig.green,
                        () => _push(AdminOrdersScreen(
                            me: me, shopId: scope, initialFilter: 'pretes'))),
                    if (!s.isSuper)
                      _stat('Nouveaux messages', unread,
                          Icons.mark_chat_unread_rounded, const Color(0xFF6A1B9A),
                          () => _push(AdminConversationsScreen(me: me, shopId: scope)))
                    else
                      _stat('Devis à faire', devis, Icons.request_quote_rounded,
                          const Color(0xFFEF6C00),
                          () => _push(AdminOrdersScreen(
                              me: me, shopId: scope, initialFilter: 'devis'))),
                  ]),
                  if (!s.isSuper && devis > 0) ...[
                    const SizedBox(height: 12),
                    Card(
                      color: const Color(0xFFFFF3E0),
                      child: ListTile(
                        leading: const Icon(Icons.request_quote_rounded,
                            color: Color(0xFFEF6C00)),
                        title: Text('$devis devis à préparer',
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _push(AdminOrdersScreen(
                            me: me, shopId: scope, initialFilter: 'devis')),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (s.isSuper)
                    _menu(Icons.storefront_rounded, 'Boutiques',
                        'Créer, modifier, désactiver',
                        () => _push(const AdminShopsScreen())),
                  if (s.isSuper || (s.staff?.isManager ?? false))
                    _menu(Icons.badge_rounded, 'Équipe',
                        s.isSuper ? 'Responsables et agents' : 'Mes agents et leurs permissions',
                        () => _push(AdminTeamScreen(shopId: scope))),
                  _menu(Icons.receipt_long_rounded, 'Commandes',
                      'Suivre et traiter les commandes',
                      () => _push(AdminOrdersScreen(me: me, shopId: scope))),
                  _menu(Icons.forum_rounded, 'Discussions', 'Répondre aux clients',
                      () => _push(AdminConversationsScreen(me: me, shopId: scope)),
                      badge: unread),
                  if (s.can('clients'))
                    _menu(Icons.people_alt_rounded, 'Clients',
                        'Clients inscrits',
                        () => _push(AdminClientsScreen(me: me, shopId: scope))),
                  if (s.can('catalog'))
                    _menu(Icons.grid_view_rounded, 'Catalogue',
                        'Services, prix, photos, formations',
                        () => _push(AdminCatalogScreen(shopId: scope))),
                  if (s.can('promos'))
                    _menu(Icons.local_offer_rounded, 'Nouveautés et offres',
                        'Promotions, annonces, nouveaux services',
                        () => _push(AdminPromotionsScreen(shopId: scope))),
                  if (s.can('promos'))
                    _menu(Icons.campaign_rounded, 'Notifications',
                        'Envoyer un message à vos clients',
                        () => _push(AdminNotificationsScreen(shopId: scope))),
                  if (s.isSuper || (s.staff?.isManager ?? false))
                    _menu(Icons.settings_rounded,
                        s.isSuper ? 'Paramètres' : 'Réglages de la boutique',
                        s.isSuper
                            ? 'Paramètres généraux, fichiers, notifications'
                            : 'Adresse, téléphone, horaires, livraison',
                        () => _push(AdminSettingsScreen(shopId: scope))),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _grid(List<Widget> children) => GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.6,
        children: children,
      );

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
                  maxLines: 2,
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
