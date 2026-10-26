import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../auth/application/session_controller.dart';

class AppNotification {
  const AppNotification({required this.id, required this.type, required this.title, required this.body, required this.createdAt, this.link, this.read = false});
  final String id;
  final String type;
  final String title;
  final String body;
  final String? link;
  final DateTime createdAt;
  final bool read;

  /// Solo rutas internas de la app: un enlace externo en una notificación nunca se abre.
  String? get safeLink => link != null && link!.startsWith('/') && !link!.startsWith('//') ? link : null;

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'] as String,
        type: j['type'] as String,
        title: j['title'] as String,
        body: j['body'] as String,
        link: j['link'] as String?,
        read: j['readAt'] != null,
        createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
      );
}

class NotificationsApi {
  const NotificationsApi(this._api);
  final ApiClient _api;

  Future<List<AppNotification>> list() async =>
      (await _api.get('/notifications', query: {'limit': 50}) as List<dynamic>).cast<Map<String, dynamic>>().map(AppNotification.fromJson).toList();

  Future<int> unread() async => ((await _api.get('/notifications/unread-count') as Map<String, dynamic>)['unread'] as num).toInt();
  Future<void> read(String id) => _api.post('/notifications/$id/read');
  Future<void> readAll() => _api.post('/notifications/read-all');
}

final notificationsApiProvider = Provider<NotificationsApi>((ref) => NotificationsApi(ref.watch(apiClientProvider)));

final notificationsProvider = FutureProvider.autoDispose<List<AppNotification>>((ref) => ref.watch(notificationsApiProvider).list());

/// Contador de no leídas: se consulta al iniciar y cada 60 s mientras hay sesión
/// (sin push configurado, así llegan los avisos). Se puede refrescar a mano tras leer.
class UnreadController extends Notifier<int> {
  Timer? _timer;

  @override
  int build() {
    final signedIn = ref.watch(sessionProvider.select((s) => s is SignedIn));
    _timer?.cancel();
    ref.onDispose(() => _timer?.cancel());
    if (!signedIn) return 0;
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => refresh());
    Future.microtask(refresh);
    return 0;
  }

  Future<void> refresh() async {
    try {
      state = await ref.read(notificationsApiProvider).unread();
    } catch (_) {
      // Sin red: se mantiene el último valor; no se interrumpe a nadie por un contador.
    }
  }
}

final unreadProvider = NotifierProvider<UnreadController, int>(UnreadController.new);
