# 15 · Vales (saldo a favor, gift cards) y apartados

## Vales

| Tipo | Cómo nace | Dinero en caja |
|---|---|---|
| **Saldo a favor** (`refund`) | Devolución con reembolso `store_credit`, o apartado cancelado | No sale dinero |
| **Gift card** (`gift`) | `POST /gift-cards` (se cobra en caja) | Entra al venderla |
| **Cortesía** (`courtesy`) | `POST /store-credits/courtesy` (permiso `sales.void`, auditado) | No |

- **Pagar con vale**: en la venta, pago `{ method: 'store_credit', amountCents, creditCode }`,
  combinable con otro medio. Se descuenta con un `UPDATE` condicional (saldo suficiente y
  vigente) dentro de la transacción de la venta: **dos cajas no pueden gastar el mismo saldo**
  (probado con ventas simultáneas). Sin saldo, no se registra la venta ni se mueve stock.
- **Anular** una venta pagada con vale devuelve el saldo.
- **Código**: `VALE-XXXX-XXXX-XXXX` (60 bits; sin 0/O/1/I/L para dictarlo sin errores). Es un
  título al portador: se muestra **una sola vez** al emitirse (para imprimir con QR o copiar) y
  se guarda solo su hash. La consulta (`GET /store-credits/lookup?code=`) acepta minúsculas, sin
  guiones o con espacios, y tiene límite de ritmo.
- Saldo con `CHECK (0 ≤ saldo ≤ inicial)` y movimientos **inmutables** (`store_credit_movements`).
- Vigencia: 1 año por defecto. La ficha del cliente muestra su saldo a favor vigente.
- **Comprobantes**: la gift card no lleva boleta al venderse (aún no se vende mercadería); la
  boleta sale cuando se canjea. El saldo a favor nace de una devolución que ya tiene su nota de
  crédito. Valídalo con tu contador para tu caso.

## Apartados

```
POST /layaways                 { branchId, customerId, items, payments (adelanto), days }
POST /layaways/:id/payments    abono
POST /layaways/:id/complete    { payments? (saldo), document? }  → entrega y venta
POST /layaways/:id/cancel      { reason, refund: cash | store_credit | none }
GET  /layaways?status=&customerId=     GET /layaways/:id
```

- **Adelanto mínimo 10 %**. Las prendas salen del **disponible** (`layaway_reserve`): nadie más
  las vende. Si falta stock de una, no se aparta nada.
- **Precio congelado**: si el precio sube, al cliente se le respeta el del día que apartó.
- **Abonos** en cualquier caja de la sucursal (entran a caja al pagarse; nunca más que el saldo).
- **Entregar** (todo pagado): se libera la reserva y se registra la **venta normal**: kardex de
  venta con costo, comprobante electrónico y cliente; se paga con el método `layaway`, que **no
  vuelve a sumar efectivo** (probado). El stock no se descuenta dos veces.
- Una venta de apartado **no se anula** (el dinero ya entró en abonos): se corrige con una
  devolución.
- **Cancelar** devuelve el stock y lo abonado: en efectivo, como **vale** o se retiene según la
  política de la tienda (auditado). Permiso `sales.return`.
- **Vencidos**: `npm run layaways:run` (diario) avisa a la sucursal; la lista los muestra primero.
- Comprobante: se emite al entregar. Si recibes anticipos importantes, consulta con tu contador
  si corresponde emitir comprobante por cada anticipo.

## Pruebas

`test/credits-layaways.spec.ts` (12): reembolso como vale sin mover caja, consulta tolerante,
pago mixto, saldo insuficiente sin venta, gasto simultáneo, restitución al anular, cortesía con
permiso, gift card en caja, saldo en la ficha; apartado con mínimo, abonos, entrega al precio
congelado sin duplicar stock ni caja, kardex, bloqueo de anulación, cancelación con vale o
efectivo y aviso de vencidos.
