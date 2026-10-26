import 'package:flutter/material.dart';

import '../money.dart';
import 'app_form.dart';
import 'validators.dart';

/// Diálogos de un solo dato con el MISMO sistema de validación que los formularios:
/// error en línea, teclado correcto, Enter confirma y no se cierra con un valor inválido.
Future<int?> promptMoney(
  BuildContext context, {
  required String title,
  String label = 'Monto',
  int? initialCents,
  String? helper,
  String? message,
  bool allowZero = true,
  int? minCents,
  String confirm = 'Aceptar',
}) async {
  final text = await _prompt(
    context,
    title: title,
    message: message,
    field: (c, submit) => AppTextField(
      controller: c,
      label: label,
      kind: FieldKind.money,
      helper: helper,
      autofocus: true,
      last: true,
      onSubmitted: (_) => submit(),
      validator: V.all([
        V.money(positive: !allowZero),
        (v) {
          final cents = parseCents(v ?? '');
          return minCents != null && cents != null && cents < minCents ? 'Mínimo ${formatCents(minCents)}' : null;
        },
      ]),
    ),
    initial: initialCents == null ? '' : (initialCents / 100).toStringAsFixed(2),
    confirm: confirm,
  );
  return text == null ? null : parseCents(text);
}

Future<int?> promptInt(
  BuildContext context, {
  required String title,
  required String label,
  int? initial,
  int min = 0,
  int? max,
  String? helper,
  String confirm = 'Guardar',
}) async {
  final text = await _prompt(
    context,
    title: title,
    field: (c, submit) => AppTextField(
      controller: c,
      label: label,
      kind: FieldKind.integer,
      helper: helper,
      autofocus: true,
      last: true,
      onSubmitted: (_) => submit(),
      validator: V.intRange(min: min, max: max),
    ),
    initial: initial?.toString() ?? '',
    confirm: confirm,
  );
  return text == null ? null : int.parse(text);
}

Future<String?> _prompt(
  BuildContext context, {
  required String title,
  String? message,
  required Widget Function(TextEditingController controller, VoidCallback submit) field,
  required String initial,
  required String confirm,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _PromptDialog(title: title, message: message, field: field, initial: initial, confirm: confirm),
  );
}

class _PromptDialog extends StatefulWidget {
  const _PromptDialog({required this.title, required this.field, required this.initial, required this.confirm, this.message});
  final String title;
  final String? message;
  final Widget Function(TextEditingController controller, VoidCallback submit) field;
  final String initial;
  final String confirm;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  final _form = GlobalKey<FormState>();
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() {
    if (submitForm(_form)) Navigator.pop(context, _c.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.message != null) ...[Text(widget.message!), const SizedBox(height: 16)],
            widget.field(_c, _submit),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _submit, child: Text(widget.confirm)),
      ],
    );
  }
}
