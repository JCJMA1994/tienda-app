/// Reglas del cobro en el POS (lógica pura, probada): cómo se reparte el total entre un vale y
/// el otro medio de pago, y cuánto vuelto corresponde. La pantalla solo pregunta y muestra.
typedef CreditUse = ({String code, int amountCents});

class PaymentLine {
  const PaymentLine(this.method, this.amountCents, {this.creditCode});
  final String method;
  final int amountCents;
  final String? creditCode;

  Map<String, Object?> toJson() => {'method': method, 'amountCents': amountCents, if (creditCode != null) 'creditCode': creditCode};
}

/// Lo que se paga con el vale nunca supera el total; el resto va al otro medio.
List<PaymentLine> splitPayments({required int totalCents, required String method, CreditUse? credit}) {
  final fromCredit = credit == null ? 0 : (credit.amountCents < totalCents ? credit.amountCents : totalCents);
  final rest = totalCents - fromCredit;
  return [
    if (credit != null && fromCredit > 0) PaymentLine('store_credit', fromCredit, creditCode: credit.code),
    if (rest > 0) PaymentLine(method, rest),
  ];
}

/// Efectivo a cobrar (solo la parte en efectivo).
int cashDue(List<PaymentLine> payments) => payments.where((p) => p.method == 'cash').fold(0, (a, p) => a + p.amountCents);

/// Vuelto: null si lo recibido no alcanza.
int? changeFor({required int cashReceivedCents, required int cashDueCents}) => cashReceivedCents < cashDueCents ? null : cashReceivedCents - cashDueCents;

/// Billetes sugeridos para "¿con cuánto paga?": exacto y los siguientes de S/ 50, 100 y 200.
List<int> cashSuggestions(int dueCents) {
  final s = <int>{dueCents, for (final b in const [5000, 10000, 20000]) if (b > dueCents) b, (dueCents / 10000).ceil() * 10000}.toList()..sort();
  return s.take(4).toList();
}
