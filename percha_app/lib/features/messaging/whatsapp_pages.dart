import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/forms/app_form.dart';
import '../../core/forms/validators.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/percha_widgets.dart';
import '../auth/application/session_controller.dart';
import 'messaging_api.dart';

export 'messaging_api.dart' show messagingApiProvider, whatsappEnabledProvider;

/// Pide el celular del cliente y envía el comprobante (o el resumen) por WhatsApp.
/// Solo a pedido del cliente: nunca mensajes masivos.
Future<void> sendReceiptByWhatsApp(BuildContext context, WidgetRef ref, String saleId) async {
  final phone = TextEditingController();
  final form = GlobalKey<FormState>();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Enviar por WhatsApp'),
      content: Form(
        key: form,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Le enviaremos el comprobante desde el WhatsApp de la tienda.'),
          const SizedBox(height: PerchaSpace.md),
          AppTextField(
            controller: phone,
            label: 'Celular del cliente',
            kind: FieldKind.phone,
            validator: V.phone(),
            autofocus: true,
            last: true,
            onSubmitted: (_) => submitForm(form) ? Navigator.pop(ctx, true) : null,
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => submitForm(form) ? Navigator.pop(ctx, true) : null, child: const Text('Enviar')),
      ],
    ),
  );
  final number = phone.text.trim();
  phone.dispose();
  if (ok != true || !context.mounted) return;

  Future<void> send({bool force = false}) async {
    try {
      final r = await ref.read(messagingApiProvider).sendReceipt(saleId, number, force: force);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r['message'] as String? ?? 'Enviado')));
    } catch (e) {
      if (!context.mounted) return;
      final msg = errorText(e);
      // Si ya se envió hace poco, se ofrece reenviar a conciencia (evita duplicados por doble toque).
      if (msg.contains('Ya se envió') || msg.contains('revisa el chat')) {
        final again = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('¿Reenviar?'),
            content: Text(msg),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reenviar')),
            ],
          ),
        );
        if (again == true) await send(force: true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  await send();
}

/// Configuración del WhatsApp de la tienda (Apachiy).
class WhatsAppSettingsPage extends ConsumerStatefulWidget {
  const WhatsAppSettingsPage({super.key});

  @override
  ConsumerState<WhatsAppSettingsPage> createState() => _WhatsAppSettingsPageState();
}

class _WhatsAppSettingsPageState extends ConsumerState<WhatsAppSettingsPage> {
  final _form = GlobalKey<FormState>();
  final _instance = TextEditingController();
  final _token = TextEditingController();
  bool _enabled = false;
  bool _hasToken = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    ref.read(messagingApiProvider).settings().then((s) {
      if (!mounted) return;
      setState(() {
        _enabled = s['enabled'] as bool;
        _hasToken = s['hasToken'] as bool;
        _instance.text = s['instance'] as String? ?? '';
        _loading = false;
      });
    }).catchError((Object e) {
      if (mounted) {
        setState(() {
          _error = errorText(e);
          _loading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _instance.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !submitForm(_form)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(messagingApiProvider).save({
        'enabled': _enabled,
        'instance': _instance.text.trim(),
        if (_token.text.trim().isNotEmpty) 'token': _token.text.trim(),
      });
      _token.clear();
      ref.invalidate(whatsappEnabledProvider);
      setState(() => _hasToken = _hasToken || true);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('WhatsApp configurado')));
    } catch (e) {
      setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('WhatsApp de la tienda')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                children: [
                  Text('Envía comprobantes a tus clientes desde el número de tu boutique, a través de Apachiy.', style: text.bodySmall),
                  const SizedBox(height: PerchaSpace.md),
                  Card(
                    color: PerchaColors.warnSoft,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        'Usa un número dedicado a la tienda y envía solo a clientes que te lo pidan. Este tipo de conexión vincula WhatsApp como dispositivo: si se usa para mensajes masivos, WhatsApp puede bloquear el número.',
                        style: TextStyle(color: PerchaColors.warn),
                      ),
                    ),
                  ),
                  const SizedBox(height: PerchaSpace.lg),
                  if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: PerchaSpace.md)],
                  Card(
                    child: SwitchListTile(
                      title: const Text('Ofrecer "Enviar por WhatsApp" al vender', style: TextStyle(fontWeight: FontWeight.w600)),
                      value: _enabled,
                      onChanged: (v) => setState(() => _enabled = v),
                    ),
                  ),
                  const SizedBox(height: PerchaSpace.lg),
                  AppTextField(
                    controller: _instance,
                    label: 'Número vinculado en Apachiy',
                    hint: '51987654321',
                    kind: FieldKind.integer,
                    maxLength: 15,
                    helper: 'Con código de país (51 para Perú), sin espacios ni +',
                    validator: (v) => RegExp(r'^\d{8,15}$').hasMatch(v ?? '') ? null : 'Ej. 51987654321',
                  ),
                  const SizedBox(height: PerchaSpace.md),
                  AppTextField(
                    controller: _token,
                    label: 'Token de Apachiy',
                    kind: FieldKind.password,
                    helper: _hasToken ? 'Ya hay un token guardado (cifrado). Escribe uno nuevo solo para cambiarlo.' : 'Se genera en el panel de Apachiy (permiso messages:send)',
                    validator: (v) => !_hasToken && _enabled && (v ?? '').trim().length < 10 ? 'Pega el token de Apachiy' : null,
                    last: true,
                  ),
                ],
              ),
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: BusyButton(label: 'Guardar', busy: _saving, onPressed: _loading ? null : _save),
        ),
      ),
    );
  }
}
