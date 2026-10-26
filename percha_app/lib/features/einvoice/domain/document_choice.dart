import '../domain/customer_rules.dart';

/// Comprobante elegido para la venta en curso.
class DocumentChoice {
  const DocumentChoice({this.factura = false, this.type = DocType.none, this.number = '', this.name = '', this.address = ''});
  final bool factura;
  final DocType type;
  final String number;
  final String name;
  final String address;

  String get summary => factura
      ? 'Factura · ${name.isEmpty ? 'sin RUC' : name}'
      : type == DocType.none
          ? 'Boleta · Clientes varios'
          : 'Boleta · ${name.isEmpty ? number : name}';

  Map<String, Object?> toJson() => {
        'type': factura ? 'factura' : 'boleta',
        'customer': {
          'docType': factura ? 'ruc' : type.name,
          if (number.isNotEmpty) 'docNumber': number,
          if (name.isNotEmpty) 'name': name,
          if (address.isNotEmpty) 'address': address,
        },
      };
}
