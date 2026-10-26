import 'package:flutter_test/flutter_test.dart';
import 'package:percha_app/core/navigation/nav.dart';
import 'package:percha_app/features/auth/data/auth_models.dart';

Me me(String role, Set<String> permissions) => Me(
      userId: 'u',
      tenantId: 't',
      membershipId: 'm',
      role: role,
      branchId: null,
      name: 'Ana',
      email: 'a@a.pe',
      tenantName: 'Alma',
      permissions: permissions,
    );

void main() {
  const owner = {'sales.create', 'sales.read', 'catalog.read', 'inventory.read', 'inventory.adjust', 'reports.read', 'settings.manage', 'purchasing.read'};

  test('la barra nunca tiene más de 5 destinos y siempre termina en "Más"', () {
    final d = destinationsFor(me('owner', owner));
    expect(d.length, lessThanOrEqualTo(5));
    expect(d.map((x) => x.label), ['Inicio', 'Vender', 'Productos', 'Ventas', 'Más']);
  });

  test('cada rol ve solo lo suyo', () {
    final seller = destinationsFor(me('seller', {'sales.create', 'sales.read', 'catalog.read', 'inventory.read'}));
    expect(seller.map((x) => x.label), ['Inicio', 'Vender', 'Productos', 'Ventas', 'Más']);
    final stock = destinationsFor(me('stock', {'catalog.read', 'inventory.read', 'inventory.adjust', 'purchasing.read'}));
    expect(stock.map((x) => x.label), ['Inicio', 'Productos', 'Movimientos', 'Más']);
  });

  test('"Más" oculta secciones sin permisos y el backoffice a quien no es superadmin', () {
    final seller = me('seller', {'sales.create'});
    final visible = [for (final s in moreSections) ...s.items.where((d) => d.allowed(seller))].map((d) => d.label);
    expect(visible, containsAll(['Equipo, roles y mi PIN', 'Plan y facturación']));
    expect(visible, isNot(contains('Reportes')));
    expect(visible, isNot(contains('Backoffice de Percha')));
  });
}
