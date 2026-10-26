import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_error.dart';
import '../../auth/application/session_controller.dart';
import '../data/pos_api.dart';

/// Venta hecha sin conexión, esperando sincronizarse. La [key] (idempotencia) es la misma en
/// cada intento: aunque se envíe dos veces, la API registra UNA venta.
class PendingSale {
  const PendingSale({required this.key, required this.body, required this.createdAt, this.error});
  final String key;
  final Map<String, dynamic> body;
  final DateTime createdAt;

  /// Motivo por el que la API la rechazó (requiere revisión); null si solo falta conexión.
  final String? error;

  int get totalCents => (body['payments'] as List<dynamic>).fold(0, (a, p) => a + ((p as Map<String, dynamic>)['amountCents'] as num).toInt());

  PendingSale copyWith({String? error}) => PendingSale(key: key, body: body, createdAt: createdAt, error: error);
  Map<String, Object?> toJson() => {'key': key, 'body': body, 'createdAt': createdAt.toIso8601String(), 'error': error};
  factory PendingSale.fromJson(Map<String, dynamic> j) =>
      PendingSale(key: j['key'] as String, body: j['body'] as Map<String, dynamic>, createdAt: DateTime.parse(j['createdAt'] as String), error: j['error'] as String?);
}

/// Errores que se resuelven solos al reintentar (no hace falta que alguien revise la venta):
/// caja cerrada, sesión vencida o sin permiso momentáneo, plan impago, demasiadas peticiones,
/// errores del servidor. Los rechazos de NEGOCIO (p. ej. 403 con código como APPROVAL_REQUIRED)
/// no se reintentan ciegamente y quedan marcados "por revisar".
bool _retryLater(ApiError e) {
  if (e.status == 403 && e.code != null && e.code != 'FORBIDDEN') return false;
  return e.code == 'CASH_CLOSED' ||
      e.code == 'IDEMPOTENCY_IN_PROGRESS' ||
      e.status == 401 ||
      e.status == 402 ||
      e.status == 403 ||
      e.status == 429 ||
      e.status >= 500;
}

/// Cola de ventas sin conexión, guardada en el dispositivo. Se sincroniza sola cada 30 s y al
/// pedirlo; en orden, de a una. Una venta solo sale de la cola cuando la API la confirma.
class OfflineSalesQueue extends Notifier<List<PendingSale>> {
  Timer? _timer;
  bool _syncing = false;

  String get _key {
    final s = ref.read(sessionProvider);
    return 'percha.offline.sales.${s is SignedIn ? s.me.tenantId : 'none'}';
  }

  @override
  List<PendingSale> build() {
    ref.watch(sessionProvider.select((s) => s is SignedIn ? s.me.tenantId : null));
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => sync());
    ref.onDispose(() => _timer?.cancel());
    Future.microtask(_load);
    return const [];
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    final saved = raw == null ? const <PendingSale>[] : (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>().map(PendingSale.fromJson).toList();
    // Lo encolado mientras se leía el disco no se pierde.
    final keys = {for (final p in saved) p.key};
    state = [...saved, ...state.where((p) => !keys.contains(p.key))];
    if (state.isNotEmpty) unawaited(sync());
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode([for (final p in state) p.toJson()]));
  }

  /// Ventas pendientes (no rechazadas) de una sucursal: hay que enviarlas antes de cerrar caja.
  int pendingFor(String branchId) => state.where((p) => p.error == null && p.body['branchId'] == branchId).length;

  Future<void> enqueue({required String key, required Map<String, Object?> body}) async {
    state = [...state, PendingSale(key: key, body: Map<String, dynamic>.from(body), createdAt: DateTime.now())];
    await _save();
  }

  /// Envía las pendientes. Devuelve cuántas se sincronizaron.
  Future<int> sync() async {
    if (_syncing || state.isEmpty) return 0;
    _syncing = true;
    var done = 0;
    try {
      for (final p in [...state]) {
        if (p.error != null) continue; // rechazadas: esperan revisión
        try {
          await ref.read(posApiProvider).postSale(p.body, idempotencyKey: p.key);
          state = state.where((x) => x.key != p.key).toList();
          done++;
        } on ApiError catch (e) {
          if (e.isNetwork) break; // sigue sin conexión: se reintenta luego
          if (_retryLater(e)) continue;
          state = [for (final x in state) x.key == p.key ? x.copyWith(error: e.message) : x];
        }
        await _save();
      }
    } finally {
      _syncing = false;
      await _save();
    }
    return done;
  }

  /// Reintentar una rechazada (p. ej. tras abrir caja o corregir datos).
  Future<void> retry(String key) async {
    state = [for (final x in state) x.key == key ? PendingSale(key: x.key, body: x.body, createdAt: x.createdAt) : x];
    await _save();
    await sync();
  }

  /// Descartar una rechazada (la tienda la registró de otra forma). Queda en el dispositivo
  /// solo hasta aquí: no se envía nunca.
  Future<void> discard(String key) async {
    state = state.where((x) => x.key != key).toList();
    await _save();
  }
}

final offlineQueueProvider = NotifierProvider<OfflineSalesQueue, List<PendingSale>>(OfflineSalesQueue.new);
