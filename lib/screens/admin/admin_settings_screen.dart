import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/shop_settings.dart';
import '../../services/db.dart';

/// Gestion → Réglages : téléphone, WhatsApp, adresse, horaires, livraison.
class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  final _form = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _whatsapp = TextEditingController();
  final _address = TextEditingController();
  final _hours = TextEditingController();
  final _fee = TextEditingController();
  bool _loaded = false;
  bool _busy = false;

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
    return Scaffold(
      appBar: AppBar(title: const Text('Réglages de la boutique')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                        labelText: 'Téléphone de la boutique',
                        prefixIcon: Icon(Icons.call)),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _whatsapp,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                        labelText: 'Numéro WhatsApp', prefixIcon: Icon(Icons.chat)),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _address,
                    maxLines: 2,
                    decoration: const InputDecoration(
                        labelText: 'Adresse (pour le retrait)',
                        prefixIcon: Icon(Icons.place)),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _hours,
                    decoration: const InputDecoration(
                        labelText: 'Horaires',
                        hintText: 'Lun–Sam, 8h–19h',
                        prefixIcon: Icon(Icons.schedule)),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _fee,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                        labelText: 'Frais de livraison',
                        suffixText: 'FCFA',
                        prefixIcon: Icon(Icons.delivery_dining)),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    child: const Text('Enregistrer'),
                  ),
                ],
              ),
            ),
    );
  }
}
