import 'package:flutter/material.dart';

import '../../features/auth/data/auth_models.dart';

/// Arquitectura de navegación (una sola fuente para barra inferior, riel y menú "Más").
///
/// Criterios:
/// - **Máximo 5 destinos** en la barra (guía de Material 3): lo diario va abajo; lo
///   ocasional, en "Más", agrupado por tarea.
/// - **Por rol**: cada destino declara el permiso que necesita. Un vendedor ve Vender y
///   Ventas; un almacenero ve Productos y Movimientos. Nadie ve pestañas vacías.
/// - **"Vender" es la acción principal** de una boutique: va segunda, con ícono relleno.
class NavDest {
  const NavDest(this.path, this.icon, this.selectedIcon, this.label, {this.permission, this.adminOnly = false});
  final String path;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String? permission;
  final bool adminOnly;

  bool allowed(Me me) => (permission == null || me.can(permission!)) && (!adminOnly || me.isPlatformAdmin);
}

const primaryDestinations = [
  NavDest('/home', Icons.home_outlined, Icons.home, 'Inicio'),
  NavDest('/pos', Icons.point_of_sale_outlined, Icons.point_of_sale, 'Vender', permission: 'sales.create'),
  NavDest('/products', Icons.checkroom_outlined, Icons.checkroom, 'Productos', permission: 'catalog.read'),
  NavDest('/sales', Icons.receipt_long_outlined, Icons.receipt_long, 'Ventas', permission: 'sales.read'),
  NavDest('/transfers', Icons.swap_horiz, Icons.swap_horiz, 'Movimientos', permission: 'inventory.adjust'),
  NavDest('/more', Icons.menu, Icons.menu, 'Más'),
];

/// Destinos visibles para este usuario (siempre ≤ 5 y con "Más" al final).
List<NavDest> destinationsFor(Me me) {
  final allowed = primaryDestinations.where((d) => d.path != '/more' && d.allowed(me)).toList();
  return [...allowed.take(4), primaryDestinations.last];
}

class MoreSection {
  const MoreSection(this.title, this.items);
  final String title;
  final List<NavDest> items;
}

/// Lo que no está en la barra, agrupado por tarea (no por módulo técnico).
const moreSections = [
  MoreSection('Operación', [
    NavDest('/customers', Icons.people_outline, Icons.people, 'Clientes', permission: 'customers.read'),
    NavDest('/layaways', Icons.bookmark_border, Icons.bookmark, 'Apartados', permission: 'sales.read'),
    NavDest('/stock-counts', Icons.fact_check_outlined, Icons.fact_check, 'Conteo de inventario', permission: 'inventory.adjust'),
    NavDest('/cash-sessions', Icons.point_of_sale_outlined, Icons.point_of_sale, 'Cierres de caja', permission: 'cash.manage'),
    NavDest('/catalog/orders', Icons.shopping_basket_outlined, Icons.shopping_basket, 'Pedidos del catálogo', permission: 'sales.read'),
    NavDest('/purchases', Icons.local_shipping_outlined, Icons.local_shipping, 'Compras y recepción', permission: 'purchasing.read'),
    NavDest('/transfers', Icons.swap_horiz, Icons.swap_horiz, 'Transferencias entre sucursales', permission: 'inventory.read'),
    NavDest('/reports', Icons.insights_outlined, Icons.insights, 'Reportes', permission: 'reports.read'),
    NavDest('/reports/commissions', Icons.percent, Icons.percent, 'Comisiones', permission: 'reports.read'),
  ]),
  MoreSection('Equipo', [
    NavDest('/team', Icons.group_outlined, Icons.group, 'Equipo, roles y mi PIN'),
  ]),
  MoreSection('Configuración', [
    NavDest('/settings/einvoice', Icons.description_outlined, Icons.description, 'Comprobantes electrónicos', permission: 'settings.manage'),
    NavDest('/settings/whatsapp', Icons.chat_outlined, Icons.chat, 'WhatsApp de la tienda', permission: 'settings.manage'),
    NavDest('/onboarding/business', Icons.storefront_outlined, Icons.storefront, 'Datos del negocio', permission: 'settings.manage'),
    NavDest('/promotions', Icons.local_offer_outlined, Icons.local_offer, 'Promociones', permission: 'catalog.write'),
    NavDest('/settings/catalog', Icons.storefront, Icons.storefront, 'Catálogo en línea', permission: 'settings.manage'),
    NavDest('/settings/branches', Icons.store_mall_directory_outlined, Icons.store_mall_directory, 'Sucursales', permission: 'settings.manage'),
    NavDest('/settings/printing', Icons.print_outlined, Icons.print, 'Impresora y etiquetas'),
    NavDest('/billing', Icons.workspace_premium_outlined, Icons.workspace_premium, 'Plan y facturación'),
  ]),
  MoreSection('Plataforma', [
    NavDest('/admin', Icons.admin_panel_settings_outlined, Icons.admin_panel_settings, 'Backoffice de Percha', adminOnly: true),
  ]),
];
