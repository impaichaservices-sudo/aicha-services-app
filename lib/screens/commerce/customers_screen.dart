import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config.dart';
import '../../models/commerce.dart';
import '../../services/commerce_service.dart';
import '../../services/docs_service.dart';
import '../../services/session.dart';
import '../../utils.dart';
import 'commerce_widgets.dart';
import 'docs_screen.dart';

/// Reste à payer par vente / facture (montant dû − paiements reçus).
Map<String, int> paidByTarget(Iterable<Payment> list) {
  final m = <String, int>{};
  for (final p in list) {
    m[p.targetId] = (m[p.targetId] ?? 0) + p.amount;
  }
  return m;
}

/// Clients commerciaux de la boutique (et leurs crédits).
class CustomersScreen extends StatefulWidget {
  final String shopId;
  final bool creditOnly;
  const CustomersScreen({super.key, required this.shopId, this.creditOnly = false});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  late final Stream<List<Customer>> _customers = Commerce.customersOf(widget.shopId);
  late final Stream<List<Sale>> _credit = Commerce.creditSales(widget.shopId);
  late final Stream<List<Payment>> _salePays =
      Commerce.paymentsWhere(widget.shopId, 'targetType', 'sale');
  String _q = '';
  late bool _creditOnly = widget.creditOnly;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Clients et crédits')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => CustomerFormScreen(shopId: widget.shopId))),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Client'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Nom, téléphone, entreprise'),
            onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            FilterChip(
              label: const Text('Avec crédit en cours'),
              selected: _creditOnly,
              onSelected: (v) => setState(() => _creditOnly = v),
            ),
          ]),
        ),
        Expanded(
          child: StreamBuilder<List<Customer>>(
            stream: _customers,
            builder: (context, cs) => StreamBuilder<List<Sale>>(
              stream: _credit,
              builder: (context, ss) => StreamBuilder<List<Payment>>(
                stream: _salePays,
                builder: (context, ps) {
                  if (cs.hasError) return Center(child: Text(friendlyError(cs.error)));
                  final all = cs.data;
                  if (all == null) return const Center(child: CircularProgressIndicator());
                  final paid = paidByTarget(ps.data ?? const []);
                  final owed = <String, int>{};
                  for (final v in ss.data ?? const <Sale>[]) {
                    final r = v.due - (paid[v.id] ?? 0);
                    if (r > 0) owed[v.customerIdOrPhone(widget.shopId)] = (owed[v.customerIdOrPhone(widget.shopId)] ?? 0) + r;
                  }
                  final totalOwed = owed.values.fold<int>(0, (a, b) => a + b);
                  final list = all.where((c) {
                    if (_creditOnly && (owed[c.id] ?? 0) <= 0) return false;
                    if (_q.isEmpty) return true;
                    return c.name.toLowerCase().contains(_q) ||
                        c.phone.contains(_q) ||
                        c.company.toLowerCase().contains(_q);
                  }).toList();
                  return ListView(padding: const EdgeInsets.only(bottom: 90), children: [
                    if (totalOwed > 0)
                      Card(
                        margin: const EdgeInsets.all(12),
                        color: const Color(0xFFFFEBEE),
                        child: ListTile(
                          leading: const Icon(Icons.account_balance_wallet_rounded, color: Colors.red),
                          title: Text('Crédits clients : ${fcfa(totalOwed)}',
                              style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.red)),
                          subtitle: Text('${owed.length} client(s) doivent de l\'argent (ventes à crédit)'),
                        ),
                      ),
                    if (list.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: Text('Aucun client.', style: TextStyle(color: Colors.black54))),
                      ),
                    for (final c in list)
                      ListTile(
                        tileColor: Colors.white,
                        leading: CircleAvatar(
                          backgroundColor: AppConfig.green,
                          child: Text(c.name.isEmpty ? '?' : c.name[0].toUpperCase(),
                              style: const TextStyle(color: Colors.white)),
                        ),
                        title: Text(c.name.isEmpty ? c.phone : c.name,
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text([c.phone, if (c.company.isNotEmpty) c.company].join(' · ')),
                        trailing: (owed[c.id] ?? 0) > 0
                            ? Text(fcfa(owed[c.id]!),
                                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w900))
                            : null,
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => CustomerDetailScreen(customerId: c.id, shopId: widget.shopId))),
                      ),
                  ]);
                },
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

extension on Sale {
  String customerIdOrPhone(String shopId) => customerIdFor(shopId, customerPhone);
}

class CustomerFormScreen extends StatefulWidget {
  final String shopId;
  final Customer? customer;
  const CustomerFormScreen({super.key, required this.shopId, this.customer});

  @override
  State<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends State<CustomerFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _c = widget.customer;
  late final _name = TextEditingController(text: _c?.name ?? '');
  late final _phone = TextEditingController(text: _c?.phone ?? '');
  late final _address = TextEditingController(text: _c?.address ?? '');
  late final _city = TextEditingController(text: _c?.city ?? '');
  late final _company = TextEditingController(text: _c?.company ?? '');
  late final _email = TextEditingController(text: _c?.email ?? '');
  late final _notes = TextEditingController(text: _c?.notes ?? '');

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final s = sessionOf(context, listen: false);
    await Commerce.saveCustomer(
      s,
      Customer(
        id: '',
        shopId: widget.shopId,
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        address: _address.text.trim(),
        city: _city.text.trim(),
        company: _company.text.trim(),
        email: _email.text.trim(),
        notes: _notes.text.trim(),
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  Widget _f(TextEditingController c, String label, {TextInputType? kb, bool req = false, bool readOnly = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: c,
          readOnly: readOnly,
          keyboardType: kb,
          textCapitalization: kb == null ? TextCapitalization.words : TextCapitalization.none,
          decoration: InputDecoration(labelText: label),
          validator: req ? (v) => (v ?? '').trim().isEmpty ? 'Obligatoire' : null : null,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_c == null ? 'Nouveau client' : 'Modifier le client')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          _f(_name, 'Nom et prénom', req: true),
          _f(_phone, 'Téléphone', kb: TextInputType.phone, req: true, readOnly: _c != null),
          if (_c != null)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text('Le téléphone identifie le client (pas de doublon) : il ne se modifie pas.',
                  style: TextStyle(color: Colors.black54, fontSize: 12.5)),
            ),
          _f(_company, 'Entreprise'),
          _f(_address, 'Adresse'),
          _f(_city, 'Ville'),
          _f(_email, 'E-mail', kb: TextInputType.emailAddress),
          _f(_notes, 'Notes'),
          const SizedBox(height: 8),
          FilledButton(onPressed: _save, child: const Text('Enregistrer')),
        ]),
      ),
    );
  }
}

class CustomerDetailScreen extends StatefulWidget {
  final String customerId;
  final String shopId;
  const CustomerDetailScreen({super.key, required this.customerId, required this.shopId});

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  late final Stream<Customer?> _c = Commerce.customerStream(widget.customerId);
  late final Stream<List<Sale>> _sales = Commerce.salesOfCustomer(widget.shopId, widget.customerId);
  late final Stream<List<BizDoc>> _invoices = Docs.ofCustomer(widget.shopId, 'invoice', widget.customerId);
  late final Stream<List<BizDoc>> _quotes = Docs.ofCustomer(widget.shopId, 'quote', widget.customerId);
  late final Stream<List<Payment>> _pays =
      Commerce.paymentsWhere(widget.shopId, 'customerId', widget.customerId);

  Future<void> _pay(String type, String id, String number, int remaining) async {
    final s = sessionOf(context, listen: false);
    final r = await askPayment(context, remaining, number);
    if (r == null) return;
    await Commerce.recordPayment(
      s: s,
      shopId: widget.shopId,
      customerId: widget.customerId,
      targetType: type,
      targetId: id,
      targetNumber: number,
      amount: r.$1,
      method: r.$2,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Paiement enregistré (compté dans votre caisse du jour si elle est ouverte).')));
    }
  }

  Widget _title(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
      );

  @override
  Widget build(BuildContext context) {
    final s = sessionOf(context);
    final canPay = s.can('payments');
    return StreamBuilder<Customer?>(
      stream: _c,
      builder: (context, cs) {
        final c = cs.data;
        return Scaffold(
          appBar: AppBar(
            title: Text(c?.name ?? 'Client'),
            actions: [
              if (c != null)
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => CustomerFormScreen(shopId: widget.shopId, customer: c))),
                ),
            ],
          ),
          body: c == null
              ? const Center(child: CircularProgressIndicator())
              : StreamBuilder<List<Payment>>(
                  stream: _pays,
                  builder: (context, ps) {
                    final pays = ps.data ?? const <Payment>[];
                    final paid = paidByTarget(pays);
                    return ListView(padding: const EdgeInsets.all(12), children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            SumRow('Téléphone', c.phone),
                            if (c.company.isNotEmpty) SumRow('Entreprise', c.company),
                            if (c.address.isNotEmpty) SumRow('Adresse', '${c.address} ${c.city}'.trim()),
                            if (c.email.isNotEmpty) SumRow('E-mail', c.email),
                            if (c.notes.isNotEmpty) Text(c.notes, style: const TextStyle(color: Colors.black54)),
                            const SizedBox(height: 8),
                            Row(children: [
                              OutlinedButton.icon(
                                onPressed: () => launchUrl(Uri.parse('tel:${c.phone}')),
                                icon: const Icon(Icons.call),
                                label: const Text('Appeler'),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                onPressed: () => launchUrl(whatsappUri(c.phone),
                                    mode: LaunchMode.externalApplication),
                                icon: const Icon(Icons.chat),
                                label: const Text('WhatsApp'),
                              ),
                            ]),
                          ]),
                        ),
                      ),
                      StreamBuilder<List<Sale>>(
                        stream: _sales,
                        builder: (context, ss) {
                          final sales = (ss.data ?? const <Sale>[]).where((v) => !v.cancelled).toList();
                          final credit = sales.where((v) => v.due - (paid[v.id] ?? 0) > 0).toList();
                          final owed = credit.fold<int>(0, (a, v) => a + v.due - (paid[v.id] ?? 0));
                          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            _title('Crédits (ventes) : ${fcfa(owed)}'),
                            if (credit.isEmpty)
                              const Text('Aucun crédit en cours.', style: TextStyle(color: Colors.black54)),
                            for (final v in credit)
                              Card(
                                child: ListTile(
                                  title: Text(v.number, style: const TextStyle(fontWeight: FontWeight.w800)),
                                  subtitle: Text('${timeLabel(v.at)} · total ${fcfa(v.total)} · '
                                      'reste ${fcfa(v.due - (paid[v.id] ?? 0))}'),
                                  trailing: canPay
                                      ? FilledButton(
                                          onPressed: () => _pay('sale', v.id, v.number, v.due - (paid[v.id] ?? 0)),
                                          child: const Text('Payer'))
                                      : null,
                                ),
                              ),
                            _title('Achats (${sales.length})'),
                            for (final v in sales.take(30))
                              ListTile(
                                dense: true,
                                title: Text('${v.number} · ${fcfa(v.total)}'),
                                subtitle: Text('${timeLabel(v.at)} · ${payMethods[v.payMethod] ?? v.payMethod}'),
                              ),
                          ]);
                        },
                      ),
                      if (s.can('docs')) ...[
                        StreamBuilder<List<BizDoc>>(
                          stream: _invoices,
                          builder: (context, is_) {
                            final list = is_.data ?? const <BizDoc>[];
                            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              _title('Factures (${list.length})'),
                              for (final d in list)
                                Card(
                                  child: ListTile(
                                    title: Text(d.number, style: const TextStyle(fontWeight: FontWeight.w800)),
                                    subtitle: Text('${fcfa(d.total)} · ${d.displayStatus(paid[d.id] ?? 0)}'),
                                    trailing: canPay && d.status == 'validee' && d.total - (paid[d.id] ?? 0) > 0
                                        ? FilledButton(
                                            onPressed: () => _pay('invoice', d.id, d.number, d.total - (paid[d.id] ?? 0)),
                                            child: const Text('Payer'))
                                        : null,
                                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                                        builder: (_) => DocDetailScreen(kind: 'invoice', id: d.id))),
                                  ),
                                ),
                            ]);
                          },
                        ),
                        StreamBuilder<List<BizDoc>>(
                          stream: _quotes,
                          builder: (context, qs) {
                            final list = qs.data ?? const <BizDoc>[];
                            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              _title('Devis (${list.length})'),
                              for (final d in list)
                                ListTile(
                                  dense: true,
                                  title: Text('${d.number} · ${fcfa(d.total)}'),
                                  subtitle: Text(d.displayStatus(0)),
                                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                                      builder: (_) => DocDetailScreen(kind: 'quote', id: d.id))),
                                ),
                            ]);
                          },
                        ),
                      ],
                      _title('Paiements reçus (${pays.length})'),
                      for (final p in pays)
                        ListTile(
                          dense: true,
                          title: Text('${fcfa(p.amount)} · ${payMethods[p.method] ?? p.method}'),
                          subtitle: Text('${p.targetNumber} · ${timeLabel(p.at)} · ${p.userName}'),
                          trailing: PendingIcon(p.pending),
                        ),
                      const SizedBox(height: 40),
                    ]);
                  },
                ),
        );
      },
    );
  }
}
