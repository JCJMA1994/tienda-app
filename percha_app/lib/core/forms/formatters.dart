import 'package:flutter/services.dart';

/// Formateadores de entrada: evitan que el usuario escriba algo inválido (mejor que avisarle después).
abstract final class F {
  static final digits = FilteringTextInputFormatter.digitsOnly;

  static List<TextInputFormatter> digitsMax(int n) => [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(n)];

  static final upper = UpperCaseFormatter();

  /// Montos: solo dígitos y un separador decimal (punto o coma) con máximo 2 decimales.
  static final money = MoneyInputFormatter();
}

class UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}

class MoneyInputFormatter extends TextInputFormatter {
  static final _valid = RegExp(r'^\d{0,7}([.,]\d{0,2})?$');

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      _valid.hasMatch(newValue.text) ? newValue : oldValue;
}
