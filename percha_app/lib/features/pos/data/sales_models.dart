import '../../einvoice/data/einvoice_models.dart';

/// Modelos de ventas (sin dependencias de red ni de Riverpod: los usan el ticket y las pruebas).
class SaleSummary {
  const SaleSummary({required this.id, required this.number, required this.totalCents, required this.voided, required this.createdAt});
  final String id;
  final int number;
  final int totalCents;
  final bool voided;
  final DateTime createdAt;

  factory SaleSummary.fromJson(Map<String, dynamic> j) => SaleSummary(
        id: j['id'] as String,
        number: j['number'] as int,
        totalCents: j['totalCents'] as int,
        voided: j['status'] == 'voided',
        createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
      );
}

class SaleLine {
  const SaleLine({
    required this.id,
    required this.variantId,
    required this.productName,
    required this.sku,
    required this.options,
    required this.quantity,
    required this.returnedQuantity,
    required this.unitPriceCents,
    required this.lineTotalCents,
  });

  final String id;
  final String variantId;
  final String productName;
  final String sku;
  final Map<String, String> options;
  final int quantity;
  final int returnedQuantity;
  final int unitPriceCents;

  /// Total de la línea con su parte del descuento (lo que realmente se pagó).
  final int lineTotalCents;

  int get returnable => quantity - returnedQuantity;
  String get optionsLabel => options.values.join(' · ');

  factory SaleLine.fromJson(Map<String, dynamic> j) => SaleLine(
        id: j['id'] as String,
        variantId: j['variantId'] as String,
        productName: j['productName'] as String,
        sku: j['sku'] as String,
        options: (j['options'] as Map<String, dynamic>).cast<String, String>(),
        quantity: j['quantity'] as int,
        returnedQuantity: j['returnedQuantity'] as int,
        unitPriceCents: j['unitPriceCents'] as int,
        lineTotalCents: j['lineTotalCents'] as int,
      );
}

class SalePayment {
  const SalePayment({required this.method, required this.amountCents});
  final String method;
  final int amountCents;
}

class SaleDetail {
  const SaleDetail({
    required this.id,
    required this.number,
    required this.branchId,
    required this.voided,
    required this.subtotalCents,
    required this.discountCents,
    required this.totalCents,
    required this.taxCents,
    required this.createdAt,
    required this.lines,
    required this.payments,
    this.voidReason,
    this.documents = const [],
    this.customer,
    this.store = const TicketStore(name: ''),
  });

  final String id;
  final int number;
  final String branchId;
  final bool voided;
  final int subtotalCents;
  final int discountCents;
  final int totalCents;
  final int taxCents;
  final DateTime createdAt;
  final List<SaleLine> lines;
  final List<SalePayment> payments;
  final String? voidReason;

  /// Boleta/factura y notas de crédito de esta venta.
  final List<EDocument> documents;

  /// Cliente de la venta (si se identificó) y datos de la tienda para imprimir el ticket.
  final ({String id, String name})? customer;
  final TicketStore store;

  bool get hasReturns => lines.any((l) => l.returnedQuantity > 0);
  bool get fullyReturned => lines.every((l) => l.returnable == 0);

  factory SaleDetail.fromJson(Map<String, dynamic> j) => SaleDetail(
        id: j['id'] as String,
        number: j['number'] as int,
        branchId: j['branchId'] as String,
        voided: j['status'] == 'voided',
        subtotalCents: j['subtotalCents'] as int,
        discountCents: j['discountCents'] as int,
        totalCents: j['totalCents'] as int,
        taxCents: j['taxCents'] as int,
        createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
        voidReason: j['voidReason'] as String?,
        documents: ((j['documents'] as List<dynamic>?) ?? const []).cast<Map<String, dynamic>>().map(EDocument.fromJson).toList(),
        customer: j['customer'] == null ? null : (id: j['customer']['id'] as String, name: j['customer']['name'] as String),
        store: j['store'] == null ? const TicketStore(name: '') : TicketStore.fromJson(j['store'] as Map<String, dynamic>),
        lines: (j['items'] as List<dynamic>).cast<Map<String, dynamic>>().map(SaleLine.fromJson).toList(),
        payments: (j['payments'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map((p) => SalePayment(method: p['method'] as String, amountCents: p['amountCents'] as int))
            .toList(),
      );
}

class ReturnResult {
  const ReturnResult({required this.number, required this.kind, required this.differenceCents, this.creditCode, this.creditExpiresAt});

  /// Si se reembolsó como saldo a favor: el código del vale (se muestra una vez).
  final String? creditCode;
  final DateTime? creditExpiresAt;
  final int number;
  final String kind;
  final int differenceCents;
}

/// Datos de la tienda que van en el encabezado del ticket.
class TicketStore {
  const TicketStore({required this.name, this.legalName, this.ruc, this.fiscalAddress, this.branchName, this.branchAddress});
  final String name;
  final String? legalName;
  final String? ruc;
  final String? fiscalAddress;
  final String? branchName;
  final String? branchAddress;

  factory TicketStore.fromJson(Map<String, dynamic> j) => TicketStore(
        name: j['name'] as String? ?? '',
        legalName: j['legalName'] as String?,
        ruc: j['ruc'] as String?,
        fiscalAddress: j['fiscalAddress'] as String?,
        branchName: j['branchName'] as String?,
        branchAddress: j['branchAddress'] as String?,
      );
}
