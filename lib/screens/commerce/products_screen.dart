import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config.dart';
import '../../models/commerce.dart';
import '../../services/commerce_service.dart';
import '../../services/notify_service.dart';
import '../../services/session.dart';
import '../../utils.dart';
import 'commerce_widgets.dart';

/// Produits et stock d'une boutique.
class ProductsScreen extends StatefulWidget {
  final String shopId;
  final bool lowOnly;
  const ProductsScreen({super.key, required this.shopId, this.lowOnly = false});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  late final Stream<List<Product>> _products = Commerce.productsOf(widget.shopId);
  String _q = '';
  late bool _low = widget.lowOnly;

  @override
  Widget build(BuildContext context) {
    final s = sessionOf(context);
    final canEdit = s.can('products');
    final seeBuy = s.can('products');
    return Scaffold(
      appBar: AppBar(title: const Text('Produits et stock')),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ProductFormScreen(shopId: widget.shopId))),
              icon: const Icon(Icons.add),
              label: const Text('Produit'),
            )
          : null,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search), hintText: 'Nom, référence ou code-barres'),
            onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            FilterChip(
              label: const Text('Stock faible'),
              selected: _low,
              onSelected: (v) => setState(() => _low = v),
            ),
          ]),
        ),
        Expanded(
          child: StreamBuilder<List<Product>>(
            stream: _products,
            builder: (context, snap) {
              if (snap.hasError) return Center(child: Text(friendlyError(snap.error)));
              final all = snap.data;
              if (all == null) return const Center(child: CircularProgressIndicator());
              final list = all.where((p) {
                if (_low && !p.lowStock) return false;
                if (_q.isEmpty) return true;
                return p.name.toLowerCase().contains(_q) ||
                    p.ref.toLowerCase().contains(_q) ||
                    p.barcode.contains(_q);
              }).toList();
              if (list.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      all.isEmpty
                          ? 'Aucun produit. ${canEdit ? 'Touchez « Produit » pour créer le premier.' : ''}'
                          : 'Aucun résultat.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.only(bottom: 90),
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final p = list[i];
                  return ListTile(
                    tileColor: p.active ? Colors.white : const Color(0xFFF2F2F2),
                    title: Text(p.name,
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            decoration: p.active ? null : TextDecoration.lineThrough)),
                    subtitle: Text([
                      if (p.ref.isNotEmpty) p.ref,
                      fcfa(p.sellPrice),
                      if (seeBuy && p.buyPrice > 0) 'achat ${fcfa(p.buyPrice)}',
                    ].join(' · ')),
                    trailing: p.trackStock
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('${p.stock}',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      color: p.lowStock ? Colors.red : AppConfig.green)),
                              Text(p.lowStock ? 'STOCK FAIBLE' : p.unit,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: p.lowStock ? Colors.red : Colors.black54,
                                      fontWeight: FontWeight.w700)),
                            ],
                          )
                        : const Text('prestation', style: TextStyle(color: Colors.black54)),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ProductDetailScreen(productId: p.id, shopId: p.shopId))),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}

/// Fiche produit : stock, mouvements, actions.
class ProductDetailScreen extends StatefulWidget {
  final String productId;
  final String shopId;
  const ProductDetailScreen({super.key, required this.productId, required this.shopId});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  late final Stream<Product?> _p = Commerce.productStream(widget.productId);
  late final Stream<List<StockMove>> _moves = Commerce.movesOf(widget.shopId, widget.productId);

  Future<void> _move(Product p) async {
    final s = sessionOf(context, listen: false);
    final type = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(
              title: Text('Mouvement de stock', style: TextStyle(fontWeight: FontWeight.w800))),
          for (final t in ['entree', 'sortie', 'retour', 'correction_plus', 'correction_moins'])
            ListTile(
              leading: Icon(
                  t == 'sortie' || t == 'correction_moins'
                      ? Icons.remove_circle_outline
                      : Icons.add_circle_outline,
                  color: t == 'sortie' || t == 'correction_moins' ? Colors.red : AppConfig.green),
              title: Text(moveTypes[t]!),
              onTap: () => Navigator.pop(c, t),
            ),
        ]),
      ),
    );
    if (type == null || !mounted) return;
    final qtyC = TextEditingController();
    final reasonC = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${moveTypes[type]} — ${p.name}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: qtyC,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: 'Quantité', suffixText: p.unit),
          ),
          TextField(
            controller: reasonC,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Motif (ex : livraison fournisseur)'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Enregistrer')),
        ],
      ),
    );
    final q = int.tryParse(qtyC.text.trim()) ?? 0;
    if (ok != true || q <= 0) return;
    final minus = type == 'sortie' || type == 'correction_moins';
    if (minus && q > p.stock && mounted) {
      final go = await confirm(context, 'Stock insuffisant',
          'Le stock affiché est ${p.stock}. Enregistrer quand même une sortie de $q ?');
      if (!go) return;
    }
    await Commerce.stockMove(s, p, minus ? -q : q, type,
        reasonC.text.trim().isEmpty ? moveTypes[type]! : reasonC.text.trim());
    final after = p.stock + (minus ? -q : q);
    if (p.trackStock && after <= p.minStock && p.stock > p.minStock) {
      NotifyService.toStaff(
        shopId: p.shopId,
        title: '⚠️ Stock faible',
        body: '${p.name} : $after restant (minimum ${p.minStock})',
        data: {'type': 'stock', 'shopId': p.shopId},
      );
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Mouvement enregistré (envoyé dès que possible).')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = sessionOf(context);
    return StreamBuilder<Product?>(
      stream: _p,
      builder: (context, ps) {
        final p = ps.data;
        return Scaffold(
          appBar: AppBar(
            title: Text(p?.name ?? 'Produit'),
            actions: [
              if (p != null && s.can('products'))
                IconButton(
                  tooltip: 'Modifier',
                  icon: const Icon(Icons.edit),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ProductFormScreen(shopId: p.shopId, product: p))),
                ),
            ],
          ),
          floatingActionButton: p != null && p.trackStock && s.can('stock')
              ? FloatingActionButton.extended(
                  onPressed: () => _move(p),
                  icon: const Icon(Icons.swap_vert),
                  label: const Text('Mouvement'),
                )
              : null,
          body: p == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (p.trackStock)
                          Row(children: [
                            Text('${p.stock}',
                                style: TextStyle(
                                    fontSize: 36,
                                    fontWeight: FontWeight.w900,
                                    color: p.lowStock ? Colors.red : AppConfig.green)),
                            const SizedBox(width: 8),
                            Text('${p.unit}(s) en stock'),
                            const Spacer(),
                            if (p.lowStock)
                              const Chip(
                                  label: Text('STOCK FAIBLE',
                                      style: TextStyle(
                                          color: Colors.white, fontWeight: FontWeight.w800)),
                                  backgroundColor: Colors.red),
                          ]),
                        SumRow('Prix de vente', fcfa(p.sellPrice), bold: true),
                        if (s.can('products')) SumRow('Prix d\'achat', fcfa(p.buyPrice)),
                        if (p.trackStock) SumRow('Stock minimum', '${p.minStock}'),
                        if (p.ref.isNotEmpty) SumRow('Référence', p.ref),
                        if (p.category.isNotEmpty) SumRow('Catégorie', p.category),
                        if (p.location.isNotEmpty) SumRow('Emplacement', p.location),
                        if (p.supplier.isNotEmpty) SumRow('Fournisseur', p.supplier),
                        if (p.barcode.isNotEmpty) SumRow('Code-barres', p.barcode),
                        if (!p.active) const SumRow('Statut', 'Inactif', color: Colors.red),
                      ]),
                    ),
                  ),
                  if (p.trackStock) ...[
                    const Padding(
                      padding: EdgeInsets.fromLTRB(4, 16, 4, 6),
                      child: Text('Mouvements de stock',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    ),
                    StreamBuilder<List<StockMove>>(
                      stream: _moves,
                      builder: (context, ms) {
                        final list = ms.data ?? const <StockMove>[];
                        if (list.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.all(12),
                            child: Text('Aucun mouvement.', style: TextStyle(color: Colors.black54)),
                          );
                        }
                        return Card(
                          child: Column(children: [
                            for (final m in list)
                              ListTile(
                                dense: true,
                                leading: Text(m.qty > 0 ? '+${m.qty}' : '${m.qty}',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16,
                                        color: m.qty > 0 ? AppConfig.green : Colors.red)),
                                title: Text('${moveTypes[m.type] ?? m.type} · ${m.reason}'),
                                subtitle: Text('${timeLabel(m.at)} · ${m.userName}'),
                                trailing: PendingIcon(m.pending),
                              ),
                          ]),
                        );
                      },
                    ),
                  ],
                ]),
        );
      },
    );
  }
}

/// Création / modification d'un produit.
class ProductFormScreen extends StatefulWidget {
  final String shopId;
  final Product? product;
  const ProductFormScreen({super.key, required this.shopId, this.product});

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _form = GlobalKey<FormState>();
  late final Product? _p = widget.product;
  late final _name = TextEditingController(text: _p?.name ?? '');
  late final _ref = TextEditingController(text: _p?.ref ?? '');
  late final _cat = TextEditingController(text: _p?.category ?? '');
  late final _desc = TextEditingController(text: _p?.description ?? '');
  late final _buy = TextEditingController(text: _p == null ? '' : '${_p!.buyPrice}');
  late final _sell = TextEditingController(text: _p == null ? '' : '${_p!.sellPrice}');
  late final _initial = TextEditingController();
  late final _min = TextEditingController(text: _p == null ? '' : '${_p!.minStock}');
  late final _loc = TextEditingController(text: _p?.location ?? '');
  late final _sup = TextEditingController(text: _p?.supplier ?? '');
  late final _bar = TextEditingController(text: _p?.barcode ?? '');
  late String _unit = _p?.unit ?? 'pièce';
  late bool _active = _p?.active ?? true;
  bool _busy = false;

  int _n(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final s = sessionOf(context, listen: false);
    setState(() => _busy = true);
    final p = Product(
      id: _p?.id ?? '',
      shopId: widget.shopId,
      name: _name.text.trim(),
      ref: _ref.text.trim(),
      category: _cat.text.trim(),
      description: _desc.text.trim(),
      unit: _unit,
      buyPrice: _n(_buy),
      sellPrice: _n(_sell),
      minStock: _n(_min),
      location: _loc.text.trim(),
      supplier: _sup.text.trim(),
      barcode: _bar.text.trim(),
      active: _active,
      trackStock: _unit != 'prestation',
    );
    if (_p == null) {
      await Commerce.createProduct(s, widget.shopId, p, _n(_initial));
    } else {
      await Commerce.updateProduct(s, p);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Widget _field(TextEditingController c, String label,
      {bool number = false, bool required = false, String? suffix}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        inputFormatters: number ? [FilteringTextInputFormatter.digitsOnly] : null,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: label, suffixText: suffix),
        validator: required ? (v) => (v ?? '').trim().isEmpty ? 'Obligatoire' : null : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = _p != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Modifier le produit' : 'Nouveau produit')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          _field(_name, 'Nom du produit', required: true),
          _field(_ref, 'Référence'),
          _field(_cat, 'Catégorie'),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DropdownButtonFormField<String>(
              value: productUnits.contains(_unit) ? _unit : 'pièce',
              decoration: const InputDecoration(labelText: 'Unité'),
              items: [
                for (final u in productUnits) DropdownMenuItem(value: u, child: Text(u)),
              ],
              onChanged: (v) => setState(() => _unit = v ?? 'pièce'),
            ),
          ),
          _field(_sell, 'Prix de vente', number: true, required: true, suffix: 'FCFA'),
          _field(_buy, 'Prix d\'achat', number: true, suffix: 'FCFA'),
          if (_unit != 'prestation') ...[
            if (!editing) _field(_initial, 'Stock initial', number: true),
            _field(_min, 'Stock minimum (alerte)', number: true),
            _field(_loc, 'Emplacement'),
          ],
          _field(_sup, 'Fournisseur'),
          _field(_bar, 'Code-barres'),
          _field(_desc, 'Description'),
          SwitchListTile(
            value: _active,
            onChanged: (v) => setState(() => _active = v),
            title: const Text('Produit actif'),
            subtitle: const Text('Inactif : n\'apparaît plus dans la caisse'),
          ),
          if (editing)
            const Padding(
              padding: EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                'Le stock ne se modifie pas ici : utilisez « Mouvement » ou « Inventaire » '
                '(chaque changement est enregistré).',
                style: TextStyle(color: Colors.black54, fontSize: 13),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: const Text('Enregistrer'),
          ),
        ]),
      ),
    );
  }
}
