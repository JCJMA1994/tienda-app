# Percha · App (Flutter)

App de Percha para teléfono y tablet: login, onboarding, inicio y punto de venta,
conectada a [percha-api](../percha-api).

## Primer arranque

Este repositorio trae solo el código Dart. Las carpetas nativas se generan una vez:

```bash
flutter create . --platforms=android,ios,web --org com.systemfailedtech --project-name percha_app
flutter pub get
flutter test
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000/v1
```

Opcionales: `--dart-define=INVITE_BASE_URL=https://…/invite` (enlaces de invitación) y
`--dart-define=PLIN_INSTRUCTIONS="Plin al …"` (datos para pagar la suscripción por Plin).

`10.0.2.2` es tu máquina vista desde el emulador de Android. En iOS Simulator usa
`http://localhost:3000/v1`; en un dispositivo físico, la IP de tu PC en la red local.

### Permisos de cámara (escáner)

- **iOS** — en `ios/Runner/Info.plist`:
  ```xml
  <key>NSCameraUsageDescription</key>
  <string>Para escanear códigos de barras de las prendas.</string>
  ```
- **Android** — `mobile_scanner` agrega el permiso solo; revisa que `minSdk` sea 21 o más
  en `android/app/build.gradle`.
- En desarrollo con HTTP (sin TLS), Android requiere `android:usesCleartextTraffic="true"`
  en el `AndroidManifest.xml` de **debug**. Nunca en release.

## Qué incluye esta iteración

| Área | Estado |
|---|---|
| Login, registro, selector de tienda, restaurar sesión, refresh seguro | Listo |
| Onboarding: negocio y atributos (pasos 1–2) | Listo |
| Inicio: progreso del onboarding, accesos rápidos, stock bajo | Listo |
| POS: caja, escaneo, búsqueda, variantes, descuento con aprobación, cobro, vuelto, cambio de vendedor, cierre | Listo |
| Productos: lista, matriz talla × color, ajustes con kardex, alta, importar Excel | Listo |
| Equipo: miembros, roles, invitaciones, PIN, matriz de permisos | Listo |
| Ventas: historial, búsqueda por ticket, anulación con PIN, devoluciones y cambios de talla | Listo |
| Compras: proveedores, órdenes, borradores, recepción por escaneo, costo de factura | Listo |
| Reportes: ventas, margen, más vendidos, rotación por talla, stock sin rotar, valorización | Listo |
| Plan y facturación: estado, uso, pagar con Yape/billeteras (Culqi) o tarjeta (Stripe), Plin manual, cobro automático con tarjeta, avisos de límite y bloqueo | Listo |
| Web admin (misma app compilada para web, navegación lateral) y backoffice de superadmin | Listo |
| Comprobantes electrónicos: boleta/factura en el POS con reglas SUNAT, PDF, reintentos, configuración del OSE | Listo |
| Transferencias entre sucursales (enviar, recibir con faltantes, cancelar) y consulta RUC/DNI en POS y proveedores | Listo |
| Rediseño: navegación por rol (≤ 5 destinos + Más), inicio con accesos rápidos, sistema único de formularios y validación | Listo |
| Diseño v2: barra flotante, tokens semánticos, modo oscuro, notificaciones, bloqueo del POS, cambio de contraseña | Listo |
| Recuperar contraseña, verificación en dos pasos, comprobante por WhatsApp, factura de proveedor validada en SUNAT, bloqueo de capturas | Listo (push: ver doc 13) |
| Impresión de tickets y etiquetas con código de barras, fotos de producto, clientes con ficha e historial | Listo |
| Vales (saldo a favor, gift cards con QR), pago con vale en el POS, apartados con abonos y constancia | Listo |
| Guía de remisión en transferencias, sucursales con ubigeo | Listo |
| Arquitectura: capas data/application/presentation verificadas, controladores, ActionRunner, pantallas < 500 líneas | Listo |
| Catálogo en línea: enlace y QR para compartir, publicar productos, pedidos con WhatsApp y apartado | Listo |
| POS sin conexión (foto local, cola con sincronización) e idempotencia en operaciones de stock y dinero | Listo |
| Reposición sugerida por talla y color, con órdenes de compra en borrador por proveedor | Listo |
| Escala tipográfica como tokens (`PerchaType`) en toda la app | Listo |
| Promociones automáticas (porcentaje, lleva X paga Y) en POS, sin conexión y catálogo | Listo |
| Comisiones por vendedora, cierre de caja imprimible (y corte parcial), conteo de inventario guiado | Listo |
| Lector de códigos: modo continuo, recuadro, UPC/EAN, permisos (`tool/setup_platforms.sh`) | Listo |
| Rediseño minimalista y cálido: paleta piedra, acción monocroma, iris como único acento | Listo |

## Documentación

- [00 · Arquitectura](docs/00-arquitectura-app.md)
- [01 · Autenticación y onboarding](docs/01-auth-onboarding.md)
- [02 · Punto de venta](docs/02-pos.md)
- [03 · Productos e inventario](docs/03-productos.md)
- [04 · Equipo, roles e invitaciones](docs/04-equipo.md)
- [05 · Compras y recepción](docs/05-compras.md)
- [06 · Reportes](docs/06-reportes.md)
- [07 · Plan y facturación](docs/07-facturacion.md)
- [08 · Web admin y backoffice](docs/08-web.md)
- [09 · Comprobantes electrónicos](docs/09-comprobantes.md)
- [10 · Transferencias y consulta RUC/DNI](docs/10-transferencias-y-consultas.md)
- [11 · Análisis de diseño y rediseño](docs/11-diseno-y-ux.md)
- [12 · Diseño v2: tokens, modo oscuro, barra flotante, notificaciones y seguridad](docs/12-diseno-v2.md)
- [13 · Integraciones (Apachiy) y pendientes de seguridad](docs/13-pendientes.md)
- [14 · Impresión, fotos y clientes](docs/14-impresion-fotos-clientes.md)
- [15 · Vales y apartados](docs/15-vales-y-apartados.md)
- [16 · Guía de remisión](docs/16-guia-de-remision.md)
- [17 · Arquitectura de la app](docs/17-arquitectura-app.md)
- [18 · Catálogo en línea](docs/18-catalogo-en-linea.md)
- [19 · POS sin conexión](docs/19-pos-sin-conexion.md)
- [21 · Promociones](docs/21-promociones.md)
- [23 · Lector de códigos](docs/23-lector-de-codigos.md)
- [24 · Diseño](docs/24-diseno.md)

## Pruebas

`flutter test` cubre la lógica pura: carrito (fusión de líneas, límite de stock, IGV con la
misma fórmula que la API, aprobación de descuentos), cálculo de devoluciones y cambios (mismo caso que la API), borradores de compra y recepción por escaneo, lector de Excel, períodos de reportes, opciones de pago por pasarela, reglas de cliente para boleta/factura, validadores y formateadores de formularios, contenido del ticket y etiquetas EAN-13, navegación por rol, contraste WCAG de los tokens en claro y oscuro, enlaces seguros de notificaciones y formato de dinero.
