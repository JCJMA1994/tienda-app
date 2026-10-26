import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../auth/application/session_controller.dart';

class LookupResult {
  const LookupResult({required this.name, this.address, this.warnings = const []});
  final String name;
  final String? address;

  /// Ej. "Contribuyente NO HABIDO": se muestra, pero no impide emitir.
  final List<String> warnings;
}

/// Consulta RUC (SUNAT) o DNI (RENIEC) para autocompletar. Si el servicio no responde, la
/// pantalla deja escribir los datos a mano (nunca bloquea la venta).
class LookupApi {
  const LookupApi(this._api);
  final ApiClient _api;

  Future<LookupResult> ruc(String numero) async {
    final r = await _api.get('/lookup/ruc/$numero') as Map<String, dynamic>;
    return LookupResult(
      name: r['name'] as String,
      address: r['address'] as String?,
      warnings: (r['warnings'] as List<dynamic>).cast<String>(),
    );
  }

  Future<LookupResult> dni(String numero) async {
    final r = await _api.get('/lookup/dni/$numero') as Map<String, dynamic>;
    return LookupResult(name: r['name'] as String);
  }
}

final lookupApiProvider = Provider<LookupApi>((ref) => LookupApi(ref.watch(apiClientProvider)));
