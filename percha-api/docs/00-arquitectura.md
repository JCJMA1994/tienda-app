# 00 · Arquitectura

## Decisiones principales

| Decisión | Elección | Por qué |
|---|---|---|
| Estilo | Monolito modular | Un equipo pequeño, un deploy. Los módulos tienen fronteras claras y se pueden extraer después si hace falta. |
| Framework | NestJS 11 | Inyección de dependencias, guards y módulos encajan con la separación por dominio. |
| BD | PostgreSQL 16 | Datos muy relacionales (producto → variante → movimiento → venta) y RLS nativo para multi-tenant. |
| ORM | Drizzle | Sin binarios externos, SQL predecible y control explícito de transacciones (clave para RLS). |
| Validación | zod | Un esquema sirve para validar y para tipar el DTO (`z.infer`). |
| Contraseñas/PIN | Argon2id | Recomendación actual de OWASP. |

## Módulos

```
auth        registro, login, refresh, PIN, aceptar invitación
access      permisos, roles, equipo, invitaciones, aprobaciones
store       configuración de la tienda, sucursales, onboarding
catalog     atributos, categorías, productos, variantes, importación
inventory   kardex, stock por sucursal, ajustes, stock mínimo
sales       caja, ventas, anulaciones, devoluciones y cambios
purchasing  proveedores, órdenes de compra, recepciones
audit       bitácora inmutable de acciones sensibles
```

Dependencias permitidas (sin ciclos):

```
catalog ─┐
sales ───┼──▶ inventory ──▶ database
purchasing┘
todos ──▶ access (ApprovalService), audit, database
```

`inventory` no conoce a nadie: es el núcleo y todos lo usan. Así una venta, una compra o un
ajuste mueven el stock por el mismo camino.

## Flujo de un request

```
HTTP ─▶ AuthGuard (JWT) ─▶ PermissionsGuard ─▶ ZodPipe ─▶ Controller ─▶ Service
                                                                          │
                                         DatabaseService.withTenant(tid, tx => …)
                                                                          │
                                   BEGIN; set_config('app.tenant_id', tid, true); …; COMMIT
```

- **Seguro por defecto**: el AuthGuard es global; un endpoint olvidado queda protegido.
  Solo los marcados con `@Public()` se abren.
- **Una operación de negocio = una transacción**. Venta, pagos, kardex y auditoría
  se confirman o se revierten juntos.
- Errores de Postgres se traducen en `AppExceptionFilter`: único → 409, FK → 422,
  RLS → 403, y nunca se filtran detalles internos.

## Convenciones

- Dinero: céntimos enteros (`priceCents`). Porcentajes: puntos básicos (`1800` = 18%).
- IDs: UUID generados por Postgres.
- Fechas: `timestamptz`.
- Correlativos por tienda (ventas, OC, recepciones) con `nextNumber()`; el número no se
  "quema" si la transacción falla.
- Nombres de código en inglés, mensajes y documentación en español.

## Qué NO incluye todavía

Reportes (fase 7), capa SaaS de planes y cobros (fase 8), facturación electrónica,
subida de fotos (hoy se guarda `imageUrl`), envío de correos de invitación (hoy la API
devuelve el token para armar el enlace) y transferencias entre sucursales.
