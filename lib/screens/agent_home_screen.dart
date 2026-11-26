import 'package:flutter/material.dart';

import '../config.dart';
import '../models/chat.dart';
import '../models/commerce.dart';
import '../models/order.dart';
import '../services/commerce_service.dart';
import '../services/db.dart';
import '../services/session.dart';
import '../utils.dart';
import 'admin/admin_screen.dart';
import 'commerce/commerce_widgets.dart';
import 'commerce/customers_screen.dart';
import 'commerce/docs_screen.dart';
import 'commerce/inventory_screen.dart';
import 'commerce/pos_screen.dart';
import 'commerce/products_screen.dart';
import 'commerce/sales_screen.dart';

/// Accueil très simple des agents : de gros boutons, seulement ce qui est autorisé.
class AgentHomeScreen extends StatefulWidget {
  final void Function(int tab) onGoTo; // 1 = Discussions, 2 = Commandes, 3 = Équipe
  const AgentHomeScreen({super.key, required this.onGoTo});

  @override
  State<AgentHomeScreen> createState() => _AgentHomeScreenState();
}

class _AgentHomeScreenState extends State<AgentHomeScreen> {
  String _key = '';
  String _shopId = 'main';
  Stream<CashSession?>? _session;
  Stream<List<ShopOrder>>? _orders;
  Stream<List<Conversation>>? _convs;
  bool _busy = false;

  void _setup(Session s) {
    final shopId = s.staff?.shopId ?? 'main';
    final key = '$shopId|${s.uid}|${dayKey(DateTime.now())}';
    if (key == _key) return;
    _key = key;
    _shopId = shopId;
    _session = Commerce.sessionStream(Commerce.sessionId(shopId, s.uid, dayKey(DateTime.now())));
    _orders = Db.allOrders(shopId: shopId);
    _convs = Db.allConversations(shopId: shopId, agentUid: s.agentUid);
  }

  void _push(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

  /// « Nouvelle vente » : ouvre la caisse du jour si besoin, puis la caisse.
  Future<void> _sell(Session s, CashSession? c) async {
    if (c != null && c.closed) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Votre journée est déjà clôturée. Revenez demain pour vendre.')));
      return;
    }
    if (c != null) {
      _push(PosScreen(shopId: _shopId, session: c));
      return;
    }
    final f = await askAmount(context,
        title: 'Ouvrir la caisse du jour',
        label: 'Argent dans la caisse au départ',
        hint: '0 si la caisse est vide',
        initial: 0);
    if (f == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await Commerce.openSession(s, _shopId, f);
      final id = Commerce.sessionId(_shopId, s.uid, dayKey(DateTime.now()));
      final opened = await Commerce.sessionStream(id)
          .firstWhere((x) => x != null)
          .timeout(const Duration(seconds: 8));
      if (mounted && opened != null) _push(PosScreen(shopId: _shopId, session: opened));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Caisse ouverte. Touchez encore « Nouvelle vente ».')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _bigTile(IconData icon, String label, Color color, VoidCallback onTap, {int badge = 0}) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Badge(
              isLabelVisible: badge > 0,
              label: Text(badge > 99 ? '99+' : '$badge'),
              backgroundColor: Colors.red,
              child: CircleAvatar(
                radius: 28,
                backgroundColor: color.withOpacity(0.12),
                child: Icon(icon, color: color, size: 30),
              ),
            ),
            const SizedBox(height: 10),
            Text(label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = sessionOf(context);
    _setup(s);
    final shop = s.shopById(_shopId);
    final canSell = s.can('sales');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accueil'),
        actions: [
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.white70),
            onPressed: () => _push(const AdminScreen()),
            icon: const Icon(Icons.more_horiz),
            label: const Text('Plus'),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        Text(greetUser(s.me.name),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
        Text(shop.name, style: const TextStyle(color: AppConfig.green, fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        if (canSell)
          StreamBuilder<CashSession?>(
            stream: _session,
            builder: (context, snap) {
              final c = snap.data;
              final closed = c != null && c.closed;
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SizedBox(
                  height: 86,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: closed ? Colors.grey : AppConfig.green,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                    onPressed: _busy ? null : () => _sell(s, c),
                    icon: const Icon(Icons.add_shopping_cart_rounded, size: 34),
                    label: Text(closed ? 'JOURNÉE CLÔTURÉE' : 'NOUVELLE VENTE',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  c == null
                      ? 'Caisse pas encore ouverte aujourd\'hui'
                      : (closed ? 'Journée clôturée — à demain !' : 'Caisse ouverte'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black54),
                ),
                if (c != null) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                        onPressed: () => _push(SalesScreen(session: c, mine: true)),
                        icon: const Icon(Icons.receipt_long),
                        label: const Text('Mes ventes'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                            foregroundColor: closed ? null : const Color(0xFFB71C1C)),
                        onPressed: () => _push(ClosureScreen(session: c, mine: true)),
                        icon: Icon(closed ? Icons.lock : Icons.lock_clock),
                        label: Text(closed ? 'Ma clôture' : 'Clôturer'),
                      ),
                    ),
                  ]),
                ],
                const SizedBox(height: 18),
              ]);
            },
          ),
        StreamBuilder<List<ShopOrder>>(
          stream: _orders,
          builder: (context, os) => StreamBuilder<List<Conversation>>(
            stream: _convs,
            builder: (context, cs) {
              final newOrders =
                  (os.data ?? const <ShopOrder>[]).where((o) => o.status == 'nouvelle').length;
              final unread = (cs.data ?? const <Conversation>[])
                  .fold<int>(0, (a, c) => a + c.unreadForShop);
              final tiles = <Widget>[
                _bigTile(Icons.receipt_long_rounded, 'Commandes', const Color(0xFF1565C0),
                    () => widget.onGoTo(2), badge: newOrders),
                _bigTile(Icons.forum_rounded, 'Messages clients', const Color(0xFF6A1B9A),
                    () => widget.onGoTo(1), badge: unread),
                if (canSell || s.can('payments') || s.can('docs'))
                  _bigTile(Icons.people_alt_rounded, 'Clients et crédits', const Color(0xFF00838F),
                      () => _push(CustomersScreen(shopId: _shopId))),
                if (canSell || s.can('stock') || s.can('products'))
                  _bigTile(Icons.inventory_2_rounded, 'Produits et stock', const Color(0xFFEF6C00),
                      () => _push(ProductsScreen(shopId: _shopId))),
                if (s.can('stock'))
                  _bigTile(Icons.fact_check_rounded, 'Inventaire', const Color(0xFF37474F),
                      () => _push(InventoryScreen(shopId: _shopId))),
                if (s.can('docs'))
                  _bigTile(Icons.request_quote_rounded, 'Devis', const Color(0xFFEF6C00),
                      () => _push(DocsScreen(shopId: _shopId, kind: 'quote'))),
                if (s.can('docs'))
                  _bigTile(Icons.description_rounded, 'Factures', const Color(0xFF1565C0),
                      () => _push(DocsScreen(shopId: _shopId, kind: 'invoice'))),
                if (canSell)
                  _bigTile(Icons.event_note_rounded, 'Mes journées', const Color(0xFF5D4037),
                      () => _push(ClosuresScreen(shopId: _shopId, all: false))),
                _bigTile(Icons.groups_rounded, 'Mon équipe', AppConfig.green, () => widget.onGoTo(3)),
              ];
              return GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.15,
                children: tiles,
              );
            },
          ),
        ),
        const SizedBox(height: 20),
      ]),
    );
  }
}
