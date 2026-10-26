import 'package:flutter_test/flutter_test.dart';
import 'package:percha_app/features/pos/application/cart.dart';
import 'package:percha_app/features/pos/data/pos_models.dart';

SellableVariant variant(String id, {int price = 18990, int? stock = 5, bool sellable = true}) => SellableVariant(
      id: id,
      sku: 'VST-014-$id',
      productName: 'Vestido midi',
      options: const {'Talla': 'M', 'Color': 'Negro'},
      priceCents: price,
      sellable: sellable,
      stock: stock,
    );

void main() {
  group('Cart', () {
    test('agregar dos veces la misma variante incrementa la cantidad', () {
      var cart = const Cart();
      AddResult r;
      (cart, r) = cart.add(variant('a'));
      expect(r, AddResult.added);
      (cart, r) = cart.add(variant('a'));
      expect(r, AddResult.incremented);
      expect(cart.lines.single.quantity, 2);
      expect(cart.subtotalCents, 37980);
    });

    test('no deja agregar más que el stock conocido', () {
      var cart = const Cart();
      (cart, _) = cart.add(variant('a', stock: 1));
      final (same, r) = cart.add(variant('a', stock: 1));
      expect(r, AddResult.outOfStock);
      expect(same.units, 1);
    });

    test('rechaza variantes que no están a la venta', () {
      final (cart, r) = const Cart().add(variant('a', sellable: false));
      expect(r, AddResult.notSellable);
      expect(cart.isEmpty, isTrue);
    });

    test('IGV incluido: mismo cálculo que la API (37980 -> 5794)', () {
      var cart = const Cart();
      (cart, _) = cart.add(variant('a'));
      (cart, _) = cart.add(variant('a'));
      final t = cart.totals(taxRateBp: 1800, pricesIncludeTax: true);
      expect(t.total, 37980);
      expect(t.tax, 5794);
    });

    test('precios sin IGV: el impuesto se suma', () {
      var cart = const Cart();
      (cart, _) = cart.add(variant('a', price: 10000));
      final t = cart.totals(taxRateBp: 1800, pricesIncludeTax: false);
      expect(t, (total: 11800, tax: 1800));
    });

    test('el descuento nunca supera el subtotal y detecta cuándo pide aprobación', () {
      var cart = const Cart();
      (cart, _) = cart.add(variant('a'));
      cart = cart.withDiscount(1899);
      expect(cart.needsDiscountApproval(1000), isFalse); // 10% exacto: no requiere
      cart = cart.withDiscount(5000);
      expect(cart.needsDiscountApproval(1000), isTrue);
      cart = cart.withDiscount(999999);
      expect(cart.effectiveDiscountCents, 18990);
    });

    test('cantidad 0 quita la línea', () {
      var cart = const Cart();
      (cart, _) = cart.add(variant('a'));
      cart = cart.setQuantity('a', 0);
      expect(cart.isEmpty, isTrue);
    });
  });
}
