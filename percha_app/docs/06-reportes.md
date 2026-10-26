# 06 · Reportes

Ruta `/reports` (permiso `reports.read`: dueño y encargado). También desde la tarjeta
**Ventas de hoy** del inicio.

## Bloques

| Bloque | Qué responde | Endpoint |
|---|---|---|
| Resumen | ¿Cuánto vendí, cuántos tickets, ticket promedio, margen? | `/reports/summary` |
| Ventas por día | ¿Qué días vendo más? (resalta el mejor día) | `/reports/daily` |
| Más vendidos | Top 10 por prendas netas, con ingreso y margen | `/reports/top-products` |
| Rotación por talla y color | ¿Qué tallas se agotan y cuáles sobran? | `/reports/attributes` |
| Stock sin rotar | ¿Qué está inmovilizado hace 30/60/90 días? | `/reports/dead-stock` |
| Valor del inventario | ¿Cuánto vale lo que tengo, a costo y a precio de venta? | `/reports/valuation` |

Períodos: Hoy, 7 días, 30 días y Este mes. Se calculan como **fechas locales** y la API los
interpreta en la zona horaria de la tienda (`America/Lima` por defecto). La aritmética es por
calendario, no por horas, para no fallar con horario de verano (`test/period_test.dart`).

## Decisiones de diseño

- **Cada bloque carga por separado** (un provider por endpoint): si uno tarda o falla, el
  resto se ve. Deslizar hacia abajo recarga todo.
- **Gráfico sin librería**: barras dibujadas con widgets simples. Una dependencia menos y el
  estilo sigue la identidad de Percha. Cada barra tiene tooltip con fecha, monto y tickets.
- **Lectura de la rotación**: naranja desde 70% de sell-through (se agota → reponer); índigo
  por debajo. Debajo de cada barra, "vendidas/total" para no depender solo del color.
- **Costos**: la API no envía margen ni costo a quien no tiene `costs.read`; la app oculta
  esas tarjetas en lugar de mostrar ceros.

Las definiciones exactas (ventas netas, anulaciones, devoluciones, IGV) están en
`percha-api/docs/07-reportes.md`.
