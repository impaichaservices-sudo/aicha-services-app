import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../config.dart';
import '../../models/catalog_item.dart';
import '../../services/db.dart';
import '../../services/session.dart';
import '../../widgets/product_image.dart';

/// Ajout / modification d'un service du catalogue.
class ItemFormScreen extends StatefulWidget {
  final CatalogItem? item;
  final String? shopId; // boutique de l'équipe (null = Super Admin)
  const ItemFormScreen({super.key, this.item, this.shopId});

  @override
  State<ItemFormScreen> createState() => _ItemFormScreenState();
}

class _ItemFormScreenState extends State<ItemFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.item?.name ?? '');
  late final _desc = TextEditingController(text: widget.item?.description ?? '');
  late final _extra = TextEditingController(text: widget.item?.extraInfo ?? '');
  late final _price =
      TextEditingController(text: widget.item?.price.toString() ?? '');
  late final _unit = TextEditingController(text: widget.item?.unit ?? "l'unité");
  late final _schedule = TextEditingController(text: widget.item?.schedule ?? '');
  late final _places =
      TextEditingController(text: widget.item?.places.toString() ?? '0');
  late final _booked =
      TextEditingController(text: widget.item?.booked.toString() ?? '0');
  late String _type = itemTypes.containsKey(widget.item?.type)
      ? widget.item!.type
      : 'impression';
  late bool _requiresFile = widget.item?.requiresFile ?? false;
  late bool _fromPrice = widget.item?.fromPrice ?? false;
  late bool _available = widget.item?.available ?? true;
  late bool _popular = widget.item?.popular ?? false;
  late String _shop = widget.shopId ??
      (widget.item == null || widget.item!.shopId == 'main'
          ? 'all'
          : widget.item!.shopId);
  File? _image;
  String? _imageData; // photo compressée, enregistrée dans la base
  bool _busy = false;

  bool get _editing => widget.item != null;

  @override
  void dispose() {
    for (final c in [_name, _desc, _extra, _price, _unit, _schedule, _places, _booked]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pick() async {
    final x = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 60,
    );
    if (x == null) return;
    final bytes = await x.readAsBytes();
    if (bytes.length > 600 * 1024) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Photo trop lourde, choisissez-en une autre.')));
      return;
    }
    setState(() {
      _image = File(x.path);
      _imageData = 'data:image/jpeg;base64,${base64Encode(bytes)}';
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final training = _type == 'formation';
      final data = <String, dynamic>{
        'shopId': widget.shopId ?? _shop,
        'type': _type,
        'name': _name.text.trim(),
        'description': _desc.text.trim(),
        'extraInfo': _extra.text.trim(),
        'price': int.tryParse(_price.text) ?? 0,
        'unit': _unit.text.trim(),
        'fromPrice': _fromPrice,
        'imageUrl': _imageData ?? widget.item?.imageUrl ?? '',
        'available': _available,
        'popular': _popular,
        'requiresFile': training ? false : _requiresFile,
        'schedule': training ? _schedule.text.trim() : '',
        'places': training ? (int.tryParse(_places.text) ?? 0) : 0,
        'booked': training ? (int.tryParse(_booked.text) ?? 0) : 0,
      };
      if (_editing) {
        await Db.catalog.doc(widget.item!.id).update(data);
      } else {
        await Db.catalog.add({
          ...data,
          'active': true,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Service enregistré')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ce service ?'),
        content: const Text('Astuce : vous pouvez aussi simplement le masquer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Non')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    await Db.catalog.doc(widget.item!.id).delete();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final digits = [FilteringTextInputFormatter.digitsOnly];
    final training = _type == 'formation';
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Modifier le service' : 'Nouveau service'),
        actions: [
          if (_editing)
            IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            GestureDetector(
              onTap: _pick,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 16 / 10,
                  child: _image != null
                      ? Image.file(_image!, fit: BoxFit.cover)
                      : Stack(fit: StackFit.expand, children: [
                          ProductImage(widget.item?.imageUrl ?? ''),
                          const Align(
                            alignment: Alignment.bottomCenter,
                            child: Padding(
                              padding: EdgeInsets.all(8),
                              child: Chip(
                                avatar: Icon(Icons.photo_camera),
                                label: Text('Choisir une photo'),
                              ),
                            ),
                          ),
                        ]),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (widget.shopId == null && sessionOf(context).shops.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                value: _shop == 'all' ||
                        sessionOf(context).shops.any((x) => x.id == _shop)
                    ? _shop
                    : 'all',
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Boutique'),
                items: [
                  const DropdownMenuItem(
                      value: 'all', child: Text('Toutes les boutiques')),
                  for (final sh in sessionOf(context).shops)
                    DropdownMenuItem(value: sh.id, child: Text(sh.name)),
                ],
                onChanged: (v) => setState(() => _shop = v ?? 'all'),
              ),
              const SizedBox(height: 12),
            ],
            DropdownButtonFormField<String>(
              value: _type,
              decoration: const InputDecoration(labelText: 'Catégorie'),
              items: [
                for (final e in itemTypes.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() {
                _type = v!;
                if (_type == 'formation' && _unit.text == "l'unité") {
                  _unit.text = 'par personne';
                }
              }),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              decoration: InputDecoration(
                labelText: 'Nom du service',
                hintText: training
                    ? 'Ex : Formation Excel débutant'
                    : 'Ex : T-shirt personnalisé',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Champ obligatoire' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _desc,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _price,
                  keyboardType: TextInputType.number,
                  inputFormatters: digits,
                  decoration: const InputDecoration(
                      labelText: 'Prix (0 = sur devis)', suffixText: 'FCFA'),
                  validator: (v) =>
                      int.tryParse(v ?? '') == null ? 'Prix invalide' : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _unit,
                  decoration: const InputDecoration(labelText: 'Unité'),
                ),
              ),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Afficher « À partir de »'),
              value: _fromPrice,
              onChanged: (v) => setState(() => _fromPrice = v),
            ),
            TextFormField(
              controller: _extra,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Informations supplémentaires',
                hintText: 'Délai, tailles disponibles, matières…',
              ),
            ),
            const SizedBox(height: 8),
            if (training) ...[
              const SizedBox(height: 4),
              TextFormField(
                controller: _schedule,
                decoration: const InputDecoration(
                  labelText: 'Date(s) et horaires',
                  hintText: 'Ex : du 2 au 6 décembre, 9h–12h',
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _places,
                    keyboardType: TextInputType.number,
                    inputFormatters: digits,
                    decoration: const InputDecoration(
                        labelText: 'Nombre de places', helperText: '0 = illimité'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _booked,
                    keyboardType: TextInputType.number,
                    inputFormatters: digits,
                    decoration: const InputDecoration(
                        labelText: 'Places réservées',
                        helperText: 'Mis à jour par les commandes'),
                  ),
                ),
              ]),
            ] else
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Le client doit envoyer un fichier'),
                subtitle: const Text('Logo, photo, document…'),
                value: _requiresFile,
                onChanged: (v) => setState(() => _requiresFile = v),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Disponible'),
              subtitle: const Text('Désactivez si le service est momentanément indisponible'),
              value: _available,
              onChanged: (v) => setState(() => _available = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Service populaire'),
              subtitle: const Text('Mis en avant sur l\'accueil'),
              value: _popular,
              onChanged: (v) => setState(() => _popular = v),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white))
                : const Text('Enregistrer'),
          ),
        ),
      ),
    );
  }
}
