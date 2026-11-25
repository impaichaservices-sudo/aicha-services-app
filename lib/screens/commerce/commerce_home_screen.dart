import 'package:flutter/material.dart';

import '../../config.dart';
import '../../models/commerce.dart';
import '../../services/commerce_service.dart';
import '../../services/session.dart';
import '../../utils.dart';
import 'commerce_widgets.dart';
import 'customers_screen.dart';
import 'docs_screen.dart';
import 'inventory_screen.dart';
import 'pos_screen.dart';
import 'products_screen.dart';
import 'reports_screen.dart';
import 'sales_screen.dart';
import 'templates_screen.dart';

/// GESTION COMMERCIALE : caisse, stock, clôtures.
class CommerceHomeScreen extends StatefulWidget {
  const CommerceHomeScreen({super.key});

  @override
  State<CommerceHomeScreen> createState() => _CommerceHomeScreenState();
}

class _CommerceHomeScreenState extends State<CommerceHomeScreen> {
  String _shopId = '';
  String _key = '';
  Stream<CashSession?>? _session;
  Stream<List<Product>>? _products;
  Stream<List<Sale>>? _todayShop;
  Stream<List<Sale>>? _mySales;
  String _mySalesId = '';

  Stream<List<Sale>> _salesOf(CashSession c) {
    if (c.id != _mySalesId || _mySales == null) {
      _mySalesId = c.id;
      _mySales = Commerce.salesOfSession(c, mine: true);
    }
    return _mySales!;
  }

  void _setup(Session s) {
    if (_shopId.isEmpty) {
      _shopId = s.managedShopId ?? (s.shops.isNotEmpty ? s.shops.first.id : 'main');
    }
    final today = dayKey(DateTime.now());
    final key = '$_shopId|${s.uid}|$today';
    if (key == _key) return;
    _key = key;
    _session = Commerce.sessionStream(Commerce.sessionId(_shopId, s.uid, today));
    _products = Commerce.productsOf(_shopId);
    _todayShop = _seesShop(s) ? Commerce.salesOfDay(_shopId, today) : null;
  }

  bool _seesShop(Session s) =>
      s.isSuper || (s.staff?.isManager ?? false) || s.can('reports');

  Future<void> _open(Session s) async {
    final f = await askAmount(context,
        title: 'Ouvrir la caisse du jour',
        label: 'Fond de caisse (espèces au départ)',
        initial: 0);
    if (f == null) return;
    await Commerce.openSession(s, _shopId, f);
  }

  void _push(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

  Widget _tile(IconData icon, String title, String sub, VoidCallback onTap,
      {Color color = AppConfig.green, int badge = 0}) {
    return Card(
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(sub),
        trailing: badge > 0
            ? Badge(
                label: Text('$badge'),
                backgroundColor: Colors.red,
                child: const Icon(Icons.chevron_right))
            : const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  Widget _mySession(Session s) {
    return StreamBuilder<CashSession?>(
      stream: _session,
      builder: (context, snap) {
        final c = snap.data;
        if (snap.connectionState == ConnectionState.waiting && c == null) {
          return const Card(child: Padding(padding: EdgeInsets.all(20), child: LinearProgressIndicator()));
        }
        if (c == null) {
          return Card(
            color: const Color(0xFFF1F7EF),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Ma caisse aujourd\'hui',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                const SizedBox(height: 4),
                const Text('Journée non ouverte. Ouvrez la caisse pour commencer à vendre.'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  onPressed: () => _open(s),
                  icon: const Icon(Icons.point_of_sale_rounded),
                  label: const Text('Ouvrir la caisse'),
                ),
              ]),
            ),
          );
        }
        return StreamBuilder<List<Sale>>(
          stream: _salesOf(c),
          builder: (context, ss) {
            final sum = DaySummary.of(ss.data ?? const <Sale>[]);
            return Card(
              color: c.closed ? const Color(0xFFEFEFEF) : const Color(0xFFF1F7EF),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                          c.closed ? 'Journée clôturée' : 'Ma caisse aujourd\'hui',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                    ),
                    PendingIcon(c.pending),
                  ]),
                  const SizedBox(height: 6),
                  SumRow('${sum.count} vente(s)', fcfa(sum.total), bold: true),
                  SumRow('Encaissé', fcfa(sum.collected)),
                  if (sum.credit > 0) SumRow('Crédit', fcfa(sum.credit), color: Colors.red),
                  const SizedBox(height: 10),
                  if (!c.closed)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                      onPressed: () => _push(PosScreen(shopId: _shopId, session: c)),
                      icon: const Icon(Icons.add_shopping_cart_rounded),
                      label: const Text('NOUVELLE VENTE',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                    ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _push(SalesScreen(session: c, mine: true)),
                        child: const Text('Mes ventes'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _push(ClosureScreen(session: c, mine: true)),
                        child: Text(c.closed ? 'Voir la clôture' : 'Clôturer'),
                      ),
                    ),
                  ]),
                ]),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = sessionOf(context);
    _setup(s);
    final shop = s.shopById(_shopId);
    final canSell = s.can('sales');
    final seesShop = _seesShop(s);
    return Scaffold(
      appBar: AppBar(title: const Text('Gestion commerciale')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        if (s.isSuper && s.shops.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: DropdownButtonFormField<String>(
              value: s.shops.any((x) => x.id == _shopId) ? _shopId : null,
              decoration: const InputDecoration(labelText: 'Boutique'),
              items: [
                for (final x in s.shops) DropdownMenuItem(value: x.id, child: Text(x.name)),
              ],
              onChanged: (v) => setState(() {
                _shopId = v ?? _shopId;
                _key = '';
              }),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text('${shop.name} · ${dayLabel(dayKey(DateTime.now()))}',
                style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w600)),
          ),
        if (seesShop)
          StreamBuilder<List<Sale>>(
            stream: _todayShop,
            builder: (context, ts) {
              final sum = DaySummary.of(ts.data ?? const <Sale>[]);
              return Card(
                color: const Color(0xFF13261A),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Boutique aujourd\'hui',
                        style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(fcfa(sum.total),
                        style: const TextStyle(
                            color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
                    Text('${sum.count} vente(s) · encaissé ${fcfa(sum.collected)}'
                        '${sum.credit > 0 ? ' · crédit ${fcfa(sum.credit)}' : ''}',
                        style: const TextStyle(color: Colors.white70)),
                  ]),
                ),
              );
            },
          ),
        if (canSell) _mySession(s),
        const SizedBox(height: 6),
        StreamBuilder<List<Product>>(
          stream: _products,
          builder: (context, ps) {
            final list = ps.data ?? const <Product>[];
            final low = list.where((p) => p.lowStock).length;
            return Column(children: [
              if (low > 0)
                Card(
                  color: const Color(0xFFFFEBEE),
                  child: ListTile(
                    leading: const Icon(Icons.warning_amber_rounded, color: Colors.red),
                    title: Text('STOCK FAIBLE : $low produit(s)',
                        style: const TextStyle(
                            color: Colors.red, fontWeight: FontWeight.w900)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _push(ProductsScreen(shopId: _shopId, lowOnly: true)),
                  ),
                ),
              _tile(Icons.inventory_2_rounded, 'Produits et stock',
                  '${list.length} produit(s)', () => _push(ProductsScreen(shopId: _shopId)),
                  badge: low),
            ]);
          },
        ),
        if (canSell || s.can('docs') || s.can('payments') || seesShop)
          _tile(Icons.people_alt_rounded, 'Clients et crédits',
              'Fiches clients, ventes à crédit, paiements',
              () => _push(CustomersScreen(shopId: _shopId)),
              color: const Color(0xFF00838F)),
        if (s.can('docs'))
          _tile(Icons.request_quote_rounded, 'Devis', 'Créer, envoyer, transformer en facture',
              () => _push(DocsScreen(shopId: _shopId, kind: 'quote')),
              color: const Color(0xFFEF6C00)),
        if (s.can('docs'))
          _tile(Icons.receipt_long_rounded, 'Factures', 'Valider, signer, encaisser, PDF',
              () => _push(DocsScreen(shopId: _shopId, kind: 'invoice')),
              color: const Color(0xFF1565C0)),
        if (s.can('stock'))
          _tile(Icons.fact_check_rounded, 'Inventaire',
              'Compter le stock et corriger les écarts',
              () => _push(InventoryScreen(shopId: _shopId)),
              color: const Color(0xFF1565C0)),
        if (seesShop)
          _tile(Icons.insights_rounded, 'Tableau de bord et rapports',
              'Ventes, stock, caisse, agents · graphiques et PDF',
              () => _push(ReportsScreen(shopId: _shopId)),
              color: const Color(0xFF2E7D32)),
        if (seesShop)
          _tile(Icons.history_rounded, 'Historique des clôtures',
              'Journées de toute l\'équipe, par date',
              () => _push(ClosuresScreen(shopId: _shopId, all: true)),
              color: const Color(0xFF6A1B9A)),
        if (canSell)
          _tile(Icons.event_note_rounded, 'Mes journées', 'Mes clôtures précédentes',
              () => _push(ClosuresScreen(shopId: _shopId, all: false)),
              color: const Color(0xFFEF6C00)),
        if (s.isSuper || (s.staff?.isManager ?? false)) ...[
          _tile(Icons.design_services_rounded, 'Modèles de documents',
              'Présentation des devis et factures, informations légales, IA',
              () => _push(TemplatesScreen(shopId: _shopId)),
              color: const Color(0xFF6A1B9A)),
          _tile(Icons.manage_search_rounded, 'Journal d\'activité',
              'Qui a fait quoi, et quand', () => _push(ActivityScreen(shopId: _shopId)),
              color: const Color(0xFF37474F)),
        ],
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'Sans internet, tout continue de marcher : les opérations sont gardées sur le '
            'téléphone (icône nuage orange) et envoyées automatiquement au retour de la connexion.',
            style: TextStyle(color: Colors.black54, fontSize: 12.5),
          ),
        ),
      ]),
    );
  }
}
