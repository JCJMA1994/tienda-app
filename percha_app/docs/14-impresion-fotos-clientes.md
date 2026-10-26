# 14 · Impresión, fotos y clientes

## Impresión

Se imprime con el diálogo del sistema (paquete `printing`): un solo camino para Android,
iOS y web, sin código nativo por marca de impresora.

| Qué | Dónde |
|---|---|
| **Ticket** (rollo 58 u 80 mm) | Recibo del POS → Imprimir; detalle de venta → Imprimir ticket/comprobante; opción "Imprimir al cobrar" |
| **Representación impresa** de boleta/factura | Igual que el ticket: tipo y serie-número, RUC y dirección del emisor, cliente, op. gravada e IGV, **QR** con la cadena del OSE y resumen (hash) |
| **Etiquetas de precio** | Detalle de producto → ícono de etiqueta. Cantidad por variante (por defecto, el stock). Nombre, talla/color, precio y **código de barras EAN-13** (el mismo que lee el POS); si el código no es EAN-13 válido, se imprime el SKU en Code 128 |
| **Configuración** | Más → Impresora y etiquetas: ancho de rollo, hoja A4 (3 × 8) o rollo 50 × 25 mm, ticket de prueba |

El contenido del ticket (`buildTicket`) es lógica pura y probada (`test/printing_test.dart`),
separada del PDF: mañana se puede agregar impresión directa ESC/POS por Bluetooth reutilizándola.

**Conectar una térmica**: Android → servicio de impresión del fabricante o uno genérico ESC/POS;
iPhone → AirPrint; web → impresora instalada. Siempre se puede guardar o compartir el PDF.

## Fotos

- Detalle de producto: galería deslizable, miniaturas, **Tomar foto** o **Galería**. Mantener
  presionada una foto → **Usar como portada** o **Borrar**. Si el producto tiene Color, se
  pregunta de qué color es la foto.
- La foto se reduce en el teléfono (2000 px, calidad 85) antes de subir y el servidor la
  reprocesa y le quita la ubicación GPS.
- Portada en la lista de productos y en el POS (miniaturas decodificadas a su tamaño real
  para no gastar memoria).
- **Permisos** (después de `flutter create`): en `ios/Runner/Info.plist` agrega
  `NSCameraUsageDescription` ("Para fotografiar tus productos") y
  `NSPhotoLibraryUsageDescription` ("Para elegir fotos de tus productos"). En Android no hace
  falta permiso extra con `image_picker`.

## Clientes

- Más → **Clientes**: búsqueda por nombre, documento o celular; ficha con compras, gasto,
  última visita, **talla habitual** y cumpleaños; permiso de WhatsApp; historial con acceso a
  cada venta.
- **Alta** con lupa RENIEC/SUNAT; validaciones de DNI, RUC, celular, correo y cumpleaños (MM-DD).
- **POS**: "Agregar cliente" en el ticket. Si el cliente tiene documento, se propone en la
  boleta automáticamente. Las ventas con DNI/RUC crean al cliente solas.
- **Eliminar datos personales** (dueño/encargado): borra los datos y conserva las ventas.
