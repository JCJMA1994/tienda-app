import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/theme/tokens.dart';

/// Resultado de procesar una lectura en modo continuo: texto para mostrar y si fue un acierto.
typedef ScanFeedback = ({String message, bool ok});

/// Lee UN código y vuelve (p. ej. el código de un vale, o buscar una prenda).
Future<String?> scanOnce(BuildContext context) => Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ScannerPage()));

/// Modo continuo: la cámara queda abierta y cada lectura se procesa con [onCode] (agregar al
/// ticket, sumar al conteo). Ideal para pasar muchas prendas seguidas.
Future<void> scanContinuous(BuildContext context, {required String title, required Future<ScanFeedback> Function(String code) onCode}) =>
    Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => ScannerPage(title: title, onCode: onCode)));

/// Lector con la cámara.
///
/// - Lee EAN-13/8, UPC-A/E, Code 128, Code 39 y QR, solo dentro del recuadro (no lee las
///   etiquetas vecinas del colgador).
/// - Vibra al leer; en modo continuo, ignora el MISMO código durante 1,5 s (la cámara lo lee
///   muchas veces por segundo) y muestra el resultado de cada lectura.
/// - Linterna, y se apaga la cámara al salir de la app.
/// - Si no hay permiso de cámara, lo explica. En web abre un campo para lector USB.
class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key, this.title = 'Escanear', this.onCode});
  final String title;

  /// Si se indica, modo continuo; si no, devuelve el primer código leído.
  final Future<ScanFeedback> Function(String code)? onCode;

  @override
  // ignore: no_logic_in_create_state
  State<ScannerPage> createState() => kIsWeb ? _WebCodeEntryState() : _ScannerPageState();
}

/// Panel web: en caja se usa un lector USB (escribe el código y presiona Enter). La cámara del
/// navegador necesitaría cargar un decodificador de un CDN externo, que la CSP no permite.
class _WebCodeEntryState extends State<ScannerPage> {
  final _code = TextEditingController();
  final _focus = FocusNode();
  ScanFeedback? _last;

  @override
  void dispose() {
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final v = _code.text.trim();
    if (v.isEmpty) return;
    if (widget.onCode == null) return Navigator.of(context).pop(v);
    _code.clear();
    final r = await widget.onCode!(v);
    if (mounted) setState(() => _last = r);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.qr_code_scanner, size: 56),
              const SizedBox(height: 16),
              const Text('Escanea con el lector USB o escribe el código y presiona Enter.', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              TextField(
                controller: _code,
                focusNode: _focus,
                autofocus: true,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(labelText: 'Código de barras, SKU o código de vale'),
                onSubmitted: (_) => _submit(),
              ),
              if (_last != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_last!.message, style: TextStyle(color: _last!.ok ? PerchaColors.accentInk : PerchaColors.warn, fontWeight: FontWeight.w600))),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, child: FilledButton(onPressed: _submit, child: Text(widget.onCode == null ? 'Usar código' : 'Agregar'))),
            ],),
          ),
        ),
      ),
    );
  }
}

class _ScannerPageState extends State<ScannerPage> with WidgetsBindingObserver {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.upcA, BarcodeFormat.upcE, BarcodeFormat.code128, BarcodeFormat.code39, BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.normal,
  );
  bool _done = false;
  bool _busy = false;
  String? _lastCode;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);
  ScanFeedback? _feedback;
  int _reads = 0;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // La cámara no queda encendida en segundo plano (batería y privacidad).
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) unawaited(_controller.stop());
    if (state == AppLifecycleState.resumed) unawaited(_controller.start());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hide?.cancel();
    unawaited(_controller.dispose());
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    final code = capture.barcodes.map((b) => b.rawValue).whereType<String>().map((c) => c.trim()).where((c) => c.isNotEmpty).firstOrNull;
    if (code == null || _done || _busy) return;

    if (widget.onCode == null) {
      _done = true; // un solo código: se devuelve y se cierra
      await HapticFeedback.mediumImpact();
      if (!mounted) return;
      Navigator.pop(context, code);
      return;
    }

    // Continuo: la misma etiqueta se lee varias veces por segundo; se cuenta una vez cada 1,5 s.
    final now = DateTime.now();
    if (code == _lastCode && now.difference(_lastAt) < const Duration(milliseconds: 1500)) return;
    _lastCode = code;
    _lastAt = now;
    _busy = true;
    try {
      final r = await widget.onCode!(code);
      await (r.ok ? HapticFeedback.mediumImpact() : HapticFeedback.heavyImpact());
      if (!mounted) return;
      setState(() {
        _feedback = r;
        if (r.ok) _reads++;
      });
      _hide?.cancel();
      _hide = Timer(const Duration(seconds: 3), () => mounted ? setState(() => _feedback = null) : null);
    } finally {
      _busy = false;
      // Se puede volver a leer la misma prenda (dos unidades iguales) pasado el intervalo.
      _lastAt = DateTime.now();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.onCode != null && _reads > 0 ? '${widget.title} · $_reads' : widget.title, style: const TextStyle(color: Colors.white)),
        actions: [
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (_, state, __) => IconButton(
              tooltip: state.torchState == TorchState.on ? 'Apagar linterna' : 'Encender linterna',
              color: Colors.white,
              icon: Icon(state.torchState == TorchState.on ? Icons.flashlight_off_outlined : Icons.flashlight_on_outlined),
              onPressed: state.torchState == TorchState.unavailable ? null : _controller.toggleTorch,
            ),
          ),
          if (widget.onCode != null) TextButton(onPressed: () => Navigator.pop(context), child: const Text('Listo', style: TextStyle(color: Colors.white))),
        ],
      ),
      body: LayoutBuilder(builder: (context, c) {
        // Recuadro centrado y ancho (los códigos de barras son horizontales).
        final w = c.maxWidth * 0.82;
        final h = (w * 0.62).clamp(140.0, 320.0);
        final window = Rect.fromCenter(center: Offset(c.maxWidth / 2, c.maxHeight * 0.42), width: w, height: h);
        return Stack(fit: StackFit.expand, children: [
          MobileScanner(controller: _controller, scanWindow: window, onDetect: _onDetect),
          IgnorePointer(child: CustomPaint(painter: _WindowPainter(window))),
          Positioned(
            left: 24,
            right: 24,
            top: window.bottom + 16,
            child: Text(
              widget.onCode == null ? 'Centra el código dentro del recuadro' : 'Pasa las prendas una por una. Toca "Listo" al terminar.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: PerchaType.strong),
            ),
          ),
          if (_feedback != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 24 + MediaQuery.paddingOf(context).bottom,
              // Tarjeta clara sobre la cámara (siempre oscura): legible en modo claro y oscuro.
              child: Material(
                color: Colors.white,
                elevation: 2,
                borderRadius: BorderRadius.circular(PerchaRadius.card),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    Icon(_feedback!.ok ? Icons.check_circle : Icons.error_outline, color: _feedback!.ok ? PerchaPalette.light.success : PerchaPalette.light.warn),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_feedback!.message, style: TextStyle(color: PerchaPalette.light.ink, fontWeight: FontWeight.w600))),
                  ],),
                ),
              ),
            ),
          // Sin permiso o sin cámara: explicación clara en lugar de una pantalla negra.
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (_, state, __) => state.error == null
                ? const SizedBox.shrink()
                : Container(
                    color: Colors.black,
                    padding: const EdgeInsets.all(32),
                    alignment: Alignment.center,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.no_photography_outlined, color: Colors.white, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        state.error!.errorCode == MobileScannerErrorCode.permissionDenied
                            ? 'Percha no tiene permiso para usar la cámara. Actívalo en los ajustes del teléfono (Aplicaciones → Percha → Permisos).'
                            : 'No se pudo abrir la cámara. Puedes escribir el código o usar un lector USB.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton(onPressed: () => Navigator.pop(context), style: OutlinedButton.styleFrom(foregroundColor: Colors.white), child: const Text('Volver')),
                    ],),
                  ),
          ),
        ],);
      },),
    );
  }
}

/// Oscurece todo menos el recuadro de lectura.
class _WindowPainter extends CustomPainter {
  _WindowPainter(this.window);
  final Rect window;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(window, const Radius.circular(16));
    canvas.drawPath(Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRRect(r)), Paint()..color = const Color(0x99000000));
    canvas.drawRRect(r, Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3,);
  }

  @override
  bool shouldRepaint(covariant _WindowPainter old) => old.window != window;
}
