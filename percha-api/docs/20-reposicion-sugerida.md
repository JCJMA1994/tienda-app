# 20 · Reposición sugerida

`GET /v1/purchasing/suggestions?branchId=…&windowDays=28&coverDays=30&leadDays=7`
(permiso `purchasing.write`)

Para cada variante (talla × color) activa de la sucursal:

| Dato | De dónde sale |
|---|---|
| Vendido (neto) | Kardex de la ventana: ventas y prendas de cambio, menos devoluciones y anulaciones. Ajustes y transferencias **no** cuentan como demanda |
| Stock y mínimo | `stock_levels` de la sucursal |
| En camino | Órdenes `ordered`/`partial` de la sucursal (pedido − recibido) |
| Proveedor y costo | Última compra de esa variante; si nunca se compró, costo promedio o del producto y grupo "sin proveedor" |

Cálculo (`replenishment.ts`, funciones puras probadas):

```
ritmo    = vendido / días de la ventana
objetivo = ⌈ritmo × (días a cubrir + días que tarda el proveedor)⌉
pedir    = máx(objetivo, mínimo) − stock − en camino      (nunca negativo)
```

Urgencia: **agotada** (stock 0) · **se agota pronto** (no alcanza hasta que llegue un pedido)
· **este mes** · **planificada**. Se ordena por urgencia y se agrupa por proveedor.

Respuesta: `{ params, totals, suppliers: [{ supplierId, supplierName, units, totalCents, items }] }`.

En la app: Compras → Reposición sugerida. Se ajustan los días y las cantidades, y
**"Crear orden"** genera una orden de compra en **borrador** por proveedor (se revisa y
confirma antes de enviarla).

Límite conocido: si una talla estuvo agotada parte de la ventana, sus ventas reales fueron
menores a la demanda; la sugerencia puede quedarse corta. Conviene mirar 4–8 semanas.
