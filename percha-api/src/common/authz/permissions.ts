/**
 * Permisos granulares. Los endpoints piden PERMISOS, nunca roles:
 * así mañana se pueden crear roles personalizados sin tocar los controladores.
 */
export const PERMISSIONS = [
  'settings.manage',
  'billing.manage',
  'team.manage',
  'catalog.read',
  'catalog.write',
  'costs.read',
  'inventory.read',
  'inventory.adjust',
  'cash.manage',
  'sales.create',
  'sales.read',
  'sales.discount_over_limit',
  'sales.void',
  'sales.return',
  'purchasing.read',
  'purchasing.write',
  'purchasing.receive',
  'reports.read',
  'customers.read',
  'customers.write',
] as const;

export type Permission = (typeof PERMISSIONS)[number];
export type Role = 'owner' | 'manager' | 'seller' | 'stock';

const ALL = new Set<Permission>(PERMISSIONS);
const without = (...p: Permission[]) => new Set([...ALL].filter((x) => !p.includes(x)));

/**
 * Matriz rol → permisos (la misma que se ve en la pantalla "Equipo" del mockup).
 * "Con aprobación" no es un permiso: el vendedor NO tiene sales.void, pero puede anular
 * si un encargado ingresa su PIN (ver ApprovalService).
 */
export const ROLE_PERMISSIONS: Record<Role, ReadonlySet<Permission>> = {
  owner: ALL,
  manager: without('billing.manage'),
  seller: new Set<Permission>([
    'catalog.read',
    'inventory.read',
    'cash.manage',
    'sales.create',
    'sales.read',
    'sales.return',
    'customers.read',
    'customers.write',
  ]),
  stock: new Set<Permission>([
    'catalog.read',
    'inventory.read',
    'inventory.adjust',
    'purchasing.read',
    'purchasing.receive',
  ]),
};

export function hasPermission(role: Role, permission: Permission): boolean {
  return ROLE_PERMISSIONS[role].has(permission);
}

/** Roles que cada rol puede asignar al gestionar su equipo. */
export const ASSIGNABLE_ROLES: Record<Role, Role[]> = {
  owner: ['owner', 'manager', 'seller', 'stock'],
  manager: ['seller', 'stock'],
  seller: [],
  stock: [],
};

/**
 * Permisos que un rol sin ellos puede ejercer si un supervisor ingresa su PIN
 * (ver ApprovalService). Solo aplica a quien ya puede vender.
 */
export const APPROVABLE: readonly Permission[] = ['sales.discount_over_limit', 'sales.void'];

/** Permisos que un rol ejerce solo dentro de su sucursal si tiene una asignada. */
export const BRANCH_SCOPED: Partial<Record<Role, Permission[]>> = { manager: ['team.manage'] };

export const ROLE_LABELS: Record<Role, string> = {
  owner: 'Dueño',
  manager: 'Encargado',
  seller: 'Vendedor',
  stock: 'Almacén',
};

/** Etiquetas y grupos para mostrar la matriz en la app (orden = orden de visualización). */
export const PERMISSION_INFO: Record<Permission, { label: string; group: string }> = {
  'sales.create': { label: 'Vender en POS', group: 'Ventas' },
  'sales.read': { label: 'Ver ventas', group: 'Ventas' },
  'sales.discount_over_limit': { label: 'Descuentos sobre el límite', group: 'Ventas' },
  'sales.void': { label: 'Anular ventas', group: 'Ventas' },
  'sales.return': { label: 'Devoluciones y cambios', group: 'Ventas' },
  'cash.manage': { label: 'Abrir y cerrar caja', group: 'Ventas' },
  'catalog.read': { label: 'Ver catálogo', group: 'Catálogo e inventario' },
  'catalog.write': { label: 'Editar catálogo', group: 'Catálogo e inventario' },
  'costs.read': { label: 'Ver costos y márgenes', group: 'Catálogo e inventario' },
  'inventory.read': { label: 'Ver stock', group: 'Catálogo e inventario' },
  'inventory.adjust': { label: 'Ajustar stock', group: 'Catálogo e inventario' },
  'purchasing.read': { label: 'Ver compras', group: 'Compras' },
  'purchasing.write': { label: 'Crear órdenes de compra', group: 'Compras' },
  'purchasing.receive': { label: 'Recibir mercadería', group: 'Compras' },
  'customers.read': { label: 'Ver clientes', group: 'Clientes' },
  'customers.write': { label: 'Registrar y editar clientes', group: 'Clientes' },
  'team.manage': { label: 'Gestionar equipo', group: 'Administración' },
  'settings.manage': { label: 'Configurar la tienda', group: 'Administración' },
  'billing.manage': { label: 'Plan y facturación', group: 'Administración' },
  'reports.read': { label: 'Ver reportes', group: 'Administración' },
};
