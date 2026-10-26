/// Modelos de comprobantes (sin dependencias de red ni de Riverpod).
class EDocument {
  const EDocument({
    required this.id,
    required this.kind,
    required this.serie,
    required this.numero,
    required this.status,
    required this.totalCents,
    this.customerName,
    this.pdfUrl,
    this.sunatDescription,
    this.lastError,
    this.saleId,
    this.hash,
    this.qr,
    this.customerDocType,
    this.customerDocNumber,
  });

  final String id;
  final String kind; // boleta · factura · nota_credito
  final String serie;
  final int numero;
  final String status; // pending · accepted · rejected · error
  final int totalCents;
  final String? customerName;
  final String? pdfUrl;
  final String? sunatDescription;
  final String? lastError;
  final String? saleId;

  /// Para la representación impresa: resumen (hash) y cadena del QR que pide SUNAT.
  final String? hash;
  final String? qr;
  final String? customerDocType;
  final String? customerDocNumber;

  String get code => '$serie-$numero';
  String get kindLabel => switch (kind) { 'factura' => 'Factura', 'nota_credito' => 'Nota de crédito', 'guia_remitente' => 'Guía de remisión', _ => 'Boleta' };
  String get statusLabel => switch (status) { 'accepted' => 'Aceptado', 'rejected' => 'Rechazado', 'error' => 'Sin enviar', _ => 'En proceso' };
  bool get canRetry => status == 'error' || status == 'pending';

  factory EDocument.fromJson(Map<String, dynamic> j) => EDocument(
        id: j['id'] as String,
        kind: j['kind'] as String,
        serie: j['serie'] as String,
        numero: (j['numero'] as num).toInt(),
        status: j['status'] as String,
        totalCents: (j['totalCents'] as num).toInt(),
        customerName: j['customerName'] as String?,
        pdfUrl: j['pdfUrl'] as String?,
        sunatDescription: j['sunatDescription'] as String?,
        lastError: j['lastError'] as String?,
        saleId: j['saleId'] as String?,
        hash: j['hash'] as String?,
        qr: j['qr'] as String?,
        customerDocType: j['customerDocType'] as String?,
        customerDocNumber: j['customerDocNumber'] as String?,
      );
}

class EInvoiceStatus {
  const EInvoiceStatus({required this.enabled, required this.anonLimitCents});
  final bool enabled;
  final int anonLimitCents;
}
