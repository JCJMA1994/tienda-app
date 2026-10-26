import '../../../core/ids.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/application/session_controller.dart';

class Supplier {
  const Supplier({required this.id, required this.name, this.ruc, this.contactName, this.phone, this.email, required this.active});
  final String id;
  final String name;
  final String? ruc;
  final String? contactName;
  final String? phone;
  final String? email;
  final bool active;

  factory Supplier.fromJson(Map<String, dynamic> j) => Supplier(
        id: j['id'] as String,
        name: j['name'] as String,
        ruc: j['ruc'] as String?,
        contactName: j['contactName'] as String?,
        phone: j['phone'] as String?,
        email: j['email'] as String?,
        active: j['active'] as bool,
      );
}

enum PoStatus {
  draft('Borrador'),
  ordered('Pedida'),
  partial('Recepción parcial'),
  received('Recibida'),
  cancelled('Cancelada');

  const PoStatus(this.label);
  final String label;

  static PoStatus parse(String v) => PoStatus.values.firstWhere((s) => s.name == v);
  bool get receivable => this == ordered || this == partial;
}

class PoSummary {
  const PoSummary({required this.id, required this.number, required this.status, required this.supplierName, required this.totalCents, required this.createdAt, this.expectedAt});
  final String id;
  final int number;
  final PoStatus status;
  final String supplierName;
  final int totalCents;
  final DateTime createdAt;
  final DateTime? expectedAt;

  factory PoSummary.fromJson(Map<String, dynamic> j) => PoSummary(
        id: j['id'] as String,
        number: j['number'] as int,
        status: PoStatus.parse(j['status'] as String),
        supplierName: j['supplierName'] as String,
        totalCents: j['totalCents'] as int,
        createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
        expectedAt: j['expectedAt'] == null ? null : DateTime.parse(j['expectedAt'] as String),
      );
}

class PoLine {
  const PoLine({
    required this.id,
    required this.variantId,
    required this.productName,
    required this.sku,
    required this.options,
    required this.ordered,
    required this.received,
    required this.unitCostCents,
  });

  final String id;
  final String variantId;
  final String productName;
  final String sku;
  final Map<String, String> options;
  final int ordered;
  final int received;
  final int unitCostCents;

  int get pending => ordered - received;
  String get optionsLabel => options.values.join(' · ');

  factory PoLine.fromJson(Map<String, dynamic> j) => PoLine(
        id: j['id'] as String,
        variantId: j['variantId'] as String,
        productName: j['productName'] as String,
        sku: j['sku'] as String,
        options: (j['options'] as Map<String, dynamic>).cast<String, String>(),
        ordered: j['quantityOrdered'] as int,
        received: j['quantityReceived'] as int,
        unitCostCents: j['unitCostCents'] as int,
      );
}

class PurchaseOrder {
  const PurchaseOrder({
    required this.id,
    required this.number,
    required this.status,
    required this.supplierId,
    required this.branchId,
    required this.totalCents,
    required this.lines,
    this.expectedAt,
    this.notes,
  });

  final String id;
  final int number;
  final PoStatus status;
  final String supplierId;
  final String branchId;
  final int totalCents;
  final List<PoLine> lines;
  final DateTime? expectedAt;
  final String? notes;

  int get unitsOrdered => lines.fold(0, (a, l) => a + l.ordered);
  int get unitsReceived => lines.fold(0, (a, l) => a + l.received);

  factory PurchaseOrder.fromJson(Map<String, dynamic> j) => PurchaseOrder(
        id: j['id'] as String,
        number: j['number'] as int,
        status: PoStatus.parse(j['status'] as String),
        supplierId: j['supplierId'] as String,
        branchId: j['branchId'] as String,
        totalCents: j['totalCents'] as int,
        expectedAt: j['expectedAt'] == null ? null : DateTime.parse(j['expectedAt'] as String),
        notes: j['notes'] as String?,
        lines: (j['items'] as List<dynamic>).cast<Map<String, dynamic>>().map(PoLine.fromJson).toList(),
      );
}

class Receipt {
  const Receipt({required this.number, required this.createdAt, required this.units});
  final int number;
  final DateTime createdAt;
  final int units;

  factory Receipt.fromJson(Map<String, dynamic> j) => Receipt(
        number: j['number'] as int,
        createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
        units: (j['items'] as List<dynamic>).cast<Map<String, dynamic>>().fold(0, (a, i) => a + (i['quantity'] as int)),
      );
}

typedef PoItemInput = ({String variantId, int quantity, int unitCostCents});

String _date(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class PurchasingApi {
  const PurchasingApi(this._api);
  final ApiClient _api;

  Future<List<Supplier>> suppliers() async =>
      (await _api.get('/suppliers') as List<dynamic>).cast<Map<String, dynamic>>().map(Supplier.fromJson).toList();

  Future<Supplier> saveSupplier({String? id, required Map<String, Object?> data}) async {
    final res = id == null ? await _api.post('/suppliers', body: data) : await _api.patch('/suppliers/$id', body: data);
    return Supplier.fromJson(res as Map<String, dynamic>);
  }

  Future<List<PoSummary>> orders({PoStatus? status}) async =>
      (await _api.get('/purchase-orders', query: {'status': status?.name}) as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(PoSummary.fromJson)
          .toList();

  Future<PurchaseOrder> order(String id) async => PurchaseOrder.fromJson(await _api.get('/purchase-orders/$id') as Map<String, dynamic>);

  Map<String, Object?> _body({String? supplierId, DateTime? expectedAt, String? notes, List<PoItemInput>? items}) => {
        if (supplierId != null) 'supplierId': supplierId,
        if (expectedAt != null) 'expectedAt': _date(expectedAt),
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        if (items != null) 'items': [for (final i in items) {'variantId': i.variantId, 'quantity': i.quantity, 'unitCostCents': i.unitCostCents}],
      };

  Future<PurchaseOrder> create({
    required String supplierId,
    required String branchId,
    DateTime? expectedAt,
    String? notes,
    required List<PoItemInput> items,
  }) async =>
      PurchaseOrder.fromJson(await _api.post('/purchase-orders', body: {
        'branchId': branchId,
        ..._body(supplierId: supplierId, expectedAt: expectedAt, notes: notes, items: items),
      }) as Map<String, dynamic>);

  Future<PurchaseOrder> update(String id, {String? supplierId, DateTime? expectedAt, String? notes, List<PoItemInput>? items}) async =>
      PurchaseOrder.fromJson(
        await _api.patch('/purchase-orders/$id', body: _body(supplierId: supplierId, expectedAt: expectedAt, notes: notes, items: items))
            as Map<String, dynamic>,
      );

  Future<void> confirm(String id) => _api.post('/purchase-orders/$id/confirm');
  Future<void> cancel(String id) => _api.post('/purchase-orders/$id/cancel');

  /// Devuelve el estado de la orden y, si se adjuntó factura, cómo quedó su validación en SUNAT
  /// (valid · unverified). Una factura anulada o inexistente hace fallar la recepción (422).
  Future<({String status, String? invoiceStatus})> receive(
    String id,
    List<({String itemId, int quantity, int? unitCostCents})> items, {
    String? notes,
    SupplierInvoice? invoice,
  }) async {
    final res = await _api.post('/purchase-orders/$id/receipts', idempotencyKey: newUuid(), body: {
      'items': [
        for (final i in items) {'purchaseOrderItemId': i.itemId, 'quantity': i.quantity, if (i.unitCostCents != null) 'unitCostCents': i.unitCostCents},
      ],
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      if (invoice != null) 'supplierInvoice': invoice.toJson(),
    }) as Map<String, dynamic>;
    return (status: res['status'] as String, invoiceStatus: (res['invoice'] as Map<String, dynamic>?)?['status'] as String?);
  }

  Future<List<Receipt>> receipts(String id) async =>
      (await _api.get('/purchase-orders/$id/receipts') as List<dynamic>).cast<Map<String, dynamic>>().map(Receipt.fromJson).toList();
}

final purchasingApiProvider = Provider<PurchasingApi>((ref) => PurchasingApi(ref.watch(apiClientProvider)));
final suppliersProvider = FutureProvider.autoDispose<List<Supplier>>((ref) => ref.watch(purchasingApiProvider).suppliers());
final poDetailProvider = FutureProvider.autoDispose.family<PurchaseOrder, String>((ref, id) => ref.watch(purchasingApiProvider).order(id));
final poReceiptsProvider = FutureProvider.autoDispose.family<List<Receipt>, String>((ref, id) => ref.watch(purchasingApiProvider).receipts(id));

/// Factura del proveedor que respalda una recepción (se valida en SUNAT al registrar).
class SupplierInvoice {
  const SupplierInvoice({required this.serie, required this.numero, required this.date, this.totalCents});
  final String serie;
  final int numero;
  final DateTime date;
  final int? totalCents;

  String get label => '$serie-$numero';

  Map<String, Object?> toJson() => {
        'type': serie.startsWith('B') ? '03' : '01',
        'serie': serie,
        'numero': numero,
        'date': '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
        if (totalCents != null) 'totalCents': totalCents,
      };
}
