import '../../features/einvoice/domain/customer_rules.dart' show isValidRuc;
import '../money.dart';

/// Validadores reutilizables. Devuelven el mensaje de error o null.
///
/// Reglas de redacción (consistentes en toda la app):
/// - Dicen QUÉ hacer, no solo qué está mal ("Ingresa un correo válido", no "Correo inválido").
/// - Son cortos: se muestran bajo el campo.
/// - Son los MISMOS límites que valida la API (zod), para no aceptar en la app lo que el
///   servidor va a rechazar.
typedef Validator = String? Function(String? value);

abstract final class V {
  static Validator required([String message = 'Este campo es obligatorio']) =>
      (v) => (v ?? '').trim().isEmpty ? message : null;

  static Validator minLength(int n, [String? message]) =>
      (v) => (v ?? '').trim().length < n ? (message ?? 'Mínimo $n caracteres') : null;

  static Validator maxLength(int n) => (v) => (v ?? '').trim().length > n ? 'Máximo $n caracteres' : null;

  static final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');
  static Validator email() => (v) => _email.hasMatch((v ?? '').trim()) ? null : 'Ingresa un correo válido';

  /// Igual que la API: 8 a 128 caracteres. Se sugiere mezclar letras y números.
  static Validator password() => (v) {
        final s = v ?? '';
        if (s.length < 8) return 'Mínimo 8 caracteres';
        if (s.length > 128) return 'Máximo 128 caracteres';
        if (!RegExp(r'[A-Za-z]').hasMatch(s) || !RegExp(r'\d').hasMatch(s)) return 'Usa letras y números';
        return null;
      };

  static Validator dni() => (v) => RegExp(r'^\d{8}$').hasMatch((v ?? '').trim()) ? null : 'El DNI tiene 8 dígitos';

  /// RUC con prefijo válido y dígito verificador (módulo 11), igual que la API.
  static Validator ruc({bool optional = false}) => (v) {
        final s = (v ?? '').trim();
        if (s.isEmpty && optional) return null;
        if (!RegExp(r'^\d{11}$').hasMatch(s)) return 'El RUC tiene 11 dígitos';
        return isValidRuc(s) ? null : 'RUC inválido: revisa los números';
      };

  /// Celular peruano: 9 dígitos que empiezan con 9.
  static Validator phone({bool optional = false}) => (v) {
        final s = (v ?? '').replaceAll(RegExp(r'\s'), '');
        if (s.isEmpty && optional) return null;
        return RegExp(r'^9\d{8}$').hasMatch(s) ? null : 'Celular de 9 dígitos que empieza con 9';
      };

  /// Monto en soles: formato válido y, opcionalmente, mayor a cero o con tope.
  static Validator money({bool optional = false, bool positive = false, int? maxCents}) => (v) {
        final s = (v ?? '').trim();
        if (s.isEmpty) return optional ? null : 'Ingresa un monto';
        final c = parseCents(s);
        if (c == null) return 'Monto inválido (ej. 189.90)';
        if (positive && c <= 0) return 'Debe ser mayor a 0';
        if (maxCents != null && c > maxCents) return 'Máximo ${formatCents(maxCents)}';
        return null;
      };

  static Validator intRange({int min = 0, int? max, bool optional = false}) => (v) {
        final s = (v ?? '').trim();
        if (s.isEmpty) return optional ? null : 'Ingresa una cantidad';
        final n = int.tryParse(s);
        if (n == null) return 'Solo números enteros';
        if (n < min) return 'Mínimo $min';
        if (max != null && n > max) return 'Máximo $max';
        return null;
      };

  static Validator url() => (v) {
        final u = Uri.tryParse((v ?? '').trim());
        return u != null && u.hasScheme && (u.scheme == 'https' || u.scheme == 'http') && u.host.isNotEmpty ? null : 'Ingresa una URL completa (https://…)';
      };

  /// Serie SUNAT de 4 caracteres que empieza con B o F.
  static Validator serie(String prefix) =>
      (v) => RegExp('^$prefix[A-Z0-9]{3}\$').hasMatch((v ?? '').trim().toUpperCase()) ? null : 'Empieza con $prefix y tiene 4 caracteres';

  /// Aplica varias reglas en orden y devuelve el primer error.
  static Validator all(List<Validator> rules) => (v) {
        for (final r in rules) {
          final e = r(v);
          if (e != null) return e;
        }
        return null;
      };
}
