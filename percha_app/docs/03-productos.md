# 03 · Productos e inventario

## Pantallas

| Ruta | Qué hace | Permiso |
|---|---|---|
| `/products` | Lista con búsqueda, filtro "Stock bajo" y paginado | `catalog.read` |
| `/products/:id` | Matriz talla × color, variante seleccionada, kardex | `catalog.read` |
| `/products/new` | Alta con matriz de variantes y stock inicial | `catalog.write` |
| `/products/import` | Importar Excel | `catalog.write` |

## Lista

- **Debounce de 350 ms** en la búsqueda: no se hace una petición por cada letra.
- Si una respuesta llega cuando el usuario ya escribió otra cosa, se descarta (evita que
  resultados viejos pisen a los nuevos).
- Al volver de un detalle se recarga: el stock pudo cambiar por un ajuste.

## Matriz talla × color

Igual que en el mockup: columnas = primer atributo (talla), filas = segundo (color).
Con un solo atributo es una fila; con tres o más, una grilla de combinaciones.

- Naranja = bajo (≤ stock mínimo, o ≤ 2 si no hay mínimo), gris = agotado, "—" = esa
  combinación no existe.
- Al tocar una celda se ve el SKU, el código de barras (seleccionable para copiar), el costo
  promedio (solo si el rol lo puede ver: la API no lo envía a vendedores) y el kardex.
- **Ajustar stock** ofrece dos modos: *Conteo* (escribes lo que hay y el sistema calcula la
  diferencia; lo normal en tienda) y *Variación* (+3, −1). El motivo es obligatorio.
- **Agregar combinaciones**: llegó un color nuevo → se marcan los valores y la API crea solo
  las combinaciones que faltan.

## Alta de producto

Nombre, categoría (se puede crear ahí mismo), precio, costo, temporada y valores por
atributo. La pantalla muestra en vivo las combinaciones resultantes con un campo de stock
inicial para cada una. SKU y código de barras los genera la API.

## Importar Excel

1. La app lee el `.xlsx` **en el dispositivo** (paquete `excel`) y lo convierte en filas JSON.
   El servidor nunca recibe el archivo: menos superficie de ataque y menos carga.
2. `sheet_parser.dart` reconoce columnas sin importar mayúsculas ni tildes (`Nombre`,
   `Precio`, `Categoría`, `Costo`, `Stock`, `SKU`, `Código de barras`). **Cualquier otra
   columna es un atributo** (Talla, Color, Material…). Corrige rarezas típicas de Excel:
   tallas `28.0` → `28`, códigos de barras guardados como número.
3. Primero se muestran los errores locales con su número de fila de Excel. Si no hay, se
   envía; si la API rechaza (todo o nada), sus errores también se traducen a filas de Excel.

El parser es lógica pura y está probado en `test/sheet_parser_test.dart`.
