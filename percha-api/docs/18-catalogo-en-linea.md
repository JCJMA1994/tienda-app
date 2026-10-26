# 18 · Catálogo en línea (vitrina pública)

## Rutas

| Ruta | Acceso | Para qué |
|---|---|---|
| `GET /c/:slug` | público | Página del catálogo (HTML liviano, sin frameworks) |
| `GET /v1/public/catalog/:slug` | público | Tienda + productos publicados con disponibilidad |
| `GET /v1/public/catalog/:slug/products/:id` | público | Fotos y variantes con disponibilidad |
| `POST /v1/public/catalog/:slug/orders` | público | Pedido `{ name, phone, note?, items }` |
| `GET/PUT /v1/catalog/settings` | `settings.manage` | Activar, slug, WhatsApp, sucursal de stock, descripción |
| `PUT /v1/catalog/products/:id/published` | `catalog.write` | Publicar / ocultar |
| `GET /v1/catalog/orders[/:id]` | `sales.read` | Pedidos |
| `POST /v1/catalog/orders/:id/status` | `sales.create` | contactado · atendido · cancelado |
| `POST /v1/catalog/orders/:id/customer` | `customers.write` | Crea o reutiliza (por celular) la ficha del cliente |

## Qué se expone y qué no

- Solo productos **publicados y activos**. Nunca costos, stock exacto, ids de tienda ni datos
  del equipo (probado buscando esos campos en las respuestas).
- Disponibilidad en tres niveles: `available` (> 3), `few` (1–3), `out` (0), del stock de una
  sucursal o de todas.
- El slug se resuelve con el pool de sistema; **todo lo demás se lee con RLS de esa tienda**.
- Slug: 3–40 caracteres `[a-z0-9-]`, palabras reservadas (`admin`, `api`, …) y único entre
  tiendas (`409 SLUG_TAKEN`).

## La página pública

- Datos como JSON escapado (`<` → `\u003c`) dentro de `<script type="application/json">`, y
  todo se pinta con `textContent`/`createElement`: el nombre de una tienda con HTML no se
  ejecuta (probado).
- **CSP con nonce** por respuesta: solo corre el script de la página; `connect-src 'self'`,
  `frame-ancestors 'none'`, sin formularios externos.
- Etiquetas **Open Graph** (título, descripción, foto): vista previa al compartir en WhatsApp.
- Carrito en `localStorage` (no hay datos sensibles), modo oscuro automático, objetivos
  táctiles ≥ 44 px.
- Una prueba compila el JavaScript de la página para detectar errores de sintaxis.

## Pedidos

- No reservan stock (un pedido falso no bloquea prendas). Se rechazan prendas ocultas o
  agotadas.
- Antispam: **5 pedidos por IP cada 10 minutos**, campo trampa para bots, máximo 20 líneas y
  5 unidades por prenda.
- Precio guardado como referencia; el real se fija al apartar o vender.
- Evento `catalog.order_received` → notificación a quien vende en la sucursal.
- La respuesta trae un enlace `wa.me` con el pedido redactado para que el cliente escriba.
