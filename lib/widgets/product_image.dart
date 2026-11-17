import 'package:flutter/material.dart';

class ProductImage extends StatelessWidget {
  final String url;
  final double? size;
  const ProductImage(this.url, {super.key, this.size});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.image_outlined, size: 40),
    );
    if (url.isEmpty) return placeholder;
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
