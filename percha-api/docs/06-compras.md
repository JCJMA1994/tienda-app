# 06 · Compras

## Ciclo de una orden de compra

```
draft ──confirm──▶ ordered ──receive──▶ partial ──receive──▶ received
  └──────────── cancel ◀──────┘   (solo si aún no se recibió nada)
```

- Solo se edita en **borrador**: una OC enviada al proveedor es un compromiso.
- Cada variante aparece una sola vez por orden.
- Correlativos propios para OC y para recepciones.

## Recepción

```json
POST /purchase-orders/:id/receipts
{ "items": [{ "purchaseOrderItemId": "…", "quantity": 2, "unitCostCents": 9500 }] }
```

En una transacción:

1. Valida que no se reciba más de lo pendiente (422 con el pendiente real).
2. Recalcula el **costo promedio ponderado** de cada variante.
3. Registra la entrada `purchase_receipt` en el kardex.
4. Pasa la OC a `partial` o `received`.

`unitCostCents` es opcional: sirve cuando la factura trae un costo distinto al de la OC.

## Costo promedio ponderado

```
nuevo = (stock_actual × costo_actual + cantidad × costo_compra) / (stock_actual + cantidad)
```

Ejemplo de la prueba: 2 unidades a S/ 80 + 2 nuevas a S/ 95 → S/ 87.50.

- Es el método más simple para retail y aceptado tributariamente en Perú.
- Se bloquea la variante (`FOR UPDATE`) para que dos recepciones simultáneas no pisen el cálculo.
- Si el stock es cero o negativo, el costo de la compra pasa a ser el nuevo promedio.
- El costo es único por variante (no por sucursal): suficiente para una boutique; si
  algún día cada sucursal compra a precios muy distintos, se mueve a `stock_levels`.

## Endpoints

```
GET/POST /suppliers           PATCH /suppliers/:id
GET  /purchase-orders?status=&supplierId=
POST /purchase-orders         GET/PATCH /purchase-orders/:id
POST /purchase-orders/:id/confirm
POST /purchase-orders/:id/cancel
POST /purchase-orders/:id/receipts
GET  /purchase-orders/:id/receipts
```

## Pendiente

Devoluciones a proveedor, cuentas por pagar y sugerencia de compra según stock mínimo y
rotación (encaja con los reportes de la fase 7).
