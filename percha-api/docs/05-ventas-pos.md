# 05 · Caja, ventas, anulaciones y cambios

## Caja

- Un turno abierto por sucursal (índice único parcial en BD).
- No se puede vender sin caja abierta (`409 CASH_CLOSED`).
- Las ventas toman la caja con `FOR SHARE` y el cierre con `FOR UPDATE`: el cierre espera a
  que terminen las ventas en curso y ninguna venta entra en una caja que se está cerrando.
- Al cerrar, el **efectivo esperado se calcula** (apertura + pagos en efectivo − reembolsos);
  el cajero solo declara lo contado y se guarda la diferencia.

## Una venta

```json
POST /sales
{ "branchId": "…",
  "items": [{ "variantId": "…", "quantity": 1 }],
  "discountCents": 5000,
  "payments": [{ "method": "cash", "amountCents": 13990 }],
  "cashReceivedCents": 15000,
  "approverPin": "4321" }
```

En **una sola transacción**:

1. Caja abierta de la sucursal.
2. Precios desde la BD (la app solo dice qué y cuánto; una app manipulada no cambia precios).
3. Ítems repetidos se fusionan (el mismo código escaneado dos veces).
4. Descuento: si supera `discountLimitBp` (10% por defecto) y el vendedor no tiene
   permiso, exige PIN de supervisor (`APPROVAL_REQUIRED` / `APPROVAL_INVALID`).
5. IGV: con precios que lo incluyen, `igv = total × 18/118`. Si no, se suma al total.
6. La suma de pagos debe ser igual al total (`PAYMENT_MISMATCH`). Se permiten pagos mixtos.
   El vuelto sale de `cashReceivedCents`.
7. Correlativo de venta, líneas, pagos y salida de stock.

El descuento del ticket se **prorratea en las líneas** (método del mayor residuo, sin perder
céntimos). Así una prenda se devuelve al precio que realmente se pagó.

Cada línea guarda una foto del costo promedio al vender (`unitCostCents`): el margen
histórico no cambia aunque el costo suba después.

## Anular vs. devolver

| | Anular | Devolver / cambiar |
|---|---|---|
| Cuándo | Error: cobro duplicado, digitación | El cliente regresa la prenda |
| Plazo | Solo en el mismo turno de caja | Cualquier momento |
| Permiso | `sales.void` o PIN de supervisor | `sales.return` |
| Efecto | Venta queda `voided`, stock vuelve, pagos se revierten con montos negativos | Documento propio con correlativo |

Una venta con devoluciones ya no se puede anular (`USE_RETURN`). Los pagos nunca se
borran: se revierten con montos negativos para que el cierre cuadre.

## Cambio de talla

El caso más común en una boutique:

```json
POST /sales/:id/returns
{ "branchId": "…",
  "items": [{ "saleItemId": "…", "quantity": 1 }],
  "replacements": [{ "variantId": "<S Beige>", "quantity": 1 }],
  "payments": [{ "method": "cash", "amountCents": 5000 }],
  "reason": "Le quedó grande" }
```

- Valor devuelto = lo que se pagó por esa línea (con su parte del descuento y el factor
  de IGV de esa venta).
- Prenda nueva = precio vigente.
- Diferencia > 0 → paga el cliente; < 0 → se reembolsa; los montos se envían positivos y
  el servidor decide el signo.
- Sin `replacements` es una devolución simple con reembolso.
- No se puede devolver más de lo vendido ni con dos devoluciones simultáneas
  (UPDATE condicional sobre `returnedQuantity`).

## Endpoints

```
POST /cash-sessions                       abrir
GET  /cash-sessions/current?branchId=     con resumen por método
POST /cash-sessions/:id/close

POST /sales      GET /sales?branchId=&number=&from=&to=      GET /sales/:id
POST /sales/:id/void
POST /sales/:id/returns                   GET /sales/:id/returns
```

## Pendiente

Clientes y fidelización, comprobantes electrónicos (boleta/factura vía OSE), plazo máximo
de devolución configurable y nota de crédito como forma de reembolso.
