import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Impide capturas y grabación de pantalla mientras este widget está visible (Android:
/// FLAG_SECURE; también oculta el contenido en "apps recientes"). Para pantallas con secretos:
/// códigos de recuperación, QR de 2FA.
///
/// Requiere el código nativo de `docs/13-pendientes.md` en MainActivity (canal `percha/secure`).
/// Si el canal no existe (iOS, web o sin configurar), no hace nada: nunca rompe la pantalla.
class SecureScreen extends StatefulWidget {
  const SecureScreen({super.key, required this.child});
  final Widget child;

  @override
  State<SecureScreen> createState() => _SecureScreenState();
}

class _SecureScreenState extends State<SecureScreen> {
  static const _channel = MethodChannel('percha/secure');

  Future<void> _set(bool on) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>(on ? 'enable' : 'disable');
    } on MissingPluginException {
      // Canal no configurado: se ignora.
    } on PlatformException {
      // Igual: la protección es una capa extra, no un requisito para usar la app.
    }
  }

  @override
  void initState() {
    super.initState();
    _set(true);
  }

  @override
  void dispose() {
    _set(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
