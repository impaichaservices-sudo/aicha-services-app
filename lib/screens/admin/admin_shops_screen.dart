import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config.dart';
import '../../models/shop.dart';
import '../../services/db.dart';
import '../../utils.dart';
import '../../widgets/common.dart';

/// Super Admin → Boutiques : créer, modifier, désactiver.
class AdminShopsScreen extends StatefulWidget {
  const AdminShopsScreen({super.key});

  @override
  State<AdminShopsScreen> createState() => _AdminShopsScreenState();
}

class _AdminShopsScreenState extends State<AdminShopsScreen> {
  late final Stream<List<Shop>> _shops = Db.allShops();

  void _open([Shop? s]) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => ShopFormScreen(shop: s)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Boutiques')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(),
        icon: const Icon(Icons.add_business),
        label: const Text('Nouvelle boutique'),
      ),
      body: StreamBuilder<List<Shop>>(
        stream: _shops,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Erreur : ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final list = snap.data!;
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.storefront_outlined,
              title: 'Aucune boutique',
              message:
                  'Créez vos boutiques (Djidian, Kéniéba, Bamako…). Les clients choisiront la leur.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final s = list[i];
              return Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(12),
                  leading: CircleAvatar(
                    radius: 24,
                    backgroundColor: s.active ? AppConfig.green : Colors.grey,
                    child: Text(s.code.isEmpty ? '?' : s.code,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w800)),
                  ),
                  title: Text(s.name,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text([
                    if (s.locality.isNotEmpty) s.locality,
                    if (s.phone.isNotEmpty) s.phone,
                    'Livraison : ${fcfa(s.deliveryFee)}',
                  ].join(' • ')),
                  trailing: s.active
                      ? const Pill('Active', color: AppConfig.green)
                      : const Pill('Désactivée', color: Colors.grey),
                  onTap: () => _open(s),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class ShopFormScreen extends StatefulWidget {
  final Shop? shop;
  const ShopFormScreen({super.key, this.shop});

  @override
  State<ShopFormScreen> createState() => _ShopFormScreenState();
}

class _ShopFormScreenState extends State<ShopFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.shop?.name ?? 'Aïcha Services ');
  late final _code = TextEditingController(text: widget.shop?.code ?? '');
  late final _locality = TextEditingController(text: widget.shop?.locality ?? '');
  late final _address = TextEditingController(text: widget.shop?.address ?? '');
  late final _phone = TextEditingController(text: widget.shop?.phone ?? '');
  late final _whatsapp = TextEditingController(text: widget.shop?.whatsapp ?? '');
  late final _hours = TextEditingController(text: widget.shop?.hours ?? '');
  late final _fee =
      TextEditingController(text: (widget.shop?.deliveryFee ?? 0).toString());
  late bool _active = widget.shop?.active ?? true;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _code, _locality, _address, _phone, _whatsapp, _hours, _fee]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await Db.saveShop(widget.shop?.id, {
        'name': _name.text.trim(),
        'code': _code.text.trim().toUpperCase(),
        'locality': _locality.text.trim(),
        'address': _address.text.trim(),
        'phone': _phone.text.trim(),
        'whatsapp': _whatsapp.text.trim(),
        'hours': _hours.text.trim(),
        'deliveryFee': int.tryParse(_fee.text) ?? 0,
        'active': _active,
      });
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Boutique enregistrée')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Champ obligatoire' : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.shop == null ? 'Nouvelle boutique' : 'Modifier la boutique')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                  labelText: 'Nom', hintText: 'Aïcha Services Djidian'),
              validator: _required,
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                    LengthLimitingTextInputFormatter(4),
                  ],
                  decoration: const InputDecoration(
                      labelText: 'Code', hintText: 'DJD', helperText: 'AS-DJD-00125'),
                  validator: _required,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _locality,
                  decoration: const InputDecoration(labelText: 'Localité'),
                  validator: _required,
                ),
              ),
            ]),
            const SizedBox(height: 12),
            TextFormField(
              controller: _address,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Adresse'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Téléphone'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _whatsapp,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'WhatsApp'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _hours,
              decoration: const InputDecoration(
                  labelText: 'Horaires', hintText: 'Lun–Sam, 8h–19h'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _fee,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                  labelText: 'Frais de livraison', suffixText: 'FCFA'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Boutique active'),
              subtitle: const Text('Désactivée : les clients ne la voient plus'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _busy ? null : _save,
            child: const Text('Enregistrer'),
          ),
        ),
      ),
    );
  }
}
