import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Affiche une image de service : soit une URL web, soit une image
/// enregistrée directement dans la base ("data:image/jpeg;base64,...").
class ProductImage extends StatelessWidget {
  final String url;
  final double? size;
  const ProductImage(this.url, {super.key, this.size});

  static final Map<String, Uint8List> _cache = {};

  static Uint8List? _decode(String dataUri) {
    final cached = _cache[dataUri];
    if (cached != null) return cached;
    try {
      final bytes = base64Decode(dataUri.substring(dataUri.indexOf(',') + 1));
      if (_cache.length > 100) _cache.clear();
      return _cache[dataUri] = bytes;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.image_outlined, size: 40),
    );
    if (url.isEmpty) return placeholder;

    if (url.startsWith('data:image')) {
      final bytes = _decode(url);
      if (bytes == null) return placeholder;
      return Image.memory(
        bytes,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => placeholder,
      );
    }

    return Image.network(
      url,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => placeholder,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : placeholder,
    );
  }
}
