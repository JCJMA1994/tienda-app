# 03 · Catálogo

## Modelo

```
attributes (Talla: S,M,L · Color: Negro,Beige)   ← definidos por cada tienda
categories
products   (nombre, precio base, costo, SKU base)
  └── variants (combinación de atributos, SKU, código de barras, precio opcional, costo promedio)
```

El stock vive en las **variantes**, nunca en el producto.

## Atributos

- Cada valor tiene un `code` para el SKU, generado automáticamente: "Negro" → `NEG`,
  "Azul marino" → `AZU`, "XL" → `XL`. Si choca, se numera (`NEG2`).
- Se pueden agregar y reordenar valores, pero **no quitar uno en uso** ni renombrar un
  atributo que ya usan variantes: rompería SKUs y el historial de ventas (409).

## Crear un producto con su matriz

```json
POST /products
{
  "name": "Vestido midi",
  "skuBase": "VST-014",
  "priceCents": 18990,
  "costCents": 8000,
  "matrix": { "Talla": ["S", "M", "L"], "Color": ["Negro", "Beige"] },
  "initialStock": { "branchId": "…", "items": [{ "options": { "Talla": "M", "Color": "Negro" }, "quantity": 2 }] }
}
```

- Se crean las 6 combinaciones (producto cartesiano), con límite de 300 por producto.
- SKU: `VST-014-M-NEG`. Si no se envía `skuBase`, se genera (`VES-0001`).
- Código de barras: **EAN-13 interno** `20` + correlativo de 10 dígitos + verificador.
  El rango GS1 20–29 está reservado para uso dentro de la tienda: no choca con códigos de
  fábrica y cualquier lector lo reconoce.
- El stock inicial entra como movimiento `initial` en el kardex (no se escribe directo).
- `POST /products/:id/variants` agrega combinaciones nuevas (p. ej. llegó un color) y
  omite las existentes.

`GET /products/:id` devuelve producto, atributos usados y variantes con stock por sucursal:
justo lo que necesita la matriz talla × color de la app.

## Importación masiva

```json
POST /catalog/import
{ "branchId": "…", "rows": [
  { "name": "Polo básico", "category": "Polos", "priceCents": 4990, "costCents": 2000,
    "options": { "Talla": "M", "Color": "Blanco" }, "quantity": 10 }
]}
```

- **La app lee el Excel en el dispositivo** (SheetJS en Flutter web o un paquete en móvil) y
  envía JSON. El servidor no parsea archivos binarios: menos superficie de ataque.
- Una fila = una variante; se agrupan por `skuBase` o, si no hay, por nombre.
- **Todo o nada**: se validan todas las filas y se devuelven todos los errores juntos
  (`{ row, message }`), más útil que corregir uno por uno.
- Atributos, valores y categorías que no existen se crean solos.
- Máximo 2000 filas por envío.

## Búsqueda para el POS

`GET /variants/lookup?code=…&branchId=…` busca por código de barras o SKU exacto y devuelve
precio efectivo, si se puede vender y el stock en la sucursal. Es lo que se llama al escanear.

## Endpoints

```
GET/POST /attributes        PUT /attributes/:id
GET/POST /categories        PATCH /categories/:id
GET /products?search=&categoryId=&active=&branchId=&page=&pageSize=
POST /products              GET/PATCH /products/:id
POST /products/:id/variants PATCH /variants/:id
GET /variants/lookup        POST /catalog/import
```
