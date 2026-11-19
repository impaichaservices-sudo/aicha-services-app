import 'package:flutter/material.dart';
import '../../utils.dart';
import '../../widgets/backup_admins.dart';
import 'package:flutter/services.dart';

import '../../models/shop.dart';
import '../../models/shop_settings.dart';
import '../../services/db.dart';
import '../../services/notify_service.dart';

/// Super Admin : paramètres généraux + fichiers (Cloudinary) + notifications.
/// Responsable : réglages de sa boutique.
class AdminSettingsScreen extends StatefulWidget {
  final String? shopId;
  const AdminSettingsScreen({super.key, this.shopId});

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
  final _cloud = TextEditingController();
  final _preset = TextEditingController();
  final _notify = TextEditingController();
  bool _loaded = false;
  bool _busy = false;

  bool get _global => widget.shopId == null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (_global) {
        final s = ShopSettings.fromDoc(await Db.settingsDoc.get());
        _phone.text = s.phone;
        _whatsapp.text = s.whatsapp;
        _address.text = s.address;
        _hours.text = s.hours;
        _fee.text = s.deliveryFee.toString();
        _cloud.text = s.cloudinaryCloud;
        _preset.text = s.cloudinaryPreset;
        _notify.text = s.notifyUrl;
      } else {
        final s = Shop.fromDoc(await Db.shops.doc(widget.shopId).get());
        _phone.text = s.phone;
        _whatsapp.text = s.whatsapp;
        _address.text = s.address;
        _hours.text = s.hours;
        _fee.text = s.deliveryFee.toString();
      }
    } catch (_) {}
    if (mounted) setState(() => _loaded = true);
  }

  @override
  void dispose() {
    for (final c in [_phone, _whatsapp, _address, _hours, _fee, _cloud, _preset, _notify]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      if (_global) {
        await Db.saveSettings(ShopSettings(
          phone: _phone.text.trim(),
          whatsapp: _whatsapp.text.trim(),
          address: _address.text.trim(),
          hours: _hours.text.trim(),
          deliveryFee: int.tryParse(_fee.text) ?? 0,
          cloudinaryCloud: _cloud.text.trim(),
          cloudinaryPreset: _preset.text.trim(),
          notifyUrl: _notify.text.trim(),
        ));
        NotifyService.resetCache();
      } else {
        await Db.shops.doc(widget.shopId).update({
          'phone': _phone.text.trim(),
          'whatsapp': _whatsapp.text.trim(),
          'address': _address.text.trim(),
          'hours': _hours.text.trim(),
          'deliveryFee': int.tryParse(_fee.text) ?? 0,
        });
      }
      messenger.showSnackBar(const SnackBar(content: Text('Réglages enregistrés')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _title(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
        child: Text(t,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(_global ? 'Paramètres' : 'Réglages de la boutique')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _title(_global
                      ? 'Coordonnées par défaut (avant la création des boutiques)'
                      : 'Coordonnées de la boutique'),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                        labelText: 'Téléphone', prefixIcon: Icon(Icons.call)),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _whatsapp,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                        labelText: 'WhatsApp', prefixIcon: Icon(Icons.chat)),
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
                  if (_global) ...[
                    _title('Super Admins de secours'),
                    const BackupAdmins(),
                    _title('Notifications (serveur Cloudflare)'),
                    TextFormField(
                      controller: _notify,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                          labelText: 'Adresse du serveur',
                          hintText: 'https://aicha-notify.xxx.workers.dev'),
                      validator: (v) {
                        final t = (v ?? '').trim();
                        if (t.isEmpty || t.startsWith('https://')) return null;
                        return 'Doit commencer par https://';
                      },
                    ),
                  ],
                  const SizedBox(height: 24),
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
