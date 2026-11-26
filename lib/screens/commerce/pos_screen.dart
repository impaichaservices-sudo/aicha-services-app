import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config.dart';
import '../../models/commerce.dart';
import '../../services/commerce_service.dart';
import '../../services/notify_service.dart';
import '../../services/session.dart';
import '../../utils.dart';
import 'commerce_widgets.dart';

/// Caisse : « Nouvelle vente ». Fonctionne sans internet.
class PosScreen extends StatefulWidget {
  final String shopId;
  final CashSession session;
  const PosScreen({super.key, required this.shopId, required this.session});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  late final Stream<List<Product>> _products = Commerce.productsOf(widget.shopId);
  final _cart = <String, SaleLine>{};
  final _stock = <String, Product>{};
  String _q = '';
  bool _busy = false;

  int get _subtotal => _cart.values.fold(0, (a, l) => a + l.total);

  void _add(Product p) {
    final cur = _cart[p.id]?.qty ?? 0;
    if (p.trackStock && cur + 1 > p.stock) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Stock insuffisant : il reste ${p.stock} ${p.unit}(s) de ${p.name}.')));
      return;
    }
    setState(() {
      _cart.putIfAbsent(
          p.id,
          () => SaleLine(
              productId: p.id,
              name: p.name,
              unit: p.unit,
              price: p.sellPrice,
              qty: 0,
              trackStock: p.trackStock));
      _cart[p.id]!.qty++;
    });
  }

  /// Article ou prestation hors de la liste des produits (saisi à la main).
  Future<void> _freeItem() async {
    final name = TextEditingController();
    final price = TextEditingController();
    final qty = TextEditingController(text: '1');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Article libre'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text(
              'Pour vendre un article ou une prestation qui n\'est pas dans la liste '
              '(ex : impression, saisie, service). Le stock n\'est pas modifié.',
              style: TextStyle(fontSize: 12.5, color: Colors.black54),
            ),
            TextField(
              controller: name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Désignation'),
            ),
            TextField(
              controller: price,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Prix unitaire', suffixText: 'FCFA'),
            ),
            TextField(
              controller: qty,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Quantité'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Ajouter')),
        ],
      ),
    );
    final n = name.text.trim();
    final p = int.tryParse(price.text.trim()) ?? 0;
    final q = int.tryParse(qty.text.trim()) ?? 1;
    if (ok != true) return;
    if (n.isEmpty || p <= 0 || q <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Indiquez la désignation, le prix et la quantité.')));
      }
      return;
    }
    final key = 'libre_${DateTime.now().millisecondsSinceEpoch}';
    setState(() => _cart[key] = SaleLine(
        productId: key, name: n, unit: 'unité', price: p, qty: q, trackStock: false));
  }

  void _setQty(SaleLine l, int q) {
    final p = _stock[l.productId];
    if (q <= 0) {
      setState(() => _cart.remove(l.productId));
      return;
    }
    if (p != null && p.trackStock && q > p.stock) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Stock insuffisant : il reste ${p.stock}.')));
      return;
    }
    setState(() => l.qty = q);
  }

  Future<void> _editQty(SaleLine l) async {
    final c = TextEditingController(text: '${l.qty}');
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.name),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: 'Quantité', suffixText: l.unit),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, int.tryParse(c.text.trim()) ?? l.qty),
              child: const Text('OK')),
        ],
      ),
    );
    if (v != null) _setQty(l, v);
  }

  Future<void> _checkout() async {
    if (_cart.isEmpty) return;
    final s = sessionOf(context, listen: false);
    final r = await showModalBottomSheet<_Checkout>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CheckoutSheet(
        subtotal: _subtotal,
        canDiscount: s.can('discount'),
        canCredit: s.can('credit'),
      ),
    );
    if (r == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final sale = await Commerce.createSale(
        s: s,
        shopId: widget.shopId,
        session: widget.session,
        lines: _cart.values.toList(),
        discount: r.discount,
        payMethod: r.method,
        paid: r.paid,
        customerName: r.name,
        customerPhone: r.phone,
      );
      _alertLowStock(sale);
      if (!mounted) return;
      setState(() => _cart.clear());
      await _receipt(sale);
    } catch (e) {
      if (!mounted) return;
      final t = '$e';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t.contains('Timeout') || t.contains('unavailable') || t.contains('network')
              ? 'Première vente sur ce téléphone : connectez-vous une fois à internet '
                  '(le téléphone reçoit sa lettre de caisse), ensuite tout marche hors ligne.'
              : friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Prévient l'équipe quand une vente fait passer un produit en stock faible.
  void _alertLowStock(Sale v) {
    final low = <String>[];
    for (final l in v.lines) {
      final p = _stock[l.productId];
      if (p == null || !p.trackStock) continue;
      final after = p.stock - l.qty;
      if (after <= p.minStock && p.stock > p.minStock) low.add('${p.name} ($after restant)');
    }
    if (low.isEmpty) return;
    NotifyService.toStaff(
      shopId: widget.shopId,
      title: '⚠️ Stock faible',
      body: low.join(', '),
      data: {'type': 'stock', 'shopId': widget.shopId},
    );
  }

  String _receiptText(Sale v) {
    final b = StringBuffer()
      ..writeln('*${AppConfig.shopName}*')
      ..writeln('Reçu ${v.number}')
      ..writeln(timeLabel(v.at))
      ..writeln('');
    for (final l in v.lines) {
      b.writeln('${l.qty} × ${l.name} : ${fcfa(l.total)}');
    }
    b.writeln('');
    if (v.discount > 0) b.writeln('Remise : -${fcfa(v.discount)}');
    b.writeln('*Total : ${fcfa(v.total)}*');
    b.writeln('Paiement : ${payMethods[v.payMethod]}');
    if (v.due > 0) b.writeln('Payé : ${fcfa(v.paid)} — Reste à payer : ${fcfa(v.due)}');
    b.writeln('');
    b.writeln('Merci pour votre confiance !');
    return b.toString();
  }

  Future<void> _receipt(Sale v) async {
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.check_circle_rounded, color: AppConfig.green, size: 48),
        title: Text('Vente ${v.number}'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final l in v.lines) SumRow('${l.qty} × ${l.name}', fcfa(l.total)),
            const Divider(),
            if (v.discount > 0) SumRow('Remise', '-${fcfa(v.discount)}'),
            SumRow('Total', fcfa(v.total), bold: true),
            SumRow('Paiement', payMethods[v.payMethod] ?? v.payMethod),
            if (v.due > 0) SumRow('Reste à payer', fcfa(v.due), color: Colors.red),
            const SizedBox(height: 10),
            const Text(
              'Vente enregistrée sur le téléphone. Elle sera envoyée automatiquement '
              'si internet est coupé.',
              style: TextStyle(fontSize: 12.5, color: Colors.black54),
            ),
          ]),
        ),
        actions: [
          if (v.customerPhone.isNotEmpty)
            TextButton.icon(
              onPressed: () => launchUrl(whatsappUri(v.customerPhone, _receiptText(v)),
                  mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.chat_rounded),
              label: const Text('Reçu WhatsApp'),
            ),
          FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Nouvelle vente')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nouvelle vente')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search), hintText: 'Rechercher un produit'),
                onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: _freeItem,
              icon: const Icon(Icons.edit_note),
              label: const Text('Article libre'),
            ),
          ]),
        ),
        Expanded(
          flex: 5,
          child: StreamBuilder<List<Product>>(
            stream: _products,
            builder: (context, snap) {
              if (snap.hasError) return Center(child: Text(friendlyError(snap.error)));
              final all = (snap.data ?? const <Product>[]).where((p) => p.active).toList();
              for (final p in all) {
                _stock[p.id] = p;
              }
              final list = _q.isEmpty
                  ? all
                  : all
                      .where((p) =>
                          p.name.toLowerCase().contains(_q) ||
                          p.ref.toLowerCase().contains(_q) ||
                          p.barcode.contains(_q))
                      .toList();
              if (snap.data == null) return const Center(child: CircularProgressIndicator());
              if (list.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text('Aucun produit dans la liste.',
                          style: TextStyle(color: Colors.black54)),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _freeItem,
                        icon: const Icon(Icons.edit_note),
                        label: const Text('Vendre un article libre'),
                      ),
                    ]),
                  ),
                );
              }
              return ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final p = list[i];
                  final inCart = _cart[p.id]?.qty ?? 0;
                  final empty = p.trackStock && p.stock <= 0;
                  return ListTile(
                    dense: true,
                    enabled: !empty,
                    title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(p.trackStock
                        ? 'Stock : ${p.stock}${p.lowStock ? ' (faible)' : ''}'
                        : 'Prestation'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(fcfa(p.sellPrice), style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(width: 8),
                      inCart > 0
                          ? CircleAvatar(
                              radius: 13,
                              backgroundColor: AppConfig.green,
                              child: Text('$inCart',
                                  style: const TextStyle(color: Colors.white, fontSize: 12)))
                          : const Icon(Icons.add_circle, color: AppConfig.green),
                    ]),
                    onTap: () => _add(p),
                  );
                },
              );
            },
          ),
        ),
        if (_cart.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: const BoxDecoration(
              color: Color(0xFFF1F7EF),
              border: Border(top: BorderSide(color: Color(0xFFCFE3C9))),
            ),
            child: ListView(shrinkWrap: true, children: [
              for (final l in _cart.values)
                ListTile(
                  dense: true,
                  title: Text(l.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${fcfa(l.price)} × ${l.qty} = ${fcfa(l.total)}'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () => _setQty(l, l.qty - 1)),
                    InkWell(
                      onTap: () => _editQty(l),
                      child: Text('${l.qty}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                    ),
                    IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () => _setQty(l, l.qty + 1)),
                    IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => _setQty(l, 0)),
                  ]),
                ),
            ]),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton(
                onPressed: _cart.isEmpty || _busy ? null : _checkout,
                child: Text(
                    _cart.isEmpty ? 'Ajoutez des produits' : 'Encaisser ${fcfa(_subtotal)}',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _Checkout {
  final int discount;
  final String method;
  final int paid;
  final String name;
  final String phone;
  const _Checkout(this.discount, this.method, this.paid, this.name, this.phone);
}

class _CheckoutSheet extends StatefulWidget {
  final int subtotal;
  final bool canDiscount;
  final bool canCredit;
  const _CheckoutSheet(
      {required this.subtotal, required this.canDiscount, required this.canCredit});

  @override
  State<_CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<_CheckoutSheet> {
  final _discount = TextEditingController();
  final _paid = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  String _method = 'especes';

  int get _disc {
    final d = int.tryParse(_discount.text.trim()) ?? 0;
    return d > widget.subtotal ? widget.subtotal : d;
  }

  int get _total => widget.subtotal - _disc;

  @override
  Widget build(BuildContext context) {
    final credit = _method == 'credit';
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Encaissement', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          SumRow('Sous-total', fcfa(widget.subtotal)),
          if (widget.canDiscount)
            TextField(
              controller: _discount,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Remise', suffixText: 'FCFA'),
              onChanged: (_) => setState(() {}),
            ),
          SumRow('Total à payer', fcfa(_total), bold: true),
          const SizedBox(height: 8),
          const Text('Moyen de paiement', style: TextStyle(fontWeight: FontWeight.w700)),
          Wrap(spacing: 8, children: [
            for (final e in payMethods.entries)
              if (e.key != 'credit' || widget.canCredit)
                ChoiceChip(
                  label: Text(e.value),
                  selected: _method == e.key,
                  onSelected: (_) => setState(() => _method = e.key),
                ),
          ]),
          if (credit)
            TextField(
              controller: _paid,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                  labelText: 'Montant payé maintenant (espèces)', suffixText: 'FCFA'),
              onChanged: (_) => setState(() {}),
            ),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: credit ? 'Nom du client (obligatoire)' : 'Nom du client (facultatif)'),
          ),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
                labelText: credit ? 'Téléphone du client (obligatoire)' : 'Téléphone (pour le reçu WhatsApp)'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: () {
              if (credit && (_name.text.trim().isEmpty || _phone.text.trim().isEmpty)) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Vente à crédit : nom et téléphone du client obligatoires.')));
                return;
              }
              Navigator.pop(
                context,
                _Checkout(_disc, _method, int.tryParse(_paid.text.trim()) ?? 0,
                    _name.text.trim(), _phone.text.trim()),
              );
            },
            child: Text('Valider la vente · ${fcfa(_total)}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ),
        ]),
      ),
    );
  }
}
