import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/application/session_controller.dart';

int _i(Object? v) => (v as num?)?.toInt() ?? 0;
DateTime? _d(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();

class PlanLimits {
  const PlanLimits({this.branches, this.members, this.products});

  /// null = ilimitado.
  final int? branches;
  final int? members;
  final int? products;

  factory PlanLimits.fromJson(Map<String, dynamic> j) =>
      PlanLimits(branches: j['branches'] as int?, members: j['members'] as int?, products: j['products'] as int?);
}

class PlanInfo {
  const PlanInfo({required this.code, required this.name, required this.priceCents, required this.currency, required this.limits});
  final String code;
  final String name;
  final int priceCents;
  final String currency;
  final PlanLimits limits;

  factory PlanInfo.fromJson(Map<String, dynamic> j) => PlanInfo(
        code: j['code'] as String,
        name: j['name'] as String,
        priceCents: _i(j['priceCents']),
        currency: j['currency'] as String,
        limits: PlanLimits.fromJson(j['limits'] as Map<String, dynamic>),
      );
}

class Invoice {
  const Invoice({required this.id, required this.number, required this.amountCents, required this.status, required this.dueAt, this.paidAt, this.method});
  final String id;
  final int number;
  final int amountCents;
  final String status;
  final DateTime dueAt;
  final DateTime? paidAt;
  final String? method;

  factory Invoice.fromJson(Map<String, dynamic> j) => Invoice(
        id: j['id'] as String,
        number: _i(j['number']),
        amountCents: _i(j['amountCents']),
        status: j['status'] as String,
        dueAt: _d(j['dueAt'])!,
        paidAt: _d(j['paidAt']),
        method: j['method'] as String?,
      );
}

/// trialing · active · past_due · suspended · canceled (igual que la API).
class BillingOverview {
  const BillingOverview({
    required this.status,
    required this.readOnly,
    required this.plan,
    required this.usage,
    required this.openInvoices,
    required this.history,
    required this.providers,
    required this.cancelAtPeriodEnd,
    required this.autopay,
    this.trialEndsAt,
    this.currentPeriodEnd,
    this.graceEndsAt,
  });

  final String status;
  final bool readOnly;
  final PlanInfo plan;
  final ({int branches, int members, int products}) usage;
  final List<Invoice> openInvoices;
  final List<Invoice> history;

  /// Pasarelas configuradas en el servidor y sus medios.
  final Map<String, List<String>> providers;
  final bool cancelAtPeriodEnd;
  final bool autopay;
  final DateTime? trialEndsAt;
  final DateTime? currentPeriodEnd;
  final DateTime? graceEndsAt;

  int? get trialDaysLeft => status == 'trialing' && trialEndsAt != null ? trialEndsAt!.difference(DateTime.now()).inDays : null;

  /// ¿Hay que llamar la atención en el inicio?
  bool get needsAttention =>
      status == 'past_due' || readOnly || (trialDaysLeft != null && trialDaysLeft! <= 5) || cancelAtPeriodEnd;

  factory BillingOverview.fromJson(Map<String, dynamic> j) {
    final usage = j['usage'] as Map<String, dynamic>;
    return BillingOverview(
      status: j['status'] as String,
      readOnly: j['readOnly'] as bool,
      plan: PlanInfo.fromJson(j['plan'] as Map<String, dynamic>),
      usage: (branches: _i(usage['branches']), members: _i(usage['members']), products: _i(usage['products'])),
      openInvoices: (j['openInvoices'] as List<dynamic>).cast<Map<String, dynamic>>().map(Invoice.fromJson).toList(),
      history: (j['history'] as List<dynamic>).cast<Map<String, dynamic>>().map(Invoice.fromJson).toList(),
      providers: {
        for (final p in (j['providers'] as List<dynamic>).cast<Map<String, dynamic>>())
          p['name'] as String: (p['methods'] as List<dynamic>).cast<String>(),
      },
      cancelAtPeriodEnd: j['cancelAtPeriodEnd'] as bool,
      autopay: j['autopay'] as bool,
      trialEndsAt: _d(j['trialEndsAt']),
      currentPeriodEnd: _d(j['currentPeriodEnd']),
      graceEndsAt: _d(j['graceEndsAt']),
    );
  }
}

/// Una forma concreta de pagar que ofrece la pantalla (pasarela + medio).
class PayOption {
  const PayOption(this.provider, this.method, this.label, this.detail);
  final String provider;
  final String method;
  final String label;
  final String detail;
}

/// Opciones según lo que el servidor tenga configurado. Yape y billeteras van por Culqi;
/// Stripe solo tarjeta (no ofrece Yape ni Plin).
List<PayOption> payOptions(Map<String, List<String>> providers) => [
      for (final entry in providers.entries)
        for (final m in entry.value)
          if (entry.key == 'culqi' && m == 'yape')
            const PayOption('culqi', 'yape', 'Yape', 'Pagas desde tu app de Yape')
          else if (entry.key == 'culqi' && m == 'wallet_qr')
            const PayOption('culqi', 'wallet_qr', 'Otras billeteras (QR)', 'Según los medios habilitados en Culqi')
          else if (entry.key == 'stripe' && m == 'card')
            const PayOption('stripe', 'card', 'Tarjeta (Stripe)', 'Visa, Mastercard, tarjetas internacionales')
          else if (entry.key == 'fake')
            PayOption('fake', m, 'Prueba: $m', 'Pasarela simulada (solo desarrollo)'),
    ];

class BillingApi {
  const BillingApi(this._api);
  final ApiClient _api;

  Future<BillingOverview> overview() async => BillingOverview.fromJson(await _api.get('/billing') as Map<String, dynamic>);

  Future<List<PlanInfo>> plans() async =>
      (await _api.get('/billing/plans') as List<dynamic>).cast<Map<String, dynamic>>().map(PlanInfo.fromJson).toList();

  Future<void> changePlan(String code) => _api.post('/billing/plan', body: {'planCode': code});

  /// Devuelve la URL a abrir (Stripe Checkout o la página de Culqi de la API).
  Future<String> pay(String invoiceId, PayOption option) async {
    final res = await _api.post('/billing/invoices/$invoiceId/pay', body: {'provider': option.provider, 'method': option.method})
        as Map<String, dynamic>;
    return res['url'] as String;
  }

  /// Enlace a la página de la API donde Culqi tokeniza la tarjeta (cobro automático).
  Future<String> cardSetupLink() async => (await _api.post('/billing/card/setup-link') as Map<String, dynamic>)['url'] as String;

  Future<void> cancel() => _api.post('/billing/cancel');
  Future<void> resume() => _api.post('/billing/resume');
}

final billingApiProvider = Provider<BillingApi>((ref) => BillingApi(ref.watch(apiClientProvider)));
final billingOverviewProvider = FutureProvider.autoDispose<BillingOverview>((ref) => ref.watch(billingApiProvider).overview());
final plansProvider = FutureProvider.autoDispose<List<PlanInfo>>((ref) => ref.watch(billingApiProvider).plans());
