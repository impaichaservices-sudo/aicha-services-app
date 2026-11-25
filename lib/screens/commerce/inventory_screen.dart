import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config.dart';
import '../../models/commerce.dart';
import '../../services/commerce_service.dart';
import '../../services/session.dart';
import '../../utils.dart';
import 'commerce_widgets.dart';

/// Inventaire : saisir le stock compté, l'écart est corrigé automatiquement.
class InventoryScreen extends StatefulWidget {
  final String shopId;
  const InventoryScreen({super.key, required this.shopId});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  late final Stream<List<Product>> _products = Commerce.productsOf(widget.shopId);
  final _counted = <String, int>{};
  final _ctrl = <String, TextEditingController>{};
  String _q = '';
  List<Product> _last = const [];

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final s = sessionOf(context, listen: false);
    final map = <Product, int>{};
    for (final p in _last) {
      final v = _counted[p.id];
      if (v != null && v != p.stock) map[p] = v;
    }
    if (map.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aucun écart : rien à corriger.')));
      return;
    }
    final lines = map.entries
        .map((e) => '${e.key.name} : ${e.key.stock} → ${e.value} (${e.value - e.key.stock > 0 ? '+' : ''}${e.value - e.key.stock})')
        .join('\n');
    if (!await confirm(context, 'Enregistrer ${map.length} correction(s) ?', lines)) return;
    final n = await Commerce.inventory(s, widget.shopId, map);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$n correction(s) enregistrée(s).')));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inventaire')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _save,
        icon: const Icon(Icons.save_rounded),
        label: Text('Enregistrer (${_counted.length})'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Rechercher'),
            onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('Saisissez la quantité réellement comptée. Laissez vide les produits non comptés.',
              style: TextStyle(color: Colors.black54, fontSize: 13)),
        ),
        Expanded(
          child: StreamBuilder<List<Product>>(
            stream: _products,
            builder: (context, snap) {
              if (snap.hasError) return Center(child: Text(friendlyError(snap.error)));
              final all = (snap.data ?? const <Product>[])
                  .where((p) => p.trackStock && p.active)
                  .toList();
              _last = all;
              final list = _q.isEmpty
                  ? all
                  : all.where((p) => p.name.toLowerCase().contains(_q) || p.ref.toLowerCase().contains(_q)).toList();
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 90),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final p = list[i];
                  final c = _ctrl.putIfAbsent(p.id, () => TextEditingController());
                  final v = _counted[p.id];
                  final gap = v == null ? null : v - p.stock;
                  return ListTile(
                    title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('Théorique : ${p.stock} ${p.unit}'
                        '${gap == null ? '' : ' · écart ${gap > 0 ? '+' : ''}$gap'}',
                        style: TextStyle(
                            color: gap == null || gap == 0
                                ? Colors.black54
                                : (gap > 0 ? AppConfig.green : Colors.red),
                            fontWeight: gap == null ? null : FontWeight.w700)),
                    trailing: SizedBox(
                      width: 90,
                      child: TextField(
                        controller: c,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(hintText: 'Réel'),
                        onChanged: (t) => setState(() {
                          final n = int.tryParse(t.trim());
                          if (n == null) {
                            _counted.remove(p.id);
                          } else {
                            _counted[p.id] = n;
                          }
                        }),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}
