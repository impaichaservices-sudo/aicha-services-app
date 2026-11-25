import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config.dart';
import '../../models/commerce.dart';
import '../../services/commerce_service.dart';
import '../../services/docs_service.dart';
import '../../services/pdf_service.dart';
import '../../services/session.dart';
import '../../utils.dart';
import 'commerce_widgets.dart';
import 'customers_screen.dart' show paidByTarget;
import 'signature_screen.dart';

String _kindTitle(String kind, {bool plural = false}) =>
    kind == 'quote' ? (plural ? 'Devis' : 'Devis') : (plural ? 'Factures' : 'Facture');

/// Liste des devis ou des factures.
class DocsScreen extends StatefulWidget {
  final String shopId;
  final String kind; // quote | invoice
  const DocsScreen({super.key, required this.shopId, required this.kind});

  @override
  State<DocsScreen> createState() => _DocsScreenState();
}

class _DocsScreenState extends State<DocsScreen> {
  late final Stream<List<BizDoc>> _docs = Docs.listOf(widget.shopId, widget.kind);
  late final Stream<List<Payment>> _pays =
      Commerce.paymentsWhere(widget.shopId, 'targetType', 'invoice');
  String _filter = '';
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final isInv = widget.kind == 'invoice';
    final statuses = isInv ? invoiceStatus : quoteStatus;
    return Scaffold(
      appBar: AppBar(title: Text(_kindTitle(widget.kind, plural: true))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => DocFormScreen(shopId: widget.shopId, kind: widget.kind))),
        icon: const Icon(Icons.add),
        label: Text(isInv ? 'Facture' : 'Devis'),
      ),
      body: StreamBuilder<List<BizDoc>>(
        stream: _docs,
        builder: (context, ds) => StreamBuilder<List<Payment>>(
          stream: _pays,
          builder: (context, ps) {
            if (ds.hasError) return Center(child: Text(friendlyError(ds.error)));
            final all = ds.data;
            if (all == null) return const Center(child: CircularProgressIndicator());
            final paid = paidByTarget(ps.data ?? const []);
            final list = all.where((d) {
              if (_filter.isNotEmpty && d.displayStatus(paid[d.id] ?? 0) != statuses[_filter]) {
                return false;
              }
              if (_q.isEmpty) return true;
              return d.number.toLowerCase().contains(_q) ||
                  d.customer.name.toLowerCase().contains(_q) ||
                  d.customer.phone.contains(_q);
            }).toList();
            final unpaid = isInv
                ? all
                    .where((d) => d.status == 'validee')
                    .fold<int>(0, (a, d) => a + (d.total - (paid[d.id] ?? 0)).clamp(0, d.total).toInt())
                : 0;
            return ListView(padding: const EdgeInsets.only(bottom: 90), children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: TextField(
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Numéro ou client'),
                  onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(children: [
                  ChoiceChip(
                      label: const Text('Tous'),
                      selected: _filter.isEmpty,
                      onSelected: (_) => setState(() => _filter = '')),
                  for (final e in statuses.entries)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: ChoiceChip(
                          label: Text(e.value),
                          selected: _filter == e.key,
                          onSelected: (_) => setState(() => _filter = e.key)),
                    ),
                ]),
              ),
              if (unpaid > 0)
                Card(
                  margin: const EdgeInsets.all(12),
                  color: const Color(0xFFFFEBEE),
                  child: ListTile(
                    leading: const Icon(Icons.warning_amber_rounded, color: Colors.red),
                    title: Text('Factures non payées : ${fcfa(unpaid)}',
                        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w900)),
                  ),
                ),
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('Rien à afficher.', style: TextStyle(color: Colors.black54))),
                ),
              for (final d in list)
                ListTile(
                  tileColor: Colors.white,
                  title: Text(d.number,
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          decoration: d.status.startsWith('annul') ? TextDecoration.lineThrough : null)),
                  subtitle: Text('${d.customer.name} · ${shortDate(d.at)}\n${d.displayStatus(paid[d.id] ?? 0)}'),
                  isThreeLine: true,
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(fcfa(d.total), style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(width: 6),
                    PendingIcon(d.pending),
                  ]),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => DocDetailScreen(kind: d.kind, id: d.id))),
                ),
            ]);
          },
        ),
      ),
    );
  }
}

/// Création / modification d'un brouillon.
class DocFormScreen extends StatefulWidget {
  final String shopId;
  final String kind;
  final BizDoc? doc;
  const DocFormScreen({super.key, required this.shopId, required this.kind, this.doc});

  @override
  State<DocFormScreen> createState() => _DocFormScreenState();
}

class _DocFormScreenState extends State<DocFormScreen> {
  late final BizDoc? _d = widget.doc;
  late final _name = TextEditingController(text: _d?.customer.name ?? '');
  late final _phone = TextEditingController(text: _d?.customer.phone ?? '');
  late final _company = TextEditingController(text: _d?.customer.company ?? '');
  late final _address = TextEditingController(text: _d?.customer.address ?? '');
  late final _email = TextEditingController(text: _d?.customer.email ?? '');
  late final _discount = TextEditingController(text: _d == null || _d!.discount == 0 ? '' : '${_d!.discount}');
  late final _tax = TextEditingController(text: _d == null || _d!.taxRate == 0 ? '' : '${_d!.taxRate}');
  late final _notes = TextEditingController(text: _d?.notes ?? '');
  late final List<DocLine> _lines = [for (final l in _d?.lines ?? const <DocLine>[]) l.copy()];
  @override
  void initState() {
    super.initState();
    if (_d == null) {
      Docs.settings(widget.shopId).then((st) {
        if (mounted && _notes.text.isEmpty && st.conditions.isNotEmpty) {
          setState(() => _notes.text = st.conditions);
        }
      });
    }
  }

  late String _date = _d?.dueDate ??
      dayKey(DateTime.now().add(Duration(days: widget.kind == 'quote' ? 15 : 30)));
  bool _busy = false;

  int _n(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;
  DocTotals get _totals => DocTotals.of(_lines, _n(_discount), _n(_tax));

  Future<void> _pickCustomer() async {
    final c = await showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CustomerPicker(shopId: widget.shopId),
    );
    if (c == null) return;
    setState(() {
      _name.text = c.name;
      _phone.text = c.phone;
      _company.text = c.company;
      _address.text = c.address;
      _email.text = c.email;
    });
  }

  Future<void> _addProduct() async {
    final p = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ProductPicker(shopId: widget.shopId),
    );
    if (p == null) return;
    setState(() => _lines.add(DocLine(
        ref: p.ref, name: p.name, unit: p.unit, price: p.sellPrice, productId: p.id)));
  }

  Future<void> _editLine([DocLine? line]) async {
    final l = line ?? DocLine(name: '');
    final name = TextEditingController(text: l.name);
    final ref = TextEditingController(text: l.ref);
    final qty = TextEditingController(text: '${l.qty}');
    final unit = TextEditingController(text: l.unit);
    final price = TextEditingController(text: l.price == 0 ? '' : '${l.price}');
    final disc = TextEditingController(text: l.discount == 0 ? '' : '${l.discount}');
    final digits = [FilteringTextInputFormatter.digitsOnly];
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(line == null ? 'Nouvelle ligne' : 'Modifier la ligne'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Désignation')),
            TextField(controller: ref, decoration: const InputDecoration(labelText: 'Référence')),
            Row(children: [
              Expanded(child: TextField(controller: qty, keyboardType: TextInputType.number,
                  inputFormatters: digits, decoration: const InputDecoration(labelText: 'Quantité'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: unit, decoration: const InputDecoration(labelText: 'Unité'))),
            ]),
            TextField(controller: price, keyboardType: TextInputType.number, inputFormatters: digits,
                decoration: const InputDecoration(labelText: 'Prix unitaire', suffixText: 'FCFA')),
            TextField(controller: disc, keyboardType: TextInputType.number, inputFormatters: digits,
                decoration: const InputDecoration(labelText: 'Remise sur la ligne', suffixText: 'FCFA')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('OK')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    setState(() {
      l
        ..name = name.text.trim()
        ..ref = ref.text.trim()
        ..qty = (int.tryParse(qty.text.trim()) ?? 1).clamp(1, 1000000).toInt()
        ..unit = unit.text.trim().isEmpty ? 'unité' : unit.text.trim()
        ..price = int.tryParse(price.text.trim()) ?? 0
        ..discount = int.tryParse(disc.text.trim()) ?? 0;
      if (line == null) _lines.add(l);
    });
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _phone.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nom et téléphone du client obligatoires.')));
      return;
    }
    if (_lines.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Ajoutez au moins une ligne.')));
      return;
    }
    final s = sessionOf(context, listen: false);
    final c = Customer(
      id: '',
      shopId: widget.shopId,
      name: _name.text.trim(),
      phone: _phone.text.trim(),
      company: _company.text.trim(),
      address: _address.text.trim(),
      email: _email.text.trim(),
    );
    setState(() => _busy = true);
    try {
      if (_d == null) {
        final id = await Docs.create(
          s: s,
          shopId: widget.shopId,
          kind: widget.kind,
          customer: c,
          lines: _lines,
          discount: _n(_discount),
          taxRate: _n(_tax),
          dueDate: _date,
          notes: _notes.text.trim(),
        );
        if (!mounted) return;
        Navigator.of(context).pushReplacement(MaterialPageRoute(
            builder: (_) => DocDetailScreen(kind: widget.kind, id: id)));
      } else {
        await Docs.updateDraft(s, _d!, c, _lines, _n(_discount), _n(_tax), _date, _notes.text.trim());
        if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final t = '$e';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t.contains('Timeout') || t.contains('unavailable')
              ? 'Premier document sur ce téléphone : connectez-vous une fois à internet.'
              : friendlyError(e))));
    }
  }

  Widget _f(TextEditingController c, String label, {TextInputType? kb}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: c,
          keyboardType: kb,
          textCapitalization: kb == null ? TextCapitalization.words : TextCapitalization.none,
          decoration: InputDecoration(labelText: label),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = _totals;
    final isQuote = widget.kind == 'quote';
    return Scaffold(
      appBar: AppBar(title: Text('${_d == null ? 'Nouveau' : 'Modifier'} ${isQuote ? 'devis' : 'facture'}')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const Expanded(child: Text('Client', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
                TextButton.icon(
                    onPressed: _pickCustomer,
                    icon: const Icon(Icons.person_search),
                    label: const Text('Client existant')),
              ]),
              _f(_name, 'Nom et prénom'),
              _f(_phone, 'Téléphone', kb: TextInputType.phone),
              _f(_company, 'Entreprise'),
              _f(_address, 'Adresse'),
              _f(_email, 'E-mail', kb: TextInputType.emailAddress),
            ]),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Articles', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              for (final l in _lines)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${l.qty} ${l.unit} × ${fcfa(l.price)}'
                      '${l.discount > 0 ? ' − ${fcfa(l.discount)}' : ''} = ${fcfa(l.total)}'),
                  onTap: () => _editLine(l),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => setState(() => _lines.remove(l)),
                  ),
                ),
              Wrap(spacing: 8, children: [
                OutlinedButton.icon(
                    onPressed: _addProduct,
                    icon: const Icon(Icons.inventory_2_outlined),
                    label: const Text('Produit')),
                OutlinedButton.icon(
                    onPressed: () => _editLine(),
                    icon: const Icon(Icons.edit_note),
                    label: const Text('Ligne libre')),
              ]),
            ]),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _discount,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Remise globale', suffixText: 'FCFA'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _tax,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Taxe', suffixText: '%'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ]),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: Text(isQuote ? 'Valable jusqu\'au ${dayLabel(_date)}' : 'Échéance : ${dayLabel(_date)}'),
                trailing: const Icon(Icons.edit_calendar),
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: DateTime.tryParse(_date) ?? DateTime.now(),
                    firstDate: DateTime(2025),
                    lastDate: DateTime(2035),
                  );
                  if (d != null) setState(() => _date = dayKey(d));
                },
              ),
              TextField(
                controller: _notes,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Conditions / remarques'),
              ),
              const SizedBox(height: 10),
              SumRow('Sous-total', fcfa(t.subtotal)),
              if (t.discount > 0) SumRow('Remise', '-${fcfa(t.discount)}'),
              if (t.tax > 0) SumRow('Taxe', fcfa(t.tax)),
              SumRow('TOTAL', fcfa(t.total), bold: true),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: _busy ? null : _save,
          child: const Text('Enregistrer le brouillon'),
        ),
        const SizedBox(height: 30),
      ]),
    );
  }
}

class _CustomerPicker extends StatefulWidget {
  final String shopId;
  const _CustomerPicker({required this.shopId});

  @override
  State<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends State<_CustomerPicker> {
  late final Stream<List<Customer>> _s = Commerce.customersOf(widget.shopId);
  String _q = '';

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      builder: (_, scroll) => Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            autofocus: true,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Rechercher un client'),
            onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Customer>>(
            stream: _s,
            builder: (context, snap) {
              final list = (snap.data ?? const <Customer>[])
                  .where((c) => _q.isEmpty || c.name.toLowerCase().contains(_q) || c.phone.contains(_q))
                  .toList();
              return ListView(controller: scroll, children: [
                for (final c in list)
                  ListTile(
                    title: Text(c.name),
                    subtitle: Text(c.phone),
                    onTap: () => Navigator.pop(context, c),
                  ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}

class _ProductPicker extends StatefulWidget {
  final String shopId;
  const _ProductPicker({required this.shopId});

  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  late final Stream<List<Product>> _s = Commerce.productsOf(widget.shopId);
  String _q = '';

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      builder: (_, scroll) => Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            autofocus: true,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Rechercher un produit'),
            onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Product>>(
            stream: _s,
            builder: (context, snap) {
              final list = (snap.data ?? const <Product>[])
                  .where((p) => p.active && (_q.isEmpty || p.name.toLowerCase().contains(_q) || p.ref.toLowerCase().contains(_q)))
                  .toList();
              return ListView(controller: scroll, children: [
                for (final p in list)
                  ListTile(
                    title: Text(p.name),
                    subtitle: Text(p.ref),
                    trailing: Text(fcfa(p.sellPrice)),
                    onTap: () => Navigator.pop(context, p),
                  ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}

/// Fiche d'un devis / d'une facture et ses actions.
class DocDetailScreen extends StatefulWidget {
  final String kind;
  final String id;
  const DocDetailScreen({super.key, required this.kind, required this.id});

  @override
  State<DocDetailScreen> createState() => _DocDetailScreenState();
}

class _DocDetailScreenState extends State<DocDetailScreen> {
  late final Stream<BizDoc?> _doc = Docs.stream(widget.kind, widget.id);
  Stream<List<Payment>>? _pays;
  bool _busy = false;

  Future<void> _run(Future<void> Function() f, String done) async {
    setState(() => _busy = true);
    try {
      await f();
      if (mounted && done.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pdf(BizDoc d, int paid) => _run(() async {
        final s = sessionOf(context, listen: false);
        final st = await Docs.settings(d.shopId);
        final bytes = await PdfService.doc(d, s.shopById(d.shopId), paid: paid, st: st);
        await PdfService.open(bytes, d.number);
      }, '');

  @override
  Widget build(BuildContext context) {
    final s = sessionOf(context);
    return StreamBuilder<BizDoc?>(
      stream: _doc,
      builder: (context, ds) {
        final d = ds.data;
        if (d == null) {
          return Scaffold(
              appBar: AppBar(title: Text(_kindTitle(widget.kind))),
              body: const Center(child: CircularProgressIndicator()));
        }
        _pays ??= Commerce.paymentsWhere(d.shopId, 'targetId', d.id);
        return StreamBuilder<List<Payment>>(
          stream: d.isInvoice ? _pays : null,
          builder: (context, ps) {
            final pays = ps.data ?? const <Payment>[];
            final paid = pays.fold<int>(0, (a, p) => a + p.amount);
            final remaining = d.total - paid;
            final canDocs = s.can('docs');
            final canCancel = s.isSuper || (s.staff?.isManager ?? false) || s.can('docCancel');
            final actions = <Widget>[
              FilledButton.icon(
                onPressed: _busy ? null : () => _pdf(d, paid),
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('PDF (voir, partager, imprimer)'),
              ),
            ];
            if (canDocs && d.isDraft) {
              actions.add(OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => DocFormScreen(shopId: d.shopId, kind: d.kind, doc: d))),
                icon: const Icon(Icons.edit),
                label: const Text('Modifier'),
              ));
            }
            final signable = canDocs && !d.signed &&
                (d.isDraft || (d.isInvoice && d.status == 'validee') || (!d.isInvoice && d.status != 'annule'));
            if (signable) {
              actions.add(OutlinedButton.icon(
                onPressed: () async {
                  final png = await Navigator.of(context).push<String>(MaterialPageRoute(
                      builder: (_) => SignatureScreen(title: 'Signer ${d.number}')));
                  if (png == null) return;
                  await _run(() => Docs.sign(s, d, png), 'Document signé.');
                },
                icon: const Icon(Icons.draw),
                label: const Text('Signer'),
              ));
            }
            if (canDocs && !d.isInvoice) {
              void st(String status, String label, IconData icon) => actions.add(OutlinedButton.icon(
                    onPressed: () => _run(() => Docs.setStatus(s, d, status), 'Devis : $label.'),
                    icon: Icon(icon),
                    label: Text(label),
                  ));
              if (d.status == 'brouillon') st('envoye', 'Marquer envoyé', Icons.send);
              if (d.status == 'brouillon' || d.status == 'envoye') {
                st('accepte', 'Accepté par le client', Icons.thumb_up);
                st('refuse', 'Refusé', Icons.thumb_down);
                st('expire', 'Expiré', Icons.timer_off);
              }
              if (d.status == 'accepte') {
                actions.add(FilledButton.icon(
                  onPressed: () => _run(() async {
                    final id = await Docs.convert(s, d);
                    if (!mounted) return;
                    Navigator.of(context).pushReplacement(MaterialPageRoute(
                        builder: (_) => DocDetailScreen(kind: 'invoice', id: id)));
                  }, ''),
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('Transformer en facture'),
                ));
              }
              if (!['converti', 'annule', 'refuse'].contains(d.status)) {
                st('annule', 'Annuler le devis', Icons.cancel_outlined);
              }
            }
            if (canDocs && d.isInvoice && d.isDraft) {
              actions.add(FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1565C0)),
                onPressed: () async {
                  final ok = await confirm(context, 'Valider ${d.number} ?',
                      'Une facture validée ne peut plus être modifiée. Pour la corriger, '
                      'il faudra l\'annuler et en créer une nouvelle.');
                  if (ok) await _run(() => Docs.setStatus(s, d, 'validee'), 'Facture validée.');
                },
                icon: const Icon(Icons.verified),
                label: const Text('Valider la facture'),
              ));
            }
            if (d.isInvoice && d.status == 'validee' && remaining > 0 && s.can('payments')) {
              actions.add(FilledButton.icon(
                onPressed: () async {
                  final r = await askPayment(context, remaining, d.number);
                  if (r == null) return;
                  await _run(
                      () => Commerce.recordPayment(
                            s: s,
                            shopId: d.shopId,
                            customerId: customerIdFor(d.shopId, d.customer.phone),
                            targetType: 'invoice',
                            targetId: d.id,
                            targetNumber: d.number,
                            amount: r.$1,
                            method: r.$2,
                          ),
                      'Paiement enregistré.');
                },
                icon: const Icon(Icons.payments),
                label: const Text('Enregistrer un paiement'),
              ));
            }
            if (d.isInvoice && d.status == 'validee' && canCancel) {
              actions.add(OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () async {
                  final reason = await askText(context, 'Annuler et corriger ${d.number}',
                      'Motif (obligatoire)');
                  if (reason == null || reason.isEmpty) return;
                  await _run(() async {
                    final id = await Docs.correct(s, d, reason);
                    if (!mounted) return;
                    Navigator.of(context).pushReplacement(MaterialPageRoute(
                        builder: (_) => DocDetailScreen(kind: 'invoice', id: id)));
                  }, 'Facture annulée ; nouvelle facture créée en brouillon.');
                },
                icon: const Icon(Icons.restart_alt),
                label: const Text('Annuler et créer une facture corrigée'),
              ));
            }
            return Scaffold(
              appBar: AppBar(title: Text('${d.title} ${d.number}')),
              body: ListView(padding: const EdgeInsets.all(12), children: [
                Card(
                  color: d.status.startsWith('annul') ? const Color(0xFFFFEBEE) : const Color(0xFFF1F7EF),
                  child: ListTile(
                    title: Text(d.displayStatus(paid),
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                    subtitle: Text([
                      'Créé par ${d.createdByName} · ${shortDate(d.at)}',
                      if (d.fromQuote.isNotEmpty) 'Devis d\'origine : ${d.fromQuote}',
                      if (d.replaces.isNotEmpty) 'Remplace : ${d.replaces}',
                      if (d.cancelReason.isNotEmpty) 'Motif : ${d.cancelReason}',
                      if (d.signed) 'Signé par ${d.signature['byName'] ?? ''}',
                    ].join('\n')),
                    trailing: PendingIcon(d.pending),
                  ),
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(d.customer.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                      if (d.customer.company.isNotEmpty) Text(d.customer.company),
                      Text(d.customer.phone),
                      if (d.customer.address.isNotEmpty) Text(d.customer.address),
                      const Divider(),
                      for (final l in d.lines)
                        SumRow('${l.qty} ${l.unit} × ${l.name}', fcfa(l.total)),
                      const Divider(),
                      SumRow('Sous-total', fcfa(d.subtotal)),
                      if (d.discount > 0) SumRow('Remise', '-${fcfa(d.discount)}'),
                      if (d.taxRate > 0) SumRow('Taxe (${d.taxRate} %)', fcfa(d.tax)),
                      SumRow('TOTAL', fcfa(d.total), bold: true),
                      if (d.isInvoice && paid > 0) ...[
                        SumRow('Payé', fcfa(paid), color: AppConfig.green),
                        SumRow('Reste à payer', fcfa(remaining < 0 ? 0 : remaining),
                            bold: true, color: remaining > 0 ? Colors.red : AppConfig.green),
                      ],
                      if (d.dueDate.isNotEmpty)
                        SumRow(d.isInvoice ? 'Échéance' : 'Valable jusqu\'au', dayLabel(d.dueDate)),
                      if (d.notes.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(d.notes, style: const TextStyle(color: Colors.black54)),
                        ),
                    ]),
                  ),
                ),
                for (final a in actions)
                  Padding(padding: const EdgeInsets.only(top: 8), child: a),
                if (pays.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 16, 4, 4),
                    child: Text('Paiements', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                  for (final p in pays)
                    ListTile(
                      dense: true,
                      title: Text('${fcfa(p.amount)} · ${payMethods[p.method] ?? p.method}'),
                      subtitle: Text('${timeLabel(p.at)} · ${p.userName}'),
                      trailing: PendingIcon(p.pending),
                    ),
                ],
                const SizedBox(height: 40),
              ]),
            );
          },
        );
      },
    );
  }
}
