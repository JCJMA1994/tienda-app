# 17 · Arquitectura: reglas, eventos y límites entre módulos

Refactorización guiada por la revisión de Clean Architecture / SOLID. Sin cambios de
comportamiento: las 121 pruebas previas siguen pasando, y se agregaron pruebas de arquitectura
y de eventos (132 en total).

## 1. Dominio sin framework (`DomainError`)

`common/domain-error.ts`: errores de negocio con **tipo** (`invalid`, `not_found`, `conflict`,
`rule`) y **código** estable. El filtro HTTP los traduce (400/404/409/422) y agrega sus
detalles. Las reglas puras ya no importan NestJS:

- `einvoice/document.ts` (cliente de boleta/factura, IGV por línea)
- `einvoice/guide.ts` (reglas del traslado)
- `credits/credits.service.ts` (vales: formato, saldo, vigencia)

Las mismas reglas sirven en un job, un script o una cola sin cambiar nada.

## 2. Eventos de dominio (`EventBus`)

Los servicios publican **hechos**; los módulos interesados se **suscriben**. Una función nueva
se agrega suscribiéndose, sin editar el servicio que origina el hecho (abierto/cerrado).

| Evento | Suscriptores |
|---|---|
| `sale.recorded` | emitir boleta o factura · asociar cliente a la venta |
| `sale.voided` | nota de crédito motivo 01 |
| `return.recorded` | nota de crédito 07 y comprobante del cambio |
| `transfer.sent` | guía de remisión · aviso a la sucursal destino |
| `transfer.cancelled` | pedir baja de guías aceptadas → `einvoice.guide_void_needed` |
| `stock.below_minimum`, `einvoice.rejected`, `subscription.*`, `team.member_joined`, `layaway.expired` | notificaciones |

- Los manejadores corren **en la misma transacción**: si uno falla (p. ej. guía sin datos del
  traslado), se revierte todo.
- Lo que debe pasar **después del commit** (enviar al OSE) usa `DatabaseService.afterCommit`:
  si la transacción se revierte, no se ejecuta (probado).
- Todos los textos y destinatarios de notificaciones están en un solo archivo:
  `notifications/notification-rules.ts`.

## 3. Métodos en pasos con nombre

- `ReturnsService.create` (141 → ~40 líneas): `lockReturnableSale` → `valueReturnedItems` →
  `insertReturn` → `settleDifference` → stock → evento.
- `SalesService.createTx`: `authorizeDiscount` → `validatePayments` → `insertSale` →
  `insertItems` → `collectPayments` → stock → evento.
- `PurchasingService.receive`: `validateSupplierInvoice` aparte.
- `BillingService.run` (89 → ~25 líneas): `processTenant` → `chargeSavedCard` → `setStatus`.
- `ImportService.run` (123 → ~25 líneas): reglas puras `groupRows` y `validateFile` (probadas sin
  base de datos en `test/import-rules.spec.ts`) + `conflictsWithExisting`, `ensureAttributes`,
  `ensureCategories`, `createProduct`.

## 4. Límites entre módulos

- Utilidades compartidas en `common/`: `crypto` (Argon2, SHA-256, AES-GCM), `authz` (permisos y
  decoradores), `dates`, `peru` (RUC), `domain-error`, `events`.
- **Sin dependencias circulares** entre módulos (antes: `access ↔ auth`, `access ↔ billing`,
  `billing ↔ notifications`).
- Ningún módulo llama directamente a notificaciones (antes: 6 servicios lo hacían).
- `SalesService`: de 8 dependencias a 7, y ya no depende de comprobantes ni de clientes (solo
  publica el hecho).

## 5. Reglas verificadas en cada corrida

`test/architecture.spec.ts` falla si:
- un archivo de dominio (`money`, `dates`, `peru`, `domain-error`, `document`, `guide`, `totp`,
  `codes`) importa NestJS, Drizzle o la base de datos;
- aparece un ciclo de dependencias entre módulos.

## Decisiones conscientes

- **Sin capa de repositorios por ahora.** Las consultas usan Drizzle dentro de la transacción
  con RLS, y las pruebas de integración contra Postgres real validan justo eso (aislamiento,
  bloqueos, concurrencia). Un repositorio solo para "poder simular la base" restaría
  confianza en lo más delicado. La lógica que sí conviene probar sin base se extrae como
  funciones puras (dinero, comprobantes, guías, importación, TOTP).
- **Excepciones HTTP en la capa de aplicación.** Los servicios de NestJS son la capa de
  aplicación y pueden lanzar `BadRequestException`; el **dominio puro** usa `DomainError` y la
  prueba de arquitectura lo exige.
