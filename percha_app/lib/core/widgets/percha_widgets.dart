import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../network/api_error.dart';
import '../theme/tokens.dart';

/// Marca: percha dibujada a mano (sin assets) + nombre.
class PerchaLogo extends StatelessWidget {
  const PerchaLogo({super.key, this.size = 40, this.showName = true});
  final double size;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: PerchaColors.accent, borderRadius: BorderRadius.circular(size * 0.3)),
          child: CustomPaint(painter: _HangerPainter()),
        ),
        if (showName) ...[
          const SizedBox(width: 10),
          Text('Percha', style: GoogleFonts.interTight(fontSize: size * 0.55, fontWeight: FontWeight.w700, letterSpacing: -0.6)),
        ],
      ],
    );
  }
}

class _HangerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final p = Paint()
      ..color = PerchaColors.onAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..addArc(Rect.fromCircle(center: Offset(12 * s, 6 * s), radius: 2 * s), 3.14, 4.4)
      ..moveTo(12 * s, 8 * s)
      ..lineTo(12 * s, 9.5 * s)
      ..lineTo(3.6 * s, 15.8 * s)
      ..lineTo(20.4 * s, 15.8 * s)
      ..close();
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Mensaje de error en línea (en lugar de diálogos que interrumpen).
class ErrorBanner extends StatelessWidget {
  const ErrorBanner(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(PerchaSpace.md),
        decoration: BoxDecoration(color: PerchaColors.warnSoft, borderRadius: BorderRadius.circular(PerchaRadius.field)),
        child: Text(message, style: TextStyle(color: PerchaColors.warn, fontWeight: FontWeight.w500)),
      ),
    );
  }
}

/// Barra de progreso por pasos del onboarding (5 segmentos).
class StepsBar extends StatelessWidget {
  const StepsBar({super.key, required this.current, this.total = 5});
  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Paso $current de $total',
      child: Row(
        children: [
          for (var i = 0; i < total; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  color: i < current ? PerchaColors.accent : PerchaColors.borderStrong,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Botón principal con estado de carga (evita dobles envíos en el POS).
class BusyButton extends StatelessWidget {
  const BusyButton({super.key, required this.label, required this.onPressed, this.busy = false});
  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: PerchaColors.onAccent))
          : Text(label),
    );
  }
}

/// Píldora de estado (stock bajo, rol...).
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.warn = false, this.dark = false});
  final String text;
  final bool warn;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = warn
        ? (PerchaColors.warnSoft, PerchaColors.warn)
        : dark
            ? (PerchaColors.inverse, PerchaColors.onInverse)
            : (PerchaColors.surfaceAlt, PerchaColors.ink);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(PerchaRadius.pill)),
      child: Text(text, style: TextStyle(color: fg, fontSize: PerchaType.meta, fontWeight: FontWeight.w600)),
    );
  }
}

/// Texto amigable para cualquier error capturado en la UI.
String errorText(Object e) => e is ApiError ? e.message : 'Ocurrió un error inesperado';
