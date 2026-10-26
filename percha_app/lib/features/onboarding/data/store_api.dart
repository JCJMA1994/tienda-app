import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/application/session_controller.dart';

class StoreSettings {
  const StoreSettings({
    required this.name,
    required this.ruc,
    required this.currency,
    required this.taxRateBp,
    required this.pricesIncludeTax,
    required this.discountLimitBp,
  });

  final String name;
  final String? ruc;
  final String currency;
  final int taxRateBp;
  final bool pricesIncludeTax;
  final int discountLimitBp;

  factory StoreSettings.fromJson(Map<String, dynamic> j) => StoreSettings(
        name: j['name'] as String,
        ruc: j['ruc'] as String?,
        currency: j['currency'] as String,
        taxRateBp: j['taxRateBp'] as int,
        pricesIncludeTax: j['pricesIncludeTax'] as bool,
        discountLimitBp: j['discountLimitBp'] as int,
      );
}

class Branch {
  const Branch({required this.id, required this.name, this.address, this.ubigeo, required this.isDefault});
  final String id;
  final String name;
  final String? address;

  /// Ubigeo INEI (6 dígitos): lo pide la guía de remisión.
  final String? ubigeo;
  final bool isDefault;

  factory Branch.fromJson(Map<String, dynamic> j) => Branch(
        id: j['id'] as String,
        name: j['name'] as String,
        address: j['address'] as String?,
        ubigeo: j['ubigeo'] as String?,
        isDefault: j['isDefault'] as bool,
      );
}

class OnboardingStep {
  const OnboardingStep({required this.key, required this.label, required this.done});
  final String key;
  final String label;
  final bool done;
}

class OnboardingProgress {
  const OnboardingProgress({required this.steps, required this.completed, required this.total, this.nextStep, required this.dismissed});
  final List<OnboardingStep> steps;
  final int completed;
  final int total;
  final String? nextStep;
  final bool dismissed;

  bool get visible => !dismissed && completed < total;
  OnboardingStep? get next => steps.where((s) => s.key == nextStep).firstOrNull;

  factory OnboardingProgress.fromJson(Map<String, dynamic> j) => OnboardingProgress(
        steps: (j['steps'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map((s) => OnboardingStep(key: s['key'] as String, label: s['label'] as String, done: s['done'] as bool))
            .toList(),
        completed: j['completed'] as int,
        total: j['total'] as int,
        nextStep: j['nextStep'] as String?,
        dismissed: j['dismissed'] as bool,
      );
}

class StoreApi {
  const StoreApi(this._api);
  final ApiClient _api;

  Future<StoreSettings> get() async => StoreSettings.fromJson(await _api.get('/store') as Map<String, dynamic>);

  Future<void> update(Map<String, Object?> changes) => _api.patch('/store', body: changes);

  Future<List<Branch>> branches() async =>
      (await _api.get('/branches') as List<dynamic>).cast<Map<String, dynamic>>().map(Branch.fromJson).toList();

  Future<void> updateBranch(String id, Map<String, Object?> changes) => _api.patch('/branches/$id', body: changes);

  Future<void> createBranch(Map<String, Object?> body) => _api.post('/branches', body: body);

  Future<OnboardingProgress> onboarding() async =>
      OnboardingProgress.fromJson(await _api.get('/store/onboarding') as Map<String, dynamic>);

  Future<void> dismissOnboarding() => _api.post('/store/onboarding/dismiss');

  Future<List<Map<String, dynamic>>> attributes() async =>
      (await _api.get('/attributes') as List<dynamic>).cast<Map<String, dynamic>>();

  Future<void> createAttribute({required String name, required int position, required List<String> values}) =>
      _api.post('/attributes', body: {'name': name, 'position': position, 'values': values});
}

final storeApiProvider = Provider<StoreApi>((ref) => StoreApi(ref.watch(apiClientProvider)));

final onboardingProvider = FutureProvider.autoDispose<OnboardingProgress>((ref) => ref.watch(storeApiProvider).onboarding());

final storeSettingsProvider = FutureProvider<StoreSettings>((ref) {
  ref.watch(sessionProvider); // se recarga si cambia la sesión (otra tienda)
  return ref.watch(storeApiProvider).get();
});

/// Sucursal en la que opera este dispositivo: la fija del usuario o la principal.
final currentBranchProvider = FutureProvider<Branch>((ref) async {
  final me = ref.watch(meProvider);
  final list = await ref.watch(storeApiProvider).branches();
  return list.firstWhere(
    (b) => b.id == me.branchId,
    orElse: () => list.firstWhere((b) => b.isDefault, orElse: () => list.first),
  );
});
