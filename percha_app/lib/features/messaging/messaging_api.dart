import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../auth/application/session_controller.dart';

class MessagingApi {
  const MessagingApi(this._api);
  final ApiClient _api;

  Future<bool> enabled() async => ((await _api.get('/messaging/status') as Map<String, dynamic>)['whatsapp'] as bool?) ?? false;
  Future<Map<String, dynamic>> settings() async => await _api.get('/messaging/settings') as Map<String, dynamic>;
  Future<void> save(Map<String, Object?> body) => _api.put('/messaging/settings', body: body);

  Future<Map<String, dynamic>> sendReceipt(String saleId, String phone, {bool force = false}) async =>
      await _api.post('/sales/$saleId/whatsapp', body: {'phone': phone, 'force': force}) as Map<String, dynamic>;
}

final messagingApiProvider = Provider<MessagingApi>((ref) => MessagingApi(ref.watch(apiClientProvider)));

/// ¿La tienda envía por WhatsApp? Si falla (sin permiso o sin red), se asume que no.
final whatsappEnabledProvider = FutureProvider<bool>((ref) async {
  ref.watch(sessionProvider.select((s) => s is SignedIn ? s.me.tenantId : null));
  try {
    return await ref.watch(messagingApiProvider).enabled();
  } catch (_) {
    return false;
  }
});

