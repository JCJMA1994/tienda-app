import 'package:flutter_test/flutter_test.dart';
import 'package:percha_app/features/einvoice/domain/customer_rules.dart';

void main() {
  test('RUC con dígito verificador (mismo caso que la API)', () {
    expect(isValidRuc('20131312955'), isTrue);
    expect(isValidRuc('20131312956'), isFalse);
    expect(isValidRuc('30131312955'), isFalse);
  });

  test('boleta anónima solo hasta el tope; factura exige RUC y razón social', () {
    String? v({bool factura = false, int total = 10000, DocType type = DocType.none, String number = '', String name = ''}) =>
        validateCustomer(factura: factura, totalCents: total, anonLimitCents: 70000, type: type, number: number, name: name);
    expect(v(), isNull);
    expect(v(total: 80000), contains('700'));
    expect(v(total: 80000, type: DocType.dni, number: '45678912', name: 'Lucía'), isNull);
    expect(v(factura: true, type: DocType.ruc, number: '20131312955'), contains('razón social'));
    expect(v(factura: true, type: DocType.ruc, number: '20131312955', name: 'Empresa SAC'), isNull);
  });
}
