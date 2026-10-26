/// Catálogos de etiquetas que se muestran en varias pantallas. Un solo lugar: si mañana
/// "Yape / Plin" pasa a "Billetera", se cambia aquí.
abstract final class Labels {
  static const paymentMethods = {
    'cash': 'Efectivo',
    'card': 'Tarjeta',
    'wallet': 'Yape / Plin',
    'transfer': 'Transferencia',
    'store_credit': 'Vale',
    'layaway': 'Abonos del apartado',
  };

  /// Medios con los que se cobra dinero (abonos, gift cards, saldo de un vale).
  static const moneyMethods = {'cash': 'Efectivo', 'card': 'Tarjeta', 'wallet': 'Yape / Plin', 'transfer': 'Transferencia'};

  static String paymentMethod(String code) => paymentMethods[code] ?? code;
}
