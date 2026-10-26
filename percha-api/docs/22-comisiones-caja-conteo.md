# 22 · Comisiones, cierre de caja imprimible y conteo de inventario

## Comisiones por vendedora

- Porcentaje por integrante: `PATCH /v1/team/members/:id { commissionBp: 300 }` (3 %;
  `null` = sin comisión; 0–50 %). Cada quien puede fijar la propia.
- `GET /v1/reports/commissions?from&to&branchId` (`reports.read`):
  ventas completadas de la vendedora (por fecha de venta) **más** la diferencia de
  devoluciones y cambios **de sus ventas** (por fecha de la devolución, aunque la procese otra
  persona). La comisión es sobre el neto **sin IGV**. Las anuladas no cuentan.

## Cierre de caja imprimible

- `GET /v1/cash-sessions?branchId` (historial) y `GET /v1/cash-sessions/:id/report`:
  medios de pago, ventas (y anuladas aparte), devoluciones y cambios, abonos de apartados,
  fondo, efectivo esperado, contado y diferencia, con quién abrió y cerró.
- App: al cerrar caja, **"Imprimir cierre"**; en el menú del POS, **"Imprimir corte parcial"**
  (caja abierta) y **"Cierres anteriores"** para reimprimir. Ticket de 58/80 mm con línea de
  firma.

## Conteo de inventario guiado

| Ruta | Para qué |
|---|---|
| `POST /v1/stock-counts { branchId, note? }` | Empezar (uno abierto por sucursal) |
| `POST /v1/stock-counts/:id/items { variantId, mode: add\|set, quantity }` | Cada escaneo suma 1, o fijar la cantidad |
| `DELETE /v1/stock-counts/:id/items/:variantId` | Quitar una prenda del conteo |
| `POST /v1/stock-counts/:id/apply { zeroUncounted }` | Ajustar el stock |
| `POST /v1/stock-counts/:id/cancel` | Cancelar sin ajustar |

- **Con la tienda abierta**: al contar una prenda por primera vez se guarda el stock del
  sistema en ese momento; al aplicar, la diferencia es `contado − stock al contarla`. Una venta
  hecha después de contar NO aparece como faltante (probado).
- Los ajustes van al kardex con el motivo "Conteo de inventario #N" y ligados al conteo: la
  base impide aplicarlo dos veces. La verificación de integridad sigue en `ok`.
- `zeroUncounted: true` solo para un conteo **completo**: lo que tenía stock y no se contó
  queda en 0 (con su motivo "no contada").
