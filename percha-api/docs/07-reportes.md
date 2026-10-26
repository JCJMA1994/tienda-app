# 07 · Reportes

Todos exigen `reports.read` (dueño y encargado). Los campos de costo y margen solo se envían
a quien tiene `costs.read`. Un miembro con sucursal fija ve solo su sucursal.

## Endpoints

| Endpoint | Responde |
|---|---|
| `GET /reports/summary?from=&to=&branchId=` | Ventas netas (con y sin IGV), tickets, unidades, ticket promedio, descuentos, anuladas, devoluciones, costo de lo vendido y margen |
| `GET /reports/daily` | Serie diaria con **todos** los días del rango (los vacíos en 0, listos para graficar) |
| `GET /reports/top-products?limit=10` | Más vendidos por unidades netas, ingreso y margen |
| `GET /reports/attributes?productId=` | Rotación por talla, color… : vendidas, stock actual y *sell-through* |
| `GET /reports/dead-stock?days=60` | Variantes con stock y sin ventas en N días, ordenadas por plata inmovilizada |
| `GET /reports/valuation` | Inventario actual por categoría, a costo y a precio de venta, y margen potencial |

`from` y `to` son fechas **locales de la tienda** (`YYYY-MM-DD`, inclusive). Por defecto, los
últimos 30 días. Rango máximo: un año.

## Definiciones (para que los números cuadren con la caja)

- **Ventas netas** = total de ventas completadas + diferencia de devoluciones y cambios del
  período. Es el dinero que efectivamente entró por ventas. Una devolución resta el día en
  que ocurre, no el día de la venta original (igual que la caja).
- **Ventas anuladas**: no existen para los reportes. Se excluyen la venta y su reverso en el
  kardex, aunque la anulación haya ocurrido otro día.
- **Unidades** y **costo de lo vendido** salen del **kardex**: venta − devolución + prenda
  entregada en un cambio. El costo es el que se registró en cada salida (costo promedio de
  ese momento), así que el margen de un mes pasado no cambia si hoy sube el costo.
- **Margen** = ventas netas sin IGV − costo de lo vendido. El IGV no es ingreso de la tienda.
- **Sell-through** = vendidas / (vendidas + stock actual). Una talla con 80% se está
  agotando; una con 5%, sobra.
- **Stock muerto**: con unidades en la sucursal y sin ventas en N días; si nunca se vendió,
  cuenta desde que entró.

**Supuesto**: los precios incluyen IGV (lo normal en retail en Perú, y la configuración por
defecto). Con precios sin IGV, el ingreso por producto es una aproximación.

## Zona horaria

`tenants.timezone` (por defecto `America/Lima`) define qué es "hoy": una venta a las 23:30
pertenece a ese día aunque en UTC ya sea el siguiente. Los límites del rango se calculan en
Postgres con `AT TIME ZONE`, y la serie diaria agrupa por fecha local. Se puede cambiar con
`PATCH /store { "timezone": "America/Bogota" }` (se valida que sea una zona IANA real).

## Rendimiento y seguridad

- Son consultas de agregación en SQL (no se traen filas a Node para sumar).
- Índices usados: `sales (tenant_id, created_at)` y el nuevo
  `stock_movements (tenant_id, created_at)` (migración `0002_reports`).
- Corren dentro de `withTenant`: **RLS también filtra el SQL crudo**, así que un reporte no
  puede mezclar tiendas aunque una consulta olvide un filtro.
- Cuando el volumen crezca, el siguiente paso natural es una tabla de resumen diario
  (o una vista materializada) que se actualice al cerrar caja.

## Pruebas

`test/reports.spec.ts` arma un día de tienda (ventas, descuento, anulación, cambio de talla y
una correa con 45 días sin rotar) y verifica cada número a mano: ventas netas 74 061,
unidades 4, costo 32 000, margen 49%, M con 80% de sell-through, valorización 36 000 a costo.
