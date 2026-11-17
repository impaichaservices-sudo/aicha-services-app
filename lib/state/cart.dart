import 'package:flutter/foundation.dart';

import '../models/catalog_item.dart';

class CartLine {
  final String key;
  final CatalogItem item;
  int qty;
  final String fileUrl;
  final String fileName;
  final String note;

  CartLine({
    required this.key,
    required this.item,
    required this.qty,
    this.fileUrl = '',
    this.fileName = '',
    this.note = '',
  });

  int get subtotal => item.onQuote ? 0 : item.price * qty;
  bool get isPlain => fileUrl.isEmpty && note.isEmpty;
}

class Cart extends ChangeNotifier {
  final List<CartLine> _lines = [];
  int _seq = 0;

  List<CartLine> get lines => List.unmodifiable(_lines);
  bool get isEmpty => _lines.isEmpty;
  int get count => _lines.fold(0, (s, l) => s + l.qty);
  int get subtotal => _lines.fold(0, (s, l) => s + l.subtotal);
  bool get needsQuote => _lines.any((l) => l.item.onQuote);

  int _clamp(CatalogItem i, int q) =>
      i.places > 0 && q > i.places ? i.places : q;

  void add(CatalogItem item,
      {int qty = 1, String fileUrl = '', String fileName = '', String note = ''}) {
    final plain = fileUrl.isEmpty && note.isEmpty;
    if (plain) {
      for (final l in _lines) {
        if (l.item.id == item.id && l.isPlain) {
          l.qty = _clamp(item, l.qty + qty);
          notifyListeners();
          return;
        }
      }
    }
    _lines.add(CartLine(
      key: '${_seq++}',
      item: item,
      qty: _clamp(item, qty),
      fileUrl: fileUrl,
      fileName: fileName,
      note: note,
    ));
    notifyListeners();
  }

  void setQty(String key, int qty) {
    final i = _lines.indexWhere((l) => l.key == key);
    if (i < 0) return;
    if (qty <= 0) {
      _lines.removeAt(i);
    } else {
      _lines[i].qty = _clamp(_lines[i].item, qty);
    }
    notifyListeners();
  }

  void remove(String key) {
    _lines.removeWhere((l) => l.key == key);
    notifyListeners();
  }

  void clear() {
    _lines.clear();
    notifyListeners();
  }
}
