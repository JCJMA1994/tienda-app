import 'package:intl/intl.dart';

/// El dinero viaja y se guarda en céntimos (int), igual que en la API.
/// Solo se convierte a texto al mostrarlo.
final _fmt = NumberFormat('#,##0.00', 'en_US');

String formatCents(int cents, {String symbol = 'S/'}) {
  final sign = cents < 0 ? '−' : '';
  return '$sign$symbol ${_fmt.format(cents.abs() / 100)}';
}

/// "189.90" o "189,90" -> 18990. Devuelve null si el texto no es un monto válido.
int? parseCents(String input) {
  final clean = input.trim().replaceAll(',', '.').replaceAll(RegExp(r'[^0-9.]'), '');
  if (clean.isEmpty || '.'.allMatches(clean).length > 1) return null;
  final parts = clean.split('.');
  final soles = int.tryParse(parts[0].isEmpty ? '0' : parts[0]);
  if (soles == null) return null;
  var decimals = parts.length > 1 ? parts[1] : '';
  if (decimals.length > 2) return null;
  decimals = decimals.padRight(2, '0');
  return soles * 100 + int.parse(decimals);
}
