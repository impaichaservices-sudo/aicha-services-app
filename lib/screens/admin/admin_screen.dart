import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config.dart';
import '../../models/catalog_item.dart';
import '../../models/order.dart';
import '../../models/shop_settings.dart';
import '../../services/db.dart';
import '../../utils.dart';
import '../../widgets/order_card.dart';
import '../../widgets/product_image.dart';
import 'item_form_screen.dart';

/// Espace du patron : commandes, catalogue et réglages de la boutique.
class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Gestion de la boutique'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Commandes'),
            Tab(text: 'Catalogue'),
            Tab(text: 'Réglages'),
          ]),
        ),
        body: const TabBarView(children: [
          _OrdersTab(),
          _CatalogTab(),
          _SettingsTab(),
        ]),
      ),
    );
  }
}

// ======================= COMMANDES =======================

class _OrdersTab extends StatefulWidget {
  const _OrdersTab();

  @override
  State<_OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<_OrdersTab>
    with AutomaticKeepAliveClientMixin {
  late final Stream<List<ShopOrder>> _orders = Db.allOrders();
  String _filter = 'a_traiter';

  @override
  bool get wantKeepAlive => true;

  bool _match(ShopOrder o) {
    switch (_filter) {
      case 'a_traiter':
        return !o.isClosed;
      case 'devis':
        return o.quoteNeeded && o.quotedTotal == null && !o.isClosed;
      case 'terminees':
        return o.isClosed;
    }
    return true;
  }

  Future<void> _setQuote(ShopOrder o) async {
    final amount = TextEditingController(
        text: (o.quotedTotal ?? (o.total > 0 ? o.total : '')).toString());
    final note = TextEditingController(text: o.adminNote);
    final key = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Prix final de la commande'),
        content: Form(
          key: key,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: amount,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                  labelText: 'Montant total (livraison comprise)',
                  suffixText: 'FCFA'),
              validator: (v) {
                final n = int.tryParse(v ?? '');
                if (n == null || n <= 0) return 'Montant invalide';
                if (n % 5 != 0) return 'Multiple de 5 svp';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              maxLines: 2,
              decoration: const InputDecoration(
                  labelText: 'Message au client (facultatif)',
                  hintText: 'Ex : prêt jeudi, papier 300 g'),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () {
                if (key.currentState!.validate()) Navigator.pop(ctx, true);
              },
              child: const Text('Envoyer')),
        ],
      ),
    );
    if (ok == true) {
      await Db.setQuote(o.id, int.parse(amount.text), note.text.trim());
    }
  }

  void _whatsapp(ShopOrder o) {
    final due = o.amountDue;
    final msg = 'Bonjour ${o.buyerName}, ici ${AppConfig.shopName}. '
        'Votre commande n° ${o.shortId} est '
        '« ${orderStatusLabels[o.status]} »'
        '${due == null ? '' : '. Montant : ${fcfa(due)}'}.';
    launchUrl(whatsappUri(o.phone, msg), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(children: [
      SizedBox(
        height: 52,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          children: [
            for (final f in const {
              'a_traiter': 'À traiter',
              'devis': 'Devis à faire',
              'terminees': 'Terminées',
              'toutes': 'Toutes',
            }.entries)
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
              return Center(child: Text('Erreur : ${snap.error}'));
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final list = snap.data!.where(_match).toList();
            if (list.isEmpty) {
              return const Center(child: Text('Aucune commande ici.'));
            }
            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: list.length,
              itemBuilder: (_, i) {
                final o = list[i];
                return OrderCard(
                  order: o,
                  adminView: true,
                  actions: [
                    IconButton.outlined(
                      tooltip: 'Appeler',
                      onPressed: () => launchUrl(Uri.parse('tel:${o.phone}')),
                      icon: const Icon(Icons.call),
                    ),
                    IconButton.outlined(
                      tooltip: 'WhatsApp',
                      onPressed: () => _whatsapp(o),
                      icon: const Icon(Icons.chat),
                    ),
                    if (!o.isClosed && (o.quoteNeeded || o.quotedTotal != null))
                      OutlinedButton.icon(
                        onPressed: () => _setQuote(o),
                        icon: const Icon(Icons.request_quote),
                        label: Text(
                            o.quotedTotal == null ? 'Fixer le prix' : 'Modifier le prix'),
                      ),
                    if (!o.isClosed)
                      PopupMenuButton<String>(
                        onSelected: (s) => Db.setOrderStatus(o.id, s),
                        itemBuilder: (_) => [
                          for (final s in [
                            'confirmee',
                            'en_cours',
                            'prete',
                            'livree',
                            'annulee'
                          ])
                            if (s != o.status)
                              PopupMenuItem(
                                  value: s, child: Text(orderStatusLabels[s]!)),
                        ],
                        child: const Chip(
                          avatar: Icon(Icons.edit, size: 18),
                          label: Text('Statut'),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    ]);
  }
}

// ======================= CATALOGUE =======================

class _CatalogTab extends StatefulWidget {
  const _CatalogTab();

  @override
  State<_CatalogTab> createState() => _CatalogTabState();
}

class _CatalogTabState extends State<_CatalogTab>
    with AutomaticKeepAliveClientMixin {
  late final Stream<List<CatalogItem>> _items =
      Db.catalogItems(onlyActive: false);

  @override
  bool get wantKeepAlive => true;

  void _open([CatalogItem? item]) => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ItemFormScreen(item: item)));

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return StreamBuilder<List<CatalogItem>>(
      stream: _items,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Erreur : ${snap.error}'));
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final list = snap.data!;
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            FilledButton.icon(
              onPressed: () => _open(),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter un service ou une formation'),
            ),
            const SizedBox(height: 8),
            if (list.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Votre catalogue est vide. Ajoutez par exemple : '
                  'cartes de visite, flyers, photocopies, formation Word/Excel…',
                  textAlign: TextAlign.center,
                ),
              ),
            for (final item in list)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ProductImage(item.imageUrl, size: 52),
                ),
                title: Text(item.name),
                subtitle: Text('${itemTypes[item.type]} • ${item.priceLabel}'
                    '${item.active ? '' : ' • masqué'}'),
                trailing: Switch(
                  value: item.active,
                  onChanged: (v) => Db.catalog.doc(item.id).update({'active': v}),
                ),
                onTap: () => _open(item),
              ),
          ],
        );
      },
    );
  }
}

// ======================= RÉGLAGES =======================

class _SettingsTab extends StatefulWidget {
  const _SettingsTab();

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab>
    with AutomaticKeepAliveClientMixin {
  final _form = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _whatsapp = TextEditingController();
  final _address = TextEditingController();
  final _hours = TextEditingController();
  final _fee = TextEditingController();
  bool _loaded = false;
  bool _busy = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    Db.settingsDoc.get().then((doc) {
      final s = ShopSettings.fromDoc(doc);
      _phone.text = s.phone;
      _whatsapp.text = s.whatsapp;
      _address.text = s.address;
      _hours.text = s.hours;
      _fee.text = s.deliveryFee.toString();
      if (mounted) setState(() => _loaded = true);
    }).catchError((_) {
      if (mounted) setState(() => _loaded = true);
    });
  }

  @override
  void dispose() {
    for (final c in [_phone, _whatsapp, _address, _hours, _fee]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await Db.saveSettings(ShopSettings(
        phone: _phone.text.trim(),
        whatsapp: _whatsapp.text.trim(),
        address: _address.text.trim(),
        hours: _hours.text.trim(),
        deliveryFee: int.tryParse(_fee.text) ?? 0,
      ));
      messenger.showSnackBar(const SnackBar(content: Text('Réglages enregistrés')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Téléphone de la boutique'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _whatsapp,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Numéro WhatsApp'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _address,
            maxLines: 2,
            decoration: const InputDecoration(
                labelText: 'Adresse de la boutique (pour le retrait)'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _hours,
            decoration: const InputDecoration(
                labelText: 'Horaires',
                hintText: 'Lun–Sam, 8h–19h'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _fee,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
                labelText: 'Frais de livraison', suffixText: 'FCFA'),
            validator: (v) {
              final n = int.tryParse(v ?? '0') ?? -1;
              if (n < 0) return 'Montant invalide';
              if (n % 5 != 0) return 'Multiple de 5 svp';
              return null;
            },
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Enregistrer'),
            ),
          ),
        ],
      ),
    );
  }
}
