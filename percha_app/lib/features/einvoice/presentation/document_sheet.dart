import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/forms/formatters.dart';
import '../../../core/money.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/percha_widgets.dart';
import '../../lookup/lookup_api.dart';
import '../domain/customer_rules.dart';
import '../domain/document_choice.dart';

export '../domain/document_choice.dart';


/// Elegir boleta o factura y los datos del cliente. Valida con las reglas de SUNAT antes de
/// cobrar (la API vuelve a validar).
Future<DocumentChoice?> pickDocument(BuildContext context, {required DocumentChoice current, required int totalCents, required int anonLimitCents, String? error}) {
  return showModalBottomSheet<DocumentChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _DocumentSheet(current: current, totalCents: totalCents, anonLimitCents: anonLimitCents, initialError: error),
  );
}

class _DocumentSheet extends ConsumerStatefulWidget {
  const _DocumentSheet({required this.current, required this.totalCents, required this.anonLimitCents, this.initialError});
  final DocumentChoice current;
  final int totalCents;
  final int anonLimitCents;
  final String? initialError;

  @override
  ConsumerState<_DocumentSheet> createState() => _DocumentSheetState();
}

class _DocumentSheetState extends ConsumerState<_DocumentSheet> {
  late bool _factura = widget.current.factura;
  late DocType _type = widget.current.factura ? DocType.ruc : widget.current.type;
  late final _number = TextEditingController(text: widget.current.number);
  late final _name = TextEditingController(text: widget.current.name);
  late final _address = TextEditingController(text: widget.current.address);
  late String? _error = widget.initialError;
  List<String> _warnings = const [];
  bool _searching = false;

  /// Autocompleta nombre (y dirección para RUC). Si falla, se escribe a mano.
  Future<void> _lookup() async {
    final n = _number.text.trim();
    final isRuc = _factura || _type == DocType.ruc;
    setState(() {
      _searching = true;
      _error = null;
      _warnings = const [];
    });
    try {
      final api = ref.read(lookupApiProvider);
      final r = isRuc ? await api.ruc(n) : await api.dni(n);
      setState(() {
        _name.text = r.name;
        if (r.address != null && _address.text.isEmpty) _address.text = r.address!;
        _warnings = r.warnings;
      });
    } catch (e) {
      setState(() => _error = '${errorText(e)}. Puedes escribir el nombre a mano.');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  void dispose() {
    _number.dispose();
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  void _done() {
    final type = _factura ? DocType.ruc : _type;
    final error = validateCustomer(
      factura: _factura,
      totalCents: widget.totalCents,
      anonLimitCents: widget.anonLimitCents,
      type: type,
      number: _number.text,
      name: _name.text,
    );
    if (error != null) return setState(() => _error = error);
    Navigator.pop(
      context,
      DocumentChoice(factura: _factura, type: type, number: _number.text.trim(), name: _name.text.trim(), address: _address.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final needsId = !_factura && widget.totalCents > widget.anonLimitCents;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Comprobante · ${formatCents(widget.totalCents)}', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: PerchaSpace.md),
            SegmentedButton<bool>(
              segments: const [ButtonSegment(value: false, label: Text('Boleta')), ButtonSegment(value: true, label: Text('Factura'))],
              selected: {_factura},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() {
                _factura = s.first;
                _type = _factura ? DocType.ruc : DocType.none;
                _error = null;
              }),
            ),
            const SizedBox(height: PerchaSpace.md),
            if (!_factura)
              DropdownButtonFormField<DocType>(
                // Si el monto exige identificar al cliente, 'Clientes varios' deja de ser opción.
                value: needsId && _type == DocType.none ? null : _type,
                decoration: InputDecoration(labelText: 'Cliente', helperText: needsId ? 'Más de S/ ${widget.anonLimitCents ~/ 100}: SUNAT exige identificarlo' : null),
                items: [
                  if (!needsId) const DropdownMenuItem(value: DocType.none, child: Text('Clientes varios (sin documento)')),
                  const DropdownMenuItem(value: DocType.dni, child: Text('DNI')),
                  const DropdownMenuItem(value: DocType.ce, child: Text('Carné de extranjería')),
                  const DropdownMenuItem(value: DocType.ruc, child: Text('RUC')),
                ],
                onChanged: (v) => setState(() => _type = v ?? DocType.dni),
              ),
            if (_factura || _type != DocType.none) ...[
              const SizedBox(height: PerchaSpace.md),
              TextField(
                controller: _number,
                keyboardType: _type == DocType.ce ? TextInputType.text : TextInputType.number,
                // No deja escribir más dígitos de los que tiene el documento.
                inputFormatters: _factura || _type == DocType.ruc
                    ? F.digitsMax(11)
                    : _type == DocType.dni
                        ? F.digitsMax(8)
                        : [F.upper],
                onSubmitted: (_) => _type != DocType.ce ? _lookup() : null,
                decoration: InputDecoration(
                  labelText: _factura || _type == DocType.ruc ? 'RUC (11 dígitos)' : _type == DocType.dni ? 'DNI (8 dígitos)' : 'N.º de documento',
                  // El carné de extranjería no tiene consulta pública: se escribe a mano.
                  suffixIcon: _type == DocType.ce
                      ? null
                      : _searching
                          ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                          : IconButton(tooltip: _factura || _type == DocType.ruc ? 'Buscar en SUNAT' : 'Buscar en RENIEC', icon: const Icon(Icons.search), onPressed: _lookup),
                ),
              ),
              for (final w in _warnings) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Atención: $w', style: TextStyle(color: PerchaColors.warn, fontWeight: FontWeight.w600))),
              const SizedBox(height: PerchaSpace.md),
              TextField(controller: _name, decoration: InputDecoration(labelText: _factura ? 'Razón social' : 'Nombre completo')),
              if (_factura) ...[
                const SizedBox(height: PerchaSpace.md),
                TextField(controller: _address, decoration: const InputDecoration(labelText: 'Dirección fiscal (opcional)')),
              ],
            ],
            if (_error != null) ...[const SizedBox(height: PerchaSpace.md), ErrorBanner(_error!)],
            const SizedBox(height: PerchaSpace.lg),
            FilledButton(onPressed: _done, child: const Text('Listo')),
          ],
        ),
      ),
    );
  }
}
