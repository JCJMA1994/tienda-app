# 08 · Capa SaaS: planes, cobro y backoffice

## Ciclo de vida de una suscripción

```
registro ─▶ trialing (14 días, plan Crece)
               │ vence
               ▼
        se emite factura del siguiente mes
        ├─ con tarjeta guardada ─▶ cobro automático ─┬─ ok ──────▶ active
        │                                            └─ rechazo ─▶ past_due
        └─ sin tarjeta (Yape, billeteras, Plin) ─────────────────▶ past_due
past_due ── pago ──▶ active
past_due ── pasan BILLING_GRACE_DAYS (7) ──▶ suspended (solo lectura)
suspended ── pago ──▶ active
active + "cancelar" ── fin del periodo ──▶ canceled (solo lectura)
```

- **Nuestra BD manda**, no la pasarela. Por eso se puede cobrar con Culqi, con Stripe o
  registrar un pago manual, y el ciclo es el mismo.
- **Facturas por adelantado**, únicas por (tienda, inicio de periodo): el job puede correr
  dos veces sin duplicar.
- **Bloqueo suave**: en `suspended`/`canceled` la tienda entra, ve, exporta y paga, pero no
  registra operaciones (`402 SUBSCRIPTION_SUSPENDED`). Nunca se borran datos. Durante la
  gracia (`past_due`) todo funciona normal: la boutique no se queda sin vender por un día de
  atraso.
- Un pago reactiva al instante (se limpia la caché del guard).

## Medios de pago: qué va por dónde

| Medio | Pasarela | Cobro automático | Cómo |
|---|---|---|---|
| Tarjeta (Perú) | **Culqi** | Sí, con tarjeta guardada | Culqi.js tokeniza → `POST /billing/card` → cada mes se cobra solo |
| **Yape** | **Culqi** | No (Yape no permite débito automático) | Cada mes: `POST /billing/invoices/:id/pay {provider:"culqi", method:"yape"}` → Culqi Checkout |
| Billeteras por QR | **Culqi** | No | Igual que Yape con `method:"wallet_qr"`, según los medios habilitados en tu cuenta Culqi |
| Tarjeta internacional | **Stripe** | No (pago por factura) | `{provider:"stripe", method:"card"}` → Stripe Checkout (redirección) |
| **Plin / transferencia** | Manual | No | El dueño paga a la cuenta de la empresa y el superadmin registra `POST /admin/invoices/:id/mark-paid` |

Aclaraciones importantes:

- **Stripe no ofrece Yape ni Plin.** Para billeteras peruanas, Culqi.
- **Stripe no lista Perú para abrir cuenta**: necesitarías una entidad en un país soportado
  (por ejemplo una LLC en EE. UU. con Stripe Atlas). Por eso quedó como opcional: si no
  configuras sus llaves, simplemente no aparece.
- **Plin** no tiene una API pública de cobro como Yape-vía-Culqi; si tu cuenta Culqi lo
  incluye en "billeteras móviles" (QR), entra por `wallet_qr`. Si no, el flujo manual cubre
  el caso.
- Los campos de la API de Culqi están en `culqi.provider.ts` siguiendo la v2. **Valídalos con
  tus llaves de integración** antes de producción: es el único archivo a ajustar.

## Pagar desde la app

`POST /billing/invoices/:id/pay` devuelve siempre una `url` para abrir en el navegador:

- **Stripe**: la URL de Stripe Checkout.
- **Culqi**: una página de esta API (`GET /v1/billing/pay/:id?t=…`) que carga Culqi
  Checkout con la orden (Yape, billeteras, agentes). El enlace está **firmado** (HMAC con el
  secreto del JWT, 1 hora): no expone la sesión del usuario. La página tiene su propia CSP
  que solo permite scripts de Culqi. **Verifica `pay-page.ts`** contra la guía vigente de
  Culqi Checkout antes de producción.

La página no acredita nada: el pago se confirma solo por webhook (con verificación contra la
API de Culqi). La app, al volver, recarga el estado.

**Guardar tarjeta (cobro automático)**, también desde la app móvil:

1. La app pide `POST /billing/card/setup-link` (solo el dueño) → enlace firmado de 30 min
   que identifica tienda, usuario y membresía (no lleva la sesión).
2. Se abre `GET /v1/billing/card-setup?t=…`: página con Culqi Checkout **solo tarjeta**.
   Culqi tokeniza en el navegador: **la tarjeta nunca pasa por nuestro servidor**.
3. La página envía el token a `POST /v1/billing/card-setup {t, token, phone}`; el backend
   valida la firma, crea cliente y tarjeta en Culqi y activa `autopay`.

## Webhooks

```
POST /v1/billing/webhooks/culqi
POST /v1/billing/webhooks/stripe
```

- **Stripe**: firma `Stripe-Signature` (HMAC-SHA256 sobre el cuerpo crudo, máximo 5 min de
  antigüedad). La app se crea con `rawBody: true` para poder verificarla.
- **Culqi**: verificación por *fetch-back*. No se confía en el cuerpo: se toma el id de la
  orden y se consulta a Culqi con la llave secreta; solo si responde `paid` se acredita.
- **Idempotencia**: cada evento se guarda con (pasarela, id) único. Si la pasarela reintenta,
  no pasa nada. Y `markPaid` solo actúa sobre facturas abiertas, así que un webhook y un
  cobro automático simultáneos no cobran dos veces.

## Límites por plan

| Plan (ejemplo) | Precio | Sucursales | Usuarios | Productos |
|---|---|---|---|---|
| Emprende | S/ 79 | 1 | 3 | 500 |
| Crece | S/ 149 | 3 | 10 | 5 000 |
| Pro | S/ 299 | ∞ | ∞ | ∞ |

**Precios y límites son de ejemplo** (migración `0004`): ajústalos con un `UPDATE plans`.
Se verifican al crear sucursales, productos (también en la importación, por archivo completo)
e invitaciones (una invitación pendiente ocupa cupo). Respuesta: `402 PLAN_LIMIT` con
`resource`, `limit` y `current`, para que la app ofrezca mejorar el plan.

- Subir de plan: límites nuevos al instante, precio nuevo desde la próxima factura (sin
  prorrateo, más fácil de explicar).
- Bajar de plan: solo si el uso actual cabe (`409 PLAN_USAGE_EXCEEDS`).

## Backoffice (superadmin)

```bash
DATABASE_OWNER_URL=... npm run admin:make -- tu@correo.com
```

| Endpoint | Para qué |
|---|---|
| `GET /admin/metrics` | Tiendas por estado, **MRR**, pruebas que vencen en 7 días |
| `GET /admin/tenants` | Todas las tiendas: plan, estado, uso, última venta, deuda |
| `GET /admin/tenants/:id/invoices` | Facturas de una tienda (para registrar pagos manuales) |
| `PATCH /admin/tenants/:id` | Bloqueo duro (`status`), cambiar plan, regalar días (`extendDays`) |
| `POST /admin/invoices/:id/mark-paid` | Registrar Plin/transferencia verificados |
| `POST /admin/billing/run` | Correr el ciclo a mano (o con `now` para simular) |

`/auth/me` incluye `isPlatformAdmin` para que la app muestre el backoffice; aun así, el
permiso de superadmin se verifica **en la BD en cada request**, no en el JWT: quitar a
alguien de `platform_admins` le corta el acceso al instante. Cada acción queda en la bitácora
de la tienda afectada.

## Operación

- **Cron**: `npm run build && npm run billing:run` cada hora (Railway Cron, Render Cron Job o
  GitHub Actions). Una transacción por tienda: si la pasarela falla con una, las demás siguen.
- **Pasarela simulada** (`BILLING_FAKE_SECRET`): solo desarrollo y pruebas; la app **no
  arranca** en producción si está definida.

## Pruebas

`test/billing.spec.ts` recorre el ciclo entero con la pasarela simulada: prueba, límites,
factura, idempotencia del job, gracia, bloqueo suave, pago por webhook (firma inválida,
duplicado), renovación con tarjeta, rechazo, pago manual por Plin y cancelación. Más la
verificación de firma de Stripe y `addMonths` (31 de enero + 1 mes = 28/29 de febrero).
