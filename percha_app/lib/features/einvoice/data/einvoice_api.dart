import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/application/session_controller.dart';
import 'einvoice_models.dart';

export 'einvoice_models.dart';

class EInvoiceApi {
  const EInvoiceApi(this._api);
  final ApiClient _api;

  Future<EInvoiceStatus> status() async {
    final r = await _api.get('/einvoice/status') as Map<String, dynamic>;
    return EInvoiceStatus(enabled: r['enabled'] as bool, anonLimitCents: (r['boletaAnonLimitCents'] as num).toInt());
  }

  Future<Map<String, dynamic>> settings() async => await _api.get('/einvoice/settings') as Map<String, dynamic>;
  Future<void> save(Map<String, Object?> body) => _api.put('/einvoice/settings', body: body);

  Future<List<EDocument>> list({String? status}) async =>
      (await _api.get('/einvoices', query: {'status': status}) as List<dynamic>).cast<Map<String, dynamic>>().map(EDocument.fromJson).toList();

  Future<EDocument> retry(String id) async => EDocument.fromJson(await _api.post('/einvoices/$id/retry') as Map<String, dynamic>);
}

final einvoiceApiProvider = Provider<EInvoiceApi>((ref) => EInvoiceApi(ref.watch(apiClientProvider)));

/// Se lee una vez por sesión: el POS necesita saber si mostrar el selector de comprobante.
final einvoiceStatusProvider = FutureProvider<EInvoiceStatus>((ref) {
  ref.watch(sessionProvider.select((s) => s is SignedIn ? s.me.tenantId : null));
  return ref.watch(einvoiceApiProvider).status();
});

final problemDocsProvider = FutureProvider.autoDispose<List<EDocument>>((ref) async {
  final api = ref.watch(einvoiceApiProvider);
  final lists = await Future.wait([api.list(status: 'error'), api.list(status: 'rejected'), api.list(status: 'pending')]);
  return [for (final l in lists) ...l];
});
