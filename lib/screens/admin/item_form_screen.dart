import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../config.dart';
import '../../models/catalog_item.dart';
import '../../services/db.dart';
import '../../services/storage_service.dart';
import '../../widgets/product_image.dart';

class ItemFormScreen extends StatefulWidget {
  final CatalogItem? item;
  const ItemFormScreen({super.key, this.item});

  @override
  State<ItemFormScreen> createState() => _ItemFormScreenState();
}

class _ItemFormScreenState extends State<ItemFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.item?.name ?? '');
  late final _desc = TextEditingController(text: widget.item?.description ?? '');
  late final _price =
      TextEditingController(text: widget.item?.price.toString() ?? '');
  late final _unit = TextEditingController(text: widget.item?.unit ?? "l'unité");
  late final _schedule =
      TextEditingController(text: widget.item?.schedule ?? '');
  late final _places =
      TextEditingController(text: widget.item?.places.toString() ?? '0');
  late String _type = widget.item?.type ?? 'impression';
  late bool _requiresFile = widget.item?.requiresFile ?? true;
  File? _image;
  bool _busy = false;

  bool get _editing => widget.item != null;

  @override
  void dispose() {
    for (final c in [_name, _desc, _price, _unit, _schedule, _places]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pick() async {
    final x = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      imageQuality: 80,
    );
    if (x != null) setState(() => _image = File(x.path));
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      var imageUrl = widget.item?.imageUrl ?? '';
      if (_image != null) {
        imageUrl = await StorageService.uploadCatalogImage(_image!);
      }
      final training = _type == 'formation';
      final data = <String, dynamic>{
        'type': _type,
        'name': _name.text.trim(),
        'description': _desc.text.trim(),
        'price': int.tryParse(_price.text) ?? 0,
        'unit': _unit.text.trim(),
        'imageUrl': imageUrl,
        'requiresFile': training ? false : _requiresFile,
        'schedule': training ? _schedule.text.trim() : '',
        'places': training ? (int.tryParse(_places.text) ?? 0) : 0,
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
      messenger.showSnackBar(const SnackBar(content: Text('Enregistré')));
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
        title: Text(_editing ? 'Modifier' : 'Nouveau service'),
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
                borderRadius: BorderRadius.circular(12),
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
            DropdownButtonFormField<String>(
              value: _type,
              decoration: const InputDecoration(labelText: 'Type'),
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
                labelText: 'Nom',
                hintText: training
                    ? 'Ex : Formation Excel débutant'
                    : 'Ex : Cartes de visite (100)',
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
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    if (n == null || n < 0) return 'Prix invalide';
                    if (n % 5 != 0) return 'Multiple de 5';
                    return null;
                  },
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
            const SizedBox(height: 12),
            if (training) ...[
              TextFormField(
                controller: _schedule,
                decoration: const InputDecoration(
                  labelText: 'Dates et horaires',
                  hintText: 'Ex : du 2 au 6 déc., 9h–12h',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _places,
                keyboardType: TextInputType.number,
                inputFormatters: digits,
                decoration: const InputDecoration(
                    labelText: 'Places disponibles (0 = illimité)'),
              ),
            ] else
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Le client doit joindre un fichier'),
                subtitle: const Text('Document, logo, photo à imprimer…'),
                value: _requiresFile,
                onChanged: (v) => setState(() => _requiresFile = v),
              ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed: _busy ? null : _save,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Enregistrer'),
            ),
          ),
        ),
      ),
    );
  }
}
