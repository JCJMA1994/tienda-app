import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Miniatura cuadrada de producto; sin foto muestra un ícono (nunca un espacio vacío).
class ProductThumb extends StatelessWidget {
  const ProductThumb({super.key, required this.url, this.size = 52});
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = PerchaColors.palette;
    final placeholder = Container(
      width: size,
      height: size,
      color: c.surfaceAlt,
      child: Icon(Icons.checkroom_outlined, color: c.muted, size: size * 0.45),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: url == null
          ? placeholder
          : Image.network(
              url!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              // Decodifica al tamaño mostrado (no a 400 px): menos memoria en listas largas.
              cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
              errorBuilder: (_, __, ___) => placeholder,
            ),
    );
  }
}
