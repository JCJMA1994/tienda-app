# 04 · Inventario

## Regla de oro

**El stock solo cambia a través de `InventoryService.apply()`.** Nadie escribe
`stock_levels` directamente.

```
stock_movements (kardex)   ← fuente de verdad, inmutable
        │
        ▼
stock_levels               ← proyección: saldo por sucursal × variante
```

Cada movimiento guarda su `balanceAfter`, así el kardex se lee como un estado de cuenta.

| Tipo | Signo | Origen |
|---|:-:|---|
| `initial` | + | alta de producto o importación |
| `adjustment` | ± | ajuste manual con motivo |
| `purchase_receipt` | + | recepción de compra |
| `sale` | − | venta |
| `sale_void` | + | anulación |
| `return_in` | + | devolución del cliente |
| `exchange_out` | − | prenda entregada en un cambio |

## Concurrencia: la última prenda

Dos vendedores cobran el último vestido M Negro al mismo tiempo. `apply` hace:

```sql
UPDATE stock_levels
   SET quantity = quantity + $delta
 WHERE branch_id = $b AND variant_id = $v
   AND quantity + $delta >= 0
RETURNING quantity;
```

- El UPDATE **bloquea la fila**: la segunda transacción espera.
- Cuando la primera confirma, la segunda re-evalúa la condición, no actualiza nada y
  responde `422 INSUFFICIENT_STOCK` con el disponible real.
- Como todo ocurre dentro de la transacción de la venta, la venta completa se revierte.
- Los movimientos se procesan **ordenados por variante**: dos ventas con las mismas
  prendas bloquean en el mismo orden y no hay deadlocks.

La prueba *"dos ventas simultáneas de la última unidad"* lo verifica.

Si la tienda activa `allowNegativeStock`, se omite la condición para salidas (útil si se
vende antes de registrar la llegada de mercadería; no recomendado).

## Ajustes

```json
POST /inventory/adjustments
{ "branchId": "…", "reason": "Conteo físico",
  "items": [{ "variantId": "…", "counted": 2 }, { "variantId": "…", "delta": -1 }] }
```

- `delta`: variación directa (merma, daño, robo).
- `counted`: conteo físico; el sistema calcula la diferencia bloqueando el saldo actual.
- El motivo es obligatorio y queda en el kardex y en la auditoría.

## Inmutabilidad

`percha_app` no tiene UPDATE/DELETE sobre `stock_movements`, y un trigger lo impide incluso
al dueño. Un error se corrige con un movimiento contrario, como en contabilidad.

## Endpoints

```
GET /inventory/stock?branchId=&variantId=&lowOnly=true
GET /inventory/movements?variantId=&branchId=&limit=&before=   (cursor por fecha)
POST /inventory/adjustments
PUT  /inventory/min-stock     { branchId, variantId, minQuantity }
```

Un miembro con sucursal fija solo ve y ajusta su sucursal.
