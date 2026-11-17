import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../models/catalog_item.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
import '../state/cart.dart';
import '../widgets/product_image.dart';

class ItemDetailScreen extends StatefulWidget {
  final CatalogItem item;
  const ItemDetailScreen({super.key, required this.item});

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  final _note = TextEditingController();
  int _qty = 1;
  File? _file;
  String _fileName = '';
  bool _busy = false;

  CatalogItem get item => widget.item;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.any);
    final f = res?.files.single;
    if (f == null || f.path == null) return;
    if (f.size > 25 * 1024 * 1024) {
      _snack('Fichier trop lourd (25 Mo maximum).');
      return;
    }
    setState(() {
      _file = File(f.path!);
      _fileName = f.name;
    });
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _add() async {
    if (item.requiresFile && _file == null) {
      _snack('Merci de joindre votre fichier à imprimer.');
      return;
    }
    final cart = context.read<Cart>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      var url = '';
      if (_file != null) {
        url = await StorageService.uploadClientFile(
            AuthService.current!.uid, _file!, _fileName);
      }
      cart.add(item,
          qty: _qty, fileUrl: url, fileName: _fileName, note: _note.text.trim());
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Ajouté au panier')));
    } catch (e) {
      _snack('Envoi du fichier impossible : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final maxQty = item.places > 0 ? item.places : 100000;

    return Scaffold(
      appBar: AppBar(title: Text(item.name)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          AspectRatio(aspectRatio: 16 / 10, child: ProductImage(item.imageUrl)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(itemTypes[item.type] ?? item.type,
                    style: t.labelLarge?.copyWith(color: scheme.primary)),
                Text(item.name, style: t.headlineSmall),
                const SizedBox(height: 8),
                Text(item.priceLabel,
                    style: t.titleLarge?.copyWith(
                        color: scheme.primary, fontWeight: FontWeight.bold)),
                if (item.onQuote)
                  const Text('Nous vous enverrons le prix exact après avoir '
                      'vu votre demande.'),
                if (item.isTraining) ...[
                  const SizedBox(height: 12),
                  if (item.schedule.isNotEmpty)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event),
                      title: Text(item.schedule),
                    ),
                  if (item.places > 0)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.groups),
                      title: Text('${item.places} places disponibles'),
                    ),
                ],
                const Divider(height: 32),
                Text(item.description.isEmpty ? '' : item.description),
                const SizedBox(height: 16),

                // Quantité / participants
                Row(children: [
                  Expanded(
                    child: Text(item.isTraining ? 'Participants' : 'Quantité',
                        style: t.titleMedium),
                  ),
                  IconButton.outlined(
                    onPressed: _qty > 1 ? () => setState(() => _qty--) : null,
                    icon: const Icon(Icons.remove),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('$_qty', style: t.titleLarge),
                  ),
                  IconButton.outlined(
                    onPressed:
                        _qty < maxQty ? () => setState(() => _qty++) : null,
                    icon: const Icon(Icons.add),
                  ),
                ]),
                const SizedBox(height: 16),

                // Fichier à imprimer
                if (item.acceptsFile) ...[
                  Text(
                      item.requiresFile
                          ? 'Votre fichier (obligatoire)'
                          : 'Votre fichier (facultatif)',
                      style: t.titleMedium),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _pickFile,
                    icon: Icon(_file == null ? Icons.attach_file : Icons.check),
                    label: Text(
                      _file == null ? 'Joindre un fichier (PDF, image, Word…)' : _fileName,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                TextField(
                  controller: _note,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: item.isTraining
                        ? 'Noms des participants / remarques'
                        : 'Précisions (format, papier, couleur, recto-verso…)',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _busy ? null : _add,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.add_shopping_cart),
            label: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_busy
                  ? 'Envoi du fichier…'
                  : item.isTraining
                      ? 'Réserver ma place'
                      : 'Ajouter au panier'),
            ),
          ),
        ),
      ),
    );
  }
}
