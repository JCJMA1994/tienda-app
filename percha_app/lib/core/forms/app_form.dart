import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'formatters.dart';
import 'validators.dart';

/// Tipos de campo frecuentes, con teclado, formateo y autocompletado correctos por defecto.
enum FieldKind { text, name, email, password, newPassword, money, integer, dni, ruc, phone, url, upper }

/// Campo de texto único para toda la app.
///
/// Buenas prácticas incluidas:
/// - Etiqueta siempre visible (no solo placeholder) y texto de ayuda opcional.
/// - Teclado, autocompletado del sistema y formateo según el tipo de dato.
/// - Error en línea bajo el campo; se valida al interactuar (no antes de tocarlo).
/// - "Siguiente" en el teclado pasa al próximo campo; el último envía el formulario.
/// - Contraseñas con botón para mostrar/ocultar.
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    this.kind = FieldKind.text,
    this.validator,
    this.hint,
    this.helper,
    this.prefixText,
    this.suffix,
    this.maxLength,
    this.maxLines = 1,
    this.autofocus = false,
    this.enabled = true,
    this.last = false,
    this.onSubmitted,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final FieldKind kind;
  final Validator? validator;
  final String? hint;
  final String? helper;
  final String? prefixText;
  final Widget? suffix;
  final int? maxLength;
  final int maxLines;
  final bool autofocus;
  final bool enabled;

  /// Último campo del formulario: el teclado muestra "Listo" y llama a [onSubmitted].
  final bool last;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  bool _obscure = true;

  bool get _isPassword => widget.kind == FieldKind.password || widget.kind == FieldKind.newPassword;

  TextInputType get _keyboard => switch (widget.kind) {
        FieldKind.email => TextInputType.emailAddress,
        FieldKind.money => const TextInputType.numberWithOptions(decimal: true),
        FieldKind.integer || FieldKind.dni || FieldKind.ruc => TextInputType.number,
        FieldKind.phone => TextInputType.phone,
        FieldKind.url => TextInputType.url,
        FieldKind.name => TextInputType.name,
        _ => widget.maxLines > 1 ? TextInputType.multiline : TextInputType.text,
      };

  List<TextInputFormatter> get _formatters => [
        ...switch (widget.kind) {
          FieldKind.money => [F.money],
          FieldKind.integer => [F.digits],
          FieldKind.dni => F.digitsMax(8),
          FieldKind.ruc => F.digitsMax(11),
          FieldKind.phone => F.digitsMax(9),
          FieldKind.upper => [F.upper],
          _ => const <TextInputFormatter>[],
        },
        // Tope duro sin contador visible (el error explica el límite si hiciera falta).
        if (widget.maxLength != null) LengthLimitingTextInputFormatter(widget.maxLength),
      ];

  Iterable<String>? get _autofill => switch (widget.kind) {
        FieldKind.email => const [AutofillHints.email],
        FieldKind.password => const [AutofillHints.password],
        FieldKind.newPassword => const [AutofillHints.newPassword],
        FieldKind.name => const [AutofillHints.name],
        FieldKind.phone => const [AutofillHints.telephoneNumber],
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      keyboardType: _keyboard,
      inputFormatters: _formatters,
      autofillHints: _autofill,
      obscureText: _isPassword && _obscure,
      enableSuggestions: !_isPassword,
      autocorrect: widget.kind == FieldKind.text,
      textCapitalization: widget.kind == FieldKind.name ? TextCapitalization.words : TextCapitalization.none,
      maxLines: _isPassword ? 1 : widget.maxLines,
      textInputAction: widget.maxLines > 1 ? TextInputAction.newline : (widget.last ? TextInputAction.done : TextInputAction.next),
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: widget.validator,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        helperText: widget.helper,
        helperMaxLines: 2,
        errorMaxLines: 2,
        prefixText: widget.prefixText ?? (widget.kind == FieldKind.money ? 'S/ ' : null),
        suffixIcon: _isPassword
            ? IconButton(
                tooltip: _obscure ? 'Mostrar contraseña' : 'Ocultar contraseña',
                icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              )
            : widget.suffix,
      ),
    );
  }
}

/// Valida el formulario y, si hay errores, lleva la vista al PRIMER campo con error
/// (en formularios largos el usuario no tiene que buscarlo).
bool submitForm(GlobalKey<FormState> key) {
  final form = key.currentState;
  if (form == null) return false;
  final invalid = form.validateGranularly();
  if (invalid.isEmpty) return true;
  final first = invalid.first.context;
  if (first.mounted) Scrollable.ensureVisible(first, duration: const Duration(milliseconds: 250), alignment: 0.2);
  return false;
}
