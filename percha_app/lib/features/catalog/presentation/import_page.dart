import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/percha_widgets.dart';
import '../../onboarding/data/store_api.dart';
import '../application/sheet_parser.dart';
import '../data/catalog_api.dart';

/// Importar catálogo desde Excel. El archivo se lee EN EL DISPOSITIVO y a la API
/// solo viaja JSON validado. La API es todo-o-nada: si hay errores no se guarda nada.
class ImportPage extends ConsumerStatefulWidget {
  const ImportPage({super.key});

  @override
  ConsumerState<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends ConsumerState<ImportPage> {
  String? _fileName;
  SheetParseResult? _parsed;
  List<({int line, String message})> _serverErrors = const [];
  Map<String, dynamic>? _done;
  bool _busy = false;
  String? _error;

  Future<void> _pick() async {
    setState(() {
      _error = null;
      _serverErrors = const [];
      _done = null;
    });
    final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx'], withData: true);
    final file = picked?.files.single;
    if (file?.bytes == null) return;
    try {
      final book = Excel.decodeBytes(file!.bytes!);
      final sheet = book.tables[book.tables.keys.first]!;
      final rows = [for (final r in sheet.rows) [for (final c in r) c?.value?.toString()]];
      setState(() {
        _fileName = file.name;
        _parsed = parseSheet(rows);
      });
    } catch (_) {
      setState(() => _error = 'No se pudo leer el archivo. ¿Es un .xlsx válido?');
    }
  }

  Future<void> _send() async {
    final parsed = _parsed;
    if (parsed == null || parsed.errors.isNotEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
      _serverErrors = const [];
    });
    try {
      final branch = await ref.read(currentBranchProvider.future);
      final rows = [for (final r in parsed.rows) Map.of(r)..remove('_line')];
      final res = await ref.read(catalogApiProvider).import(branchId: branch.id, rows: rows);
      setState(() => _done = res);
    } on ApiError catch (e) {
      final raw = e.data['errors'];
      if (raw is List) {
        // La API indica la fila por índice (0 = primera fila de datos); se traduce a la línea de Excel.
        setState(() => _serverErrors = [
              for (final err in raw.cast<Map<String, dynamic>>())
                (
                  line: (err['row'] as int) < 0 ? 0 : parsed.rows[err['row'] as int]['_line'] as int,
                  message: err['message'] as String,
                ),
            ],);
      } else {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final parsed = _parsed;
    final errors = [...?parsed?.errors, ..._serverErrors];

    return Scaffold(
      appBar: AppBar(title: const Text('Importar catálogo')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Formato del Excel', style: text.titleMedium),
                  const SizedBox(height: PerchaSpace.sm),
                  const Text('Una fila por variante. Primera fila con los títulos:'),
                  const SizedBox(height: PerchaSpace.sm),
                  const Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      Pill('Nombre *'),
                      Pill('Precio *'),
                      Pill('Categoría'),
                      Pill('Costo'),
                      Pill('Stock'),
                      Pill('SKU'),
                      Pill('Código de barras'),
                    ],
                  ),
                  const SizedBox(height: PerchaSpace.sm),
                  Text('Cualquier otra columna (Talla, Color, Material…) se toma como atributo.', style: text.bodySmall),
                ],
              ),
            ),
          ),
          const SizedBox(height: PerchaSpace.lg),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.upload_file_outlined),
            label: Text(_fileName ?? 'Elegir archivo .xlsx'),
          ),
          if (_error != null) ...[const SizedBox(height: PerchaSpace.lg), ErrorBanner(_error!)],
          if (_done != null) ...[
            const SizedBox(height: PerchaSpace.lg),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: PerchaColors.accentSoft, borderRadius: BorderRadius.circular(PerchaRadius.card)),
              child: Text(
                'Listo: ${_done!['products']} productos, ${_done!['variants']} variantes y ${_done!['unitsLoaded']} unidades cargadas.',
                style: TextStyle(color: PerchaColors.accentInk, fontWeight: FontWeight.w600),
              ),
            ),
          ] else if (parsed != null) ...[
            const SizedBox(height: PerchaSpace.lg),
            Text(
              '${parsed.rows.length} filas · atributos: ${parsed.attributeColumns.isEmpty ? 'ninguno' : parsed.attributeColumns.join(', ')}',
              style: text.titleMedium,
            ),
            if (errors.isNotEmpty) ...[
              const SizedBox(height: PerchaSpace.md),
              ErrorBanner('Corrige ${errors.length} error${errors.length == 1 ? '' : 'es'} en el Excel y vuelve a elegirlo. No se guardó nada.'),
              const SizedBox(height: PerchaSpace.sm),
              for (final e in errors.take(50))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Text(e.line == 0 ? '—' : 'Fila ${e.line}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  title: Text(e.message),
                ),
            ] else ...[
              const SizedBox(height: PerchaSpace.lg),
              BusyButton(label: 'Importar ${parsed.rows.length} filas', busy: _busy, onPressed: _send),
            ],
          ],
        ],
      ),
    );
  }
}
