# 01 · Fundaciones: multi-tenant con RLS

## Objetivo

Que sea **imposible** que una tienda vea o modifique datos de otra, aunque el código tenga un bug.

## Tres roles de base de datos

| Rol | Uso | RLS |
|---|---|---|
| `percha_owner` | Dueño de las tablas, corre migraciones | Lo omite (dueño) |
| `percha_app` | Todo lo de negocio | **Siempre aplicado** |
| `percha_system` | Solo login, registro, refresh e invitaciones | Lo omite (miembro del dueño) |

`percha_system` existe porque el login necesita buscar un correo sin saber aún a qué tienda
pertenece. Su uso está limitado a `AuthService` y `TokenService`.

**Funciona en Neon, Supabase o RDS**: no usa `BYPASSRLS` (que muchos proveedores no dejan
asignar), sino la regla de que el dueño de una tabla omite RLS mientras no se use `FORCE`.

## Cómo se fija la tienda

```ts
db.withTenant(tenantId, async (tx) => { ... })
// BEGIN; SELECT set_config('app.tenant_id', $1, true); ... COMMIT
```

- El tercer parámetro `true` hace la variable **local a la transacción**: al terminar
  desaparece y la conexión vuelve limpia al pool. Sin esto, la siguiente petición en esa
  conexión heredaría la tienda anterior.
- La política usa `app_tenant_id()`, que devuelve `NULL` si la variable no existe:
  sin tienda no se ve ninguna fila (**falla cerrado**).

```sql
CREATE POLICY tenant_isolation ON products
  USING (tenant_id = app_tenant_id())
  WITH CHECK (tenant_id = app_tenant_id());
```

`USING` filtra lecturas; `WITH CHECK` impide insertar o mover filas a otra tienda.

## FK compuestas: el detalle que casi todos olvidan

**Las verificaciones de claves foráneas no pasan por RLS.** Con una FK simple
`product.category_id → categories.id`, la tienda B podría crear un producto apuntando a una
categoría de A si conoce su UUID. Por eso todas las FK internas son compuestas:

```sql
FOREIGN KEY (tenant_id, category_id) REFERENCES categories (tenant_id, id)
```

La prueba *"aísla tiendas: B no ve ni referencia datos de A"* lo verifica (responde 422).

## Otras garantías en la BD

- `users`: `percha_app` solo puede leer `id, email, name` de usuarios de su tienda; nunca el
  hash de contraseña (permiso por columna).
- `refresh_tokens`: sin permisos para `percha_app`.
- `stock_movements` y `audit_logs`: sin UPDATE/DELETE y con trigger que lo bloquea incluso
  para el dueño.
- Índice único parcial: una sola caja abierta por sucursal.

## Configuración

Variables validadas con zod al arrancar (`src/config/env.ts`): si falta algo, la app no
inicia. Ver `.env.example`.

## Riesgos y mitigaciones

| Riesgo | Mitigación |
|---|---|
| Olvidar el `WHERE tenant_id` | RLS filtra igual |
| Variable de tienda filtrada entre requests | `set_config(..., true)` local |
| Referencia a datos ajenos por UUID | FK compuestas |
| Uso indebido de `percha_system` | Solo lo inyectan los servicios de auth; revisar en code review |
