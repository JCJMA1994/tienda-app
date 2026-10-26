# 14 · Fotos de producto, clientes y datos del ticket

## Fotos de producto

```
POST   /products/:id/images[?option=Negro]   cuerpo = la imagen (image/jpeg|png|webp|heic), máx. 10 MB
DELETE /products/:id/images/:imageId
PUT    /products/:id/images/order { ids }    la primera es la portada
GET    /products/:id                         incluye images[] (url, thumbUrl, optionValue)
```

Cada foto se **reprocesa en el servidor** (sharp) y el original nunca se guarda:

| Riesgo | Control |
|---|---|
| Archivo disfrazado (script con `Content-Type: image/jpeg`) | Se revisa la **firma real** de los bytes (probado) |
| Bomba de descompresión | Tope de 50 megapíxeles al decodificar |
| **Ubicación GPS y datos de la cámara** en fotos de celular | Se eliminan todos los metadatos (probado: la WebP final no tiene EXIF) |
| Fotos pesadas que gastan datos | WebP 1200 px (detalle) y 400 px (listas, POS), ~100–200 KB |
| Rutas manipuladas | Claves generadas por el servidor: `t/<tienda>/p/<producto>/<uuid>.webp`; cualquier otra se rechaza |

- Hasta **8 fotos** por producto. Se pueden asociar a un **color** (`option=Negro`) para mostrar
  la foto correcta de cada variante.
- La primera es la **portada**: `products.imageUrl` (miniatura) se actualiza al subir, borrar o
  reordenar, y aparece en la lista de productos y en el POS.
- **Almacén**: `STORAGE_DRIVER=local` (desarrollo; servido en `/media` con `nosniff` y CSP
  `default-src 'none'`) o `s3` (Cloudflare R2 o S3) con un bucket público de solo lectura tras
  `MEDIA_PUBLIC_URL` (p. ej. `media.system-failed-tech.com`). R2 no cobra la salida de datos.

## Clientes

```
GET    /customers?search=        nombre, documento o celular
GET    /customers/:id            ficha + estadísticas (compras, gasto, última visita, talla habitual)
POST   /customers                PATCH /customers/:id
DELETE /customers/:id            anonimizar (permiso settings.manage)
```

- Permisos nuevos `customers.read` / `customers.write` (dueño, encargado y vendedor).
- **Se crean solos**: una venta con boleta o factura identificada (DNI/RUC/CE) busca el cliente
  por documento o lo crea con el nombre del comprobante. En el POS también se elige o crea a
  mano (`customerId` en la venta).
- **Datos personales (Ley 29733)**: lo mínimo; cumpleaños sin año (`MM-DD`, no expone la
  edad); permiso de **WhatsApp explícito**, con fecha y registro en la auditoría; **derecho de
  cancelación**: anonimizar borra nombre, documento, contacto y notas, y conserva las ventas
  (registro contable) sin datos personales. El documento queda libre por si vuelve.
- Un documento = un cliente por tienda (índice único).

## Datos para imprimir

`GET /sales/:id` incluye `store` (nombre, razón social, RUC, dirección fiscal y de la sucursal)
y `customer`. Los comprobantes traen `hash` y `qr` (cadena del OSE) para la **representación
impresa** que pide SUNAT.

## Pruebas

`test/images-customers.spec.ts`: reproceso sin metadatos, firma falsa, permisos, portada y
orden, borrado del archivo, tope de 8; clientes con validación, estadísticas, talla habitual,
datos del ticket y anonimización.
