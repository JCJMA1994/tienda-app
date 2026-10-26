# 21 · Promociones automáticas

Tipos: **porcentaje** (1–90 %) y **lleva X, paga Y** (2x1, 3x2…). Alcance: todo el catálogo,
categorías o productos. Vigencia con inicio y fin opcional; se pueden pausar.

## Rutas

| Ruta | Permiso |
|---|---|
| `GET /v1/promotions` | `sales.create` (el POS las lee) |
| `POST /v1/promotions`, `PUT /v1/promotions/:id` | `catalog.write` |
| `POST /v1/sales/quote` `{ branchId, items, discountCents }` | `sales.create` — total exacto antes de cobrar |

## Reglas (motor `modules/promotions/engine.ts`)

1. Una prenda recibe **una sola** promoción.
2. *Lleva X, paga Y*: se juntan las prendas elegibles del ticket (aunque sean distintas), de
   la más cara a la más barata; en cada grupo completo de X salen gratis las más baratas.
3. Porcentaje: a lo que quede, el mejor porcentaje vigente (redondeo por prenda).
4. Se calculan dos formas (con y sin *lleva X, paga Y*) y gana la que **más ahorra al cliente**.
5. El descuento manual se aplica **después** de las promociones, y su límite se mide sobre lo
   que queda.

**El mismo motor existe en la app (Dart)** y ambos pasan los mismos casos
(`test/fixtures/promotions-vectors.json`; la app tiene una copia). Si cambias una regla,
cambia los casos y verifica en los dos lados.

## Dónde se aplica

- **Venta**: el servidor recalcula siempre (la app no puede inventar descuentos). En la venta
  quedan `discountCents` (total = promo + manual) y `promoDiscountCents`; en cada línea,
  `promoDiscountCents` y `promotionId`. Comprobante, devoluciones y reportes usan el neto por
  línea, así que todo cuadra sin cambios.
- **Sin conexión**: la foto del POS trae las promociones; al sincronizar, el servidor usa las
  vigentes **a la hora real de la venta** (probado).
- **Apartados**: conservan el precio congelado al apartar; no se les aplican promociones
  nuevas al entregarlos.
- **Catálogo en línea**: etiqueta "−30 %" con el precio rebajado, o "2x1"; el total del
  pedido ya las considera.
- **Devoluciones**: se valoran al precio realmente pagado por línea (prorrateado): en un 2x1
  de dos prendas iguales, cada una vale la mitad.
