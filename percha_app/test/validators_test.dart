import 'package:flutter_test/flutter_test.dart';
import 'package:percha_app/core/forms/formatters.dart';
import 'package:percha_app/core/forms/validators.dart';

void main() {
  test('correo y contraseña', () {
    expect(V.email()('ana@tienda.pe'), isNull);
    expect(V.email()('ana@tienda'), isNotNull);
    expect(V.password()('corta1'), 'Mínimo 8 caracteres');
    expect(V.password()('solamenteletras'), 'Usa letras y números');
    expect(V.password()('clave-segura-1'), isNull);
  });

  test('documentos peruanos', () {
    expect(V.dni()('45678912'), isNull);
    expect(V.dni()('4567891'), isNotNull);
    expect(V.ruc()('20131312955'), isNull);
    expect(V.ruc()('20131312956'), contains('revisa'));
    expect(V.ruc(optional: true)(''), isNull);
    expect(V.phone()('987654321'), isNull);
    expect(V.phone()('087654321'), isNotNull);
  });

  test('montos, cantidades, URL y series', () {
    expect(V.money()('189.90'), isNull);
    expect(V.money(positive: true)('0'), 'Debe ser mayor a 0');
    expect(V.money(optional: true)(''), isNull);
    expect(V.intRange(min: 1, max: 10)('11'), 'Máximo 10');
    expect(V.url()('https://api.nubefact.com/api/v1/x'), isNull);
    expect(V.url()('api.nubefact.com'), isNotNull);
    expect(V.serie('B')('b001'), isNull);
    expect(V.serie('F')('B001'), isNotNull);
    expect(V.all([V.required(), V.minLength(3)])('ab'), 'Mínimo 3 caracteres');
  });

  test('el formateador de montos no deja escribir texto inválido', () {
    TextEditingValue apply(String old, String next) =>
        F.money.formatEditUpdate(TextEditingValue(text: old), TextEditingValue(text: next));
    expect(apply('18', '189').text, '189');
    expect(apply('189.9', '189.90').text, '189.90');
    expect(apply('189.90', '189.901').text, '189.90');
    expect(apply('189', '189a').text, '189');
    expect(apply('1.5', '1.5.').text, '1.5');
  });
}
