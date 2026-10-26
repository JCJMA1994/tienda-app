# 02 · Identidad, roles y equipo

## Modelo

- `users`: persona global (un correo). Puede pertenecer a varias tiendas.
- `memberships`: usuario ↔ tienda, con `role`, `branchId` opcional (null = todas las
  sucursales), `pinHash` y `status`.
- `invitations`: correo + rol + sucursal, con token de un solo uso (se guarda su SHA-256).

## Sesiones

| Token | Formato | Vida | Dónde se valida |
|---|---|---|---|
| Access | JWT (`sub`, `tid`, `mid`, `role`, `bid`) | 15 min | En memoria, sin consultar la BD |
| Refresh | Opaco, 32 bytes | 30 días | BD (solo su hash) |

**Rotación**: cada refresh invalida el anterior y emite uno nuevo. Si llega un refresh ya
usado, se asume robo y se revocan todas las sesiones del usuario.

> Bug encontrado por las pruebas: la revocación se hacía y luego se lanzaba el error dentro
> de la misma transacción, lo que provocaba rollback y la revocación nunca se guardaba.
> Ahora la revocación ocurre en una transacción aparte (`TokenService.rotate`).

**Compromiso aceptado**: un cambio de rol o una baja tarda hasta 15 minutos en aplicarse
(lo que dura el access token). El refresh sí relee la membresía. Si se necesitara inmediatez,
se puede agregar una versión de sesión en la membresía y verificarla en el guard.

## Login con varias tiendas

Si el usuario pertenece a más de una tienda y no envía `tenantId`, la respuesta es
`{ requiresTenantSelection: true, tenants: [...] }` y la app muestra el selector.
Con correo inexistente se compara igual contra un hash ficticio, para no revelar por el
tiempo de respuesta qué correos están registrados.

## Roles y permisos

Los endpoints piden **permisos**, nunca roles (`@RequirePermissions('sales.void')`).

| Permiso | Dueño | Encargado | Vendedor | Almacén |
|---|:-:|:-:|:-:|:-:|
| settings.manage | ✓ | ✓ | | |
| billing.manage | ✓ | | | |
| team.manage | ✓ | ✓¹ | | |
| catalog.read | ✓ | ✓ | ✓ | ✓ |
| catalog.write | ✓ | ✓ | | |
| costs.read | ✓ | ✓ | | |
| inventory.read | ✓ | ✓ | ✓ | ✓ |
| inventory.adjust | ✓ | ✓ | | ✓ |
| cash.manage | ✓ | ✓ | ✓ | |
| sales.create / sales.read | ✓ | ✓ | ✓ | |
| sales.return | ✓ | ✓ | ✓ | |
| sales.discount_over_limit | ✓ | ✓ | PIN² | |
| sales.void | ✓ | ✓ | PIN² | |
| purchasing.read | ✓ | ✓ | | ✓ |
| purchasing.write | ✓ | ✓ | | |
| purchasing.receive | ✓ | ✓ | | ✓ |
| reports.read | ✓ | ✓ | | |

¹ Un encargado solo gestiona vendedores y almaceneros, y si tiene sucursal fija, solo de la suya.
² "Con aprobación": el vendedor no tiene el permiso, pero un supervisor ingresa su PIN en la
tablet (`ApprovalService`) y queda registrado quién aprobó.

### `GET /roles`

Se **genera** desde `ROLE_PERMISSIONS`, `APPROVABLE`, `BRANCH_SCOPED` y `ASSIGNABLE_ROLES`, la
misma fuente que usan los guards: la app ya no duplica la matriz. Cada rol trae `access` con
un nivel por permiso: `yes`, `no`, `approval` (con PIN de supervisor) u `own_branch`. Una
prueba verifica que lo publicado coincide con lo que se aplica. Se cachea 1 hora en el cliente.

Quien no tiene `costs.read` no recibe `costCents` ni `avgCostCents` en ninguna respuesta.

## Reglas del equipo

- Nadie cambia su propio rol ni estado.
- La tienda siempre conserva al menos un dueño activo.
- El **PIN es único** entre quienes comparten sucursal: si dos vendedores tuvieran el mismo,
  el cambio rápido no sabría a quién asignar la venta.
- El cambio de vendedor por PIN (`POST /auth/pin`) tiene límite de 5 intentos por minuto,
  porque un PIN de 4 dígitos es adivinable.

## Endpoints

```
POST /auth/register            crea tienda + sucursal principal + dueño
POST /auth/login
POST /auth/refresh
POST /auth/logout
POST /auth/pin                 cambio de vendedor en el POS
POST /auth/invitations/accept
GET  /auth/me                  usuario, rol y lista de permisos (la app oculta botones con esto)
GET  /roles                    catálogo de roles: etiquetas, nivel de acceso por permiso y roles asignables

GET    /team/members
PATCH  /team/members/:id       rol, sucursal, estado
PUT    /team/members/:id/pin
POST   /team/invitations       devuelve el token una sola vez
GET    /team/invitations
DELETE /team/invitations/:id
```

## Onboarding

`GET /store/onboarding` **calcula** el progreso desde los datos reales (RUC cargado,
atributos, productos, equipo, primera venta) en vez de guardar banderas. Si el dueño
importa productos por otra vía, el paso se marca solo.

```
GET   /store         PATCH /store
GET   /store/onboarding
POST  /store/onboarding/dismiss
GET   /branches      POST /branches      PATCH /branches/:id
```
