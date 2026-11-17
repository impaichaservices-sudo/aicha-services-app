import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../config.dart';
import '../../models/catalog_item.dart';
import '../../models/promotion.dart';
import '../../services/db.dart';
import '../../utils.dart';
import '../../widgets/common.dart';
import '../../widgets/product_image.dart';

/// Gestion → Offres et nouveautés (affichées dans « Nos offres »).
class AdminPromotionsScreen extends StatefulWidget {
  const AdminPromotionsScreen({super.key});

  @override
  State<AdminPromotionsScreen> createState() => _AdminPromotionsScreenState();
}

class _AdminPromotionsScreenState extends State<AdminPromotionsScreen> {
  late final Stream<List<Promotion>> _promos = Db.allPromotions();

  void _open([Promotion? p]) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => PromotionFormScreen(promo: p)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Offres et nouveautés')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(),
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle offre'),
      ),
      body: StreamBuilder<List<Promotion>>(
        stream: _promos,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Erreur : ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final list = snap.data!;
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.local_offer_outlined,
              title: 'Aucune offre publiée',
              message:
                  'Créez une promotion, une nouveauté ou une annonce : elle apparaîtra dans « Nos offres » sur l\'accueil.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final p = list[i];
              return Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(10),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: ProductImage(p.imageUrl, size: 56),
                  ),
                  title: Text(p.title,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(promoKinds[p.kind] ?? p.kind),
                      Text(
                        '${p.start == null ? 'Dès maintenant' : 'Du ${shortDate(p.start).split(' ').first}'}'
                        '${p.end == null ? '' : ' au ${shortDate(p.end).split(' ').first}'}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      p.isLive
                          ? const Pill('En ligne', color: AppConfig.green)
                          : const Pill('Hors ligne', color: Colors.grey),
                    ],
                  ),
                  trailing: Switch(
                    value: p.active,
                    onChanged: (v) => Db.promotions.doc(p.id).update({'active': v}),
                  ),
                  onTap: () => _open(p),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class PromotionFormScreen extends StatefulWidget {
  final Promotion? promo;
  const PromotionFormScreen({super.key, this.promo});

  @override
  State<PromotionFormScreen> createState() => _PromotionFormScreenState();
}

class _PromotionFormScreenState extends State<PromotionFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.promo?.title ?? '');
  late final _desc = TextEditingController(text: widget.promo?.description ?? '');
  late String _kind = promoKinds.containsKey(widget.promo?.kind)
      ? widget.promo!.kind
      : 'promotion';
  late String _itemId = widget.promo?.itemId ?? '';
  late DateTime? _start = widget.promo?.start;
  late DateTime? _end = widget.promo?.end;
  File? _image;
  String? _imageData;
  bool _busy = false;
  List<CatalogItem> _items = const [];

  @override
  void initState() {
    super.initState();
    Db.catalogItems().first.then((l) {
      if (mounted) setState(() => _items = l);
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final x = await ImagePicker().pickImage(
        source: ImageSource.gallery, maxWidth: 1000, maxHeight: 700, imageQuality: 60);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    if (bytes.length > 600 * 1024) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image trop lourde, choisissez-en une autre.')));
      return;
    }
    setState(() {
      _image = File(x.path);
      _imageData = 'data:image/jpeg;base64,${base64Encode(bytes)}';
    });
  }

  Future<DateTime?> _date(DateTime? initial) => showDatePicker(
        context: context,
        initialDate: initial ?? DateTime.now(),
        firstDate: DateTime(2024),
        lastDate: DateTime(2035),
      );

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final data = <String, dynamic>{
        'kind': _kind,
        'title': _title.text.trim(),
        'description': _desc.text.trim(),
        'imageUrl': _imageData ?? widget.promo?.imageUrl ?? '',
        'itemId': _itemId,
        'start': _start == null ? null : Timestamp.fromDate(_start!),
        'end': _end == null ? null : Timestamp.fromDate(_end!),
        'shops': ['all'],
      };
      if (widget.promo == null) {
        await Db.promotions.add({
          ...data,
          'active': true,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        await Db.promotions.doc(widget.promo!.id).update(data);
      }
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Offre enregistrée')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    await Db.promotions.doc(widget.promo!.id).delete();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.promo == null ? 'Nouvelle offre' : 'Modifier l\'offre'),
        actions: [
          if (widget.promo != null)
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
                  aspectRatio: 16 / 9,
                  child: _image != null
                      ? Image.file(_image!, fit: BoxFit.cover)
                      : Stack(fit: StackFit.expand, children: [
                          ProductImage(widget.promo?.imageUrl ?? ''),
                          const Align(
                            alignment: Alignment.bottomCenter,
                            child: Padding(
                              padding: EdgeInsets.all(8),
                              child: Chip(
                                  avatar: Icon(Icons.photo_camera),
                                  label: Text('Choisir une image')),
                            ),
                          ),
                        ]),
                ),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _kind,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [
                for (final e in promoKinds.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _kind = v!),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(
                  labelText: 'Titre', hintText: 'Ex : -20 % sur les cartes de visite'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Champ obligatoire' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _desc,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _items.any((i) => i.id == _itemId) ? _itemId : '',
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Service lié (facultatif)',
                  helperText: 'Le client arrive sur ce service en touchant l\'offre'),
              items: [
                const DropdownMenuItem(value: '', child: Text('Aucun')),
                for (final i in _items)
                  DropdownMenuItem(
                      value: i.id,
                      child: Text(i.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _itemId = v ?? ''),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final d = await _date(_start);
                    if (d != null) setState(() => _start = d);
                  },
                  icon: const Icon(Icons.event),
                  label: Text(_start == null
                      ? 'Début : maintenant'
                      : 'Début : ${shortDate(_start).split(' ').first}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final d = await _date(_end);
                    if (d != null) setState(() => _end = d);
                  },
                  icon: const Icon(Icons.event_busy),
                  label: Text(_end == null
                      ? 'Fin : aucune'
                      : 'Fin : ${shortDate(_end).split(' ').first}'),
                ),
              ),
            ]),
            if (_start != null || _end != null)
              TextButton(
                onPressed: () => setState(() {
                  _start = null;
                  _end = null;
                }),
                child: const Text('Effacer les dates'),
              ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _busy ? null : _save,
            child: const Text('Publier'),
          ),
        ),
      ),
    );
  }
}
