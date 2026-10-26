# 23 · Lector de códigos de barras y QR

## Cámara (`pos/presentation/scanner_page.dart`)

- **Formatos**: EAN-13, EAN-8, UPC-A, UPC-E, Code 128 (las etiquetas de Percha), Code 39 y QR
  (vales y gift cards).
- **Recuadro de lectura**: solo lee lo que está dentro del recuadro, así no toma la etiqueta
  de la prenda de al lado en el colgador.
- **Modo continuo** (`scanContinuous`): la cámara queda abierta y cada lectura se procesa al
  instante, con vibración y un aviso ("+1 Vestido M", "No hay más stock…"). La misma
  etiqueta se cuenta una vez cada 1,5 s (la cámara la lee varias veces por segundo); para dos
  unidades iguales, se vuelve a pasar. Lo usan el **POS** (agregar al ticket) y el **conteo de
  inventario**. El título muestra cuántas se leyeron.
- **Un solo código** (`scanOnce`): vales, devoluciones, recepción de compras.
- Linterna (con su estado), cámara apagada al salir de la app, y un mensaje claro si no hay
  permiso de cámara.
- **Web**: campo para lector USB (escribe el código + Enter), también en modo continuo.

## Lectores USB / Bluetooth

Funcionan como un teclado: el buscador del POS y el del conteo reciben el código y el Enter.
Se limpian los caracteres que agregan algunos lectores (`\r`, tabulaciones, espacios).

## Mismo código, distinta forma

UPC-A (12 dígitos, común en marcas importadas) y EAN-13 con un 0 adelante son el mismo
código: la búsqueda prueba ambos, en el servidor (`catalog/barcodes.ts`) y en la foto local
sin conexión (`core/barcodes.dart`), con las mismas pruebas en los dos lados.

Si en el POS se escanea el QR de un **vale**, se avisa que se usa al cobrar (no se busca como
prenda).

## Permisos

Ejecuta una vez `bash tool/setup_platforms.sh`: crea los proyectos Android/iOS y, en macOS,
agrega a `ios/Runner/Info.plist` los textos de permiso de cámara y fotos (sin ellos iOS
cierra la app al abrir la cámara). En Android, el permiso de cámara lo declara el plugin.
