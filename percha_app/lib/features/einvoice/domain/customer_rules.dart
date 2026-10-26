/// Mismas reglas que la API (percha-api/src/modules/einvoice/document.ts), para avisar en el
/// POS antes de cobrar. La API vuelve a validar: esto es comodidad, no la fuente de verdad.
enum DocType { none, dni, ruc, ce }

bool isValidRuc(String ruc) {
  if (!RegExp(r'^(10|15|16|17|20)\d{9}$').hasMatch(ruc)) return false;
  const weights = [5, 4, 3, 2, 7, 6, 5, 4, 3, 2];
  var sum = 0;
  for (var i = 0; i < 10; i++) {
    sum += weights[i] * int.parse(ruc[i]);
  }
  return (11 - sum % 11) % 10 == int.parse(ruc[10]);
}

/// Devuelve el problema a corregir, o null si el comprobante se puede emitir.
String? validateCustomer({
  required bool factura,
  required int totalCents,
  required int anonLimitCents,
  required DocType type,
  required String number,
  required String name,
}) {
  final n = number.trim();
  if (factura) {
    if (type != DocType.ruc || !isValidRuc(n)) return 'Ingresa un RUC válido';
    if (name.trim().length < 2) return 'Ingresa la razón social';
    return null;
  }
  if (type == DocType.none) {
    return totalCents > anonLimitCents ? 'Las boletas mayores a S/ ${anonLimitCents ~/ 100} deben llevar DNI, RUC o CE' : null;
  }
  final ok = switch (type) {
    DocType.dni => RegExp(r'^\d{8}$').hasMatch(n),
    DocType.ruc => isValidRuc(n),
    DocType.ce => RegExp(r'^[A-Za-z0-9]{8,12}$').hasMatch(n),
    DocType.none => true,
  };
  if (!ok) return 'Número de ${type.name.toUpperCase()} inválido';
  if (name.trim().length < 2) return 'Ingresa el nombre del cliente';
  return null;
}
