import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'labels.dart';
import 'ticket.dart';

/// Ticket para impresora térmica de rollo (58 u 80 mm). El alto se ajusta al contenido.
Future<Uint8List> ticketPdf(TicketModel t, {required int paperMm}) async {
  final doc = pw.Document(title: t.title.replaceAll('\n', ' '));
  final width = paperMm * PdfPageFormat.mm;
  final small = pw.TextStyle(fontSize: paperMm >= 80 ? 8.5 : 7.5);
  final normal = pw.TextStyle(fontSize: paperMm >= 80 ? 9.5 : 8.5);
  final bold = normal.copyWith(fontWeight: pw.FontWeight.bold);
  pw.Widget rule() => pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 4), child: pw.Divider(height: 1, thickness: 0.6, borderStyle: pw.BorderStyle.dashed));
  pw.Widget row(String l, String r, {pw.TextStyle? style}) => pw.Row(children: [pw.Expanded(child: pw.Text(l, style: style ?? normal)), pw.Text(r, style: style ?? normal)]);

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat(width, double.infinity, marginAll: 3 * PdfPageFormat.mm),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          for (final (i, h) in t.header.indexed) pw.Text(h, textAlign: pw.TextAlign.center, style: i == 0 ? bold : small),
          rule(),
          pw.Text(t.title, textAlign: pw.TextAlign.center, style: bold),
          pw.SizedBox(height: 3),
          for (final m in t.meta) pw.Text(m, style: small),
          rule(),
          for (final it in t.items) ...[
            row(it.left, it.right),
            if (it.detail != null) pw.Padding(padding: const pw.EdgeInsets.only(left: 8, bottom: 2), child: pw.Text(it.detail!, style: small)),
          ],
          rule(),
          for (final tot in t.totals) row(tot.label, tot.value, style: tot.strong ? bold.copyWith(fontSize: (bold.fontSize ?? 9) + 2) : normal),
          if (t.payments.isNotEmpty) ...[pw.SizedBox(height: 4), for (final p in t.payments) row(p.label, p.value, style: small)],
          if (t.qr != null) ...[
            rule(),
            pw.Center(child: pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: t.qr!, width: 28 * PdfPageFormat.mm, height: 28 * PdfPageFormat.mm)),
          ],
          if (t.hash != null) pw.Text('Resumen: ${t.hash}', textAlign: pw.TextAlign.center, style: small),
          rule(),
          for (final f in t.footer) pw.Text(f, textAlign: pw.TextAlign.center, style: small),
        ],
      ),
    ),
  );
  return doc.save();
}

/// Etiquetas de precio con código de barras.
/// - `roll50x25`: impresora de etiquetas, una etiqueta de 50 × 25 mm por página.
/// - `a4Sheet`: hoja A4 de 3 × 8 etiquetas de 70 × 37 mm (impresora común).
Future<Uint8List> labelsPdf(List<LabelData> labels, {required LabelFormat format}) async {
  final doc = pw.Document(title: 'Etiquetas');
  pw.Widget label(LabelData l, {required double w, required double h}) {
    final code = l.barcodeKind == BarcodeKind.ean13 ? pw.Barcode.ean13(drawEndChar: false) : pw.Barcode.code128();
    return pw.Container(
      width: w,
      height: h,
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(l.name, maxLines: 1, overflow: pw.TextOverflow.clip, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
          pw.Row(children: [
            pw.Expanded(child: pw.Text(l.options, maxLines: 1, style: const pw.TextStyle(fontSize: 6.5))),
            pw.Text(l.price, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          ],),
          pw.SizedBox(height: 1),
          pw.Expanded(child: pw.BarcodeWidget(barcode: code, data: l.barcodeData, drawText: true, textStyle: const pw.TextStyle(fontSize: 6))),
        ],
      ),
    );
  }

  if (format == LabelFormat.roll50x25) {
    final w = 50 * PdfPageFormat.mm, h = 25 * PdfPageFormat.mm;
    for (final l in labels) {
      doc.addPage(pw.Page(pageFormat: PdfPageFormat(w, h), build: (_) => label(l, w: w, h: h)));
    }
  } else {
    final w = 70 * PdfPageFormat.mm, h = 37 * PdfPageFormat.mm;
    const perPage = 24;
    for (var start = 0; start < labels.length; start += perPage) {
      final page = labels.skip(start).take(perPage).toList();
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.copyWith(marginLeft: 0, marginRight: 0, marginTop: 0.5 * PdfPageFormat.cm, marginBottom: 0.5 * PdfPageFormat.cm),
          build: (_) => pw.Wrap(children: [for (final l in page) label(l, w: w, h: h)]),
        ),
      );
    }
  }
  return doc.save();
}
