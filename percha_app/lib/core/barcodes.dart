/// Normalización de códigos leídos por cámara o lector USB (puro, probado; la API aplica la
/// misma regla al buscar).
///
/// - Quita espacios y caracteres de control que agregan algunos lectores (`\r`, `\t`).
/// - UPC-A (12 dígitos) y EAN-13 con un 0 adelante son el MISMO código: una prenda importada
///   etiquetada con UPC se encuentra aunque esté registrada como EAN-13, y al revés.
List<String> barcodeCandidates(String raw) {
  final code = raw.replaceAll(RegExp(r'[\x00-\x1F\x7F\s]'), '');
  if (code.isEmpty) return const [];
  return {
    code,
    if (RegExp(r'^\d{12}$').hasMatch(code)) '0$code',
    if (RegExp(r'^0\d{12}$').hasMatch(code)) code.substring(1),
  }.toList();
}

/// QR de un vale o gift card de Percha (no es una prenda: se usa al cobrar).
bool isCreditCode(String raw) => RegExp(r'^VALE-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$').hasMatch(raw.trim().toUpperCase());
