import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/percha_widgets.dart';
import '../data/catalog_api.dart';

/// Galería del producto: fotos deslizables, miniaturas y, para quien edita el catálogo,
/// agregar (cámara o galería), poner de portada, asociar a un color y borrar.
class ProductGallery extends ConsumerStatefulWidget {
  const ProductGallery({super.key, required this.product, required this.canEdit});
  final Product product;
  final bool canEdit;

  @override
  ConsumerState<ProductGallery> createState() => _ProductGalleryState();
}

class _ProductGalleryState extends ConsumerState<ProductGallery> {
  final _page = PageController();
  int _index = 0;
  bool _uploading = false;

  List<ProductImage> get _images => widget.product.images;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void _refresh() => ref.invalidate(productDetailProvider(widget.product.id));

  Future<void> _add(ImageSource source) async {
    // El teléfono reduce la foto antes de subirla (menos datos móviles); el servidor la vuelve
    // a procesar y le quita los metadatos.
    final file = await ImagePicker().pickImage(source: source, maxWidth: 2000, maxHeight: 2000, imageQuality: 85);
    if (file == null) return;
    final option = await _pickOption();
    setState(() => _uploading = true);
    try {
      final bytes = await file.readAsBytes();
      final type = file.mimeType ?? (file.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg');
      await ref.read(catalogApiProvider).uploadImage(widget.product.id, bytes, contentType: type, option: option);
      _refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(e))));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// Si el producto tiene colores (u otro atributo visual), se puede asociar la foto.
  Future<String?> _pickOption() async {
    final attr = widget.product.attributes.where((a) => a.name.toLowerCase() == 'color').firstOrNull;
    if (attr == null || attr.values.length < 2 || !mounted) return null;
    return showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('¿De qué color es la foto?'),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx), child: const Text('General (todos los colores)')),
          for (final v in attr.values) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, v), child: Text(v)),
        ],
      ),
    );
  }

  Future<void> _menu(ProductImage img, int i) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (i > 0) ListTile(leading: const Icon(Icons.star_outline), title: const Text('Usar como portada'), onTap: () => Navigator.pop(ctx, 'cover')),
          ListTile(leading: Icon(Icons.delete_outline, color: PerchaColors.warn), title: Text('Borrar foto', style: TextStyle(color: PerchaColors.warn)), onTap: () => Navigator.pop(ctx, 'delete')),
        ]),
      ),
    );
    if (action == null) return;
    final api = ref.read(catalogApiProvider);
    try {
      if (action == 'cover') {
        await api.reorderImages(widget.product.id, [img.id, ..._images.where((x) => x.id != img.id).map((x) => x.id)]);
      } else {
        await api.deleteImage(widget.product.id, img.id);
      }
      _refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(e))));
    }
  }

  Future<void> _chooseSource() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Tomar foto'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Elegir de la galería'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
        ]),
      ),
    );
    if (source != null) await _add(source);
  }

  @override
  Widget build(BuildContext context) {
    final c = PerchaColors.palette;
    final canAdd = widget.canEdit && _images.length < 8;
    if (_images.isEmpty) {
      return AspectRatio(
        aspectRatio: 4 / 3,
        child: Material(
          color: c.surfaceAlt,
          borderRadius: BorderRadius.circular(PerchaRadius.card),
          child: InkWell(
            borderRadius: BorderRadius.circular(PerchaRadius.card),
            onTap: canAdd && !_uploading ? _chooseSource : null,
            child: Center(
              child: _uploading
                  ? const CircularProgressIndicator()
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.add_a_photo_outlined, size: 36, color: c.muted),
                      const SizedBox(height: 8),
                      Text(widget.canEdit ? 'Agrega fotos: ayudan a encontrar la prenda' : 'Sin fotos', style: TextStyle(color: c.muted)),
                    ]),
            ),
          ),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(PerchaRadius.card),
        child: AspectRatio(
          aspectRatio: 4 / 5,
          child: Stack(fit: StackFit.expand, children: [
            PageView.builder(
              controller: _page,
              itemCount: _images.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) => GestureDetector(
                onLongPress: widget.canEdit ? () => _menu(_images[i], i) : null,
                child: Semantics(
                  image: true,
                  label: 'Foto ${i + 1} de ${_images.length}${_images[i].optionValue != null ? ', color ${_images[i].optionValue}' : ''}',
                  child: Image.network(
                    _images[i].url,
                    fit: BoxFit.cover,
                    loadingBuilder: (_, child, progress) => progress == null ? child : Container(color: c.surfaceAlt),
                    errorBuilder: (_, __, ___) => Container(color: c.surfaceAlt, child: Icon(Icons.broken_image_outlined, color: c.muted)),
                  ),
                ),
              ),
            ),
            if (_images[_index].optionValue != null)
              Positioned(left: 12, top: 12, child: Pill(_images[_index].optionValue!)),
            if (_images.length > 1)
              Positioned(
                bottom: 10,
                left: 0,
                right: 0,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (var i = 0; i < _images.length; i++)
                    AnimatedContainer(
                      duration: PerchaMotion.fast,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _index ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(color: i == _index ? Colors.white : Colors.white70, borderRadius: BorderRadius.circular(3)),
                    ),
                ]),
              ),
          ]),
        ),
      ),
      if (widget.canEdit) ...[
        const SizedBox(height: PerchaSpace.sm),
        SizedBox(
          height: 74,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (var i = 0; i < _images.length; i++)
              Padding(
                // Espacio arriba y a la derecha para el botón de opciones (sobresale de la miniatura).
                padding: const EdgeInsets.only(right: 12, top: 8),
                // Además de la pulsación larga, un botón visible: así se descubre que la foto tiene
                // opciones (portada, borrar).
                child: Stack(clipBehavior: Clip.none, children: [
                  GestureDetector(
                  onTap: () => _page.animateToPage(i, duration: PerchaMotion.normal, curve: PerchaMotion.curve),
                  onLongPress: () => _menu(_images[i], i),
                  child: Container(
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: i == _index ? c.accent : c.border, width: 2)),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        _images[i].thumbUrl,
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                        semanticLabel: 'Foto ${i + 1}',
                        errorBuilder: (_, __, ___) => SizedBox(width: 60, height: 60, child: Icon(Icons.broken_image_outlined, color: c.muted)),
                      ),
                    ),
                  ),
                ),
                  Positioned(
                    right: -6,
                    top: -6,
                    child: Material(
                      color: c.surface,
                      shape: CircleBorder(side: BorderSide(color: c.border)),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => _menu(_images[i], i),
                        child: Tooltip(
                          message: 'Opciones de la foto ${i + 1}',
                          child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.more_horiz, size: 16, color: c.inkSoft)),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            if (canAdd)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: _uploading ? null : _chooseSource,
                child: Container(
                  width: 64,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: c.borderStrong)),
                  child: _uploading ? const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(strokeWidth: 2)) : Icon(Icons.add_a_photo_outlined, color: c.muted),
                ),
                ),
              ),
          ]),
        ),
        Text('Toca ··· en una foto (o mantenla presionada) para ponerla de portada o borrarla.', style: Theme.of(context).textTheme.bodySmall),
      ],
    ]);
  }
}
