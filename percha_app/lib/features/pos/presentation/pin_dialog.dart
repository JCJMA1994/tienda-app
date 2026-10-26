import '../../../core/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Pide un PIN de 4 a 6 dígitos. Se usa para cambiar de vendedor y para aprobaciones.
Future<String?> askPin(BuildContext context, {required String title, String? message}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _PinDialog(title: title, message: message),
  );
}

class _PinDialog extends StatefulWidget {
  const _PinDialog({required this.title, this.message});
  final String title;
  final String? message;

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final pin = _controller.text;
    if (RegExp(r'^\d{4,6}$').hasMatch(pin)) Navigator.pop(context, pin);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.message != null) ...[Text(widget.message!), const SizedBox(height: 16)],
          TextField(
            controller: _controller,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 6,
            style: const TextStyle(fontSize: PerchaType.display, letterSpacing: 12, fontWeight: FontWeight.w600),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'PIN', counterText: ''),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _submit, child: const Text('Confirmar')),
      ],
    );
  }
}
