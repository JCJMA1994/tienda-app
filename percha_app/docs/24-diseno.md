# 24 · Diseño: minimalista y cálido

## Dirección

Una herramienta para una tienda de ropa: la interfaz se aparta y dejan de competir los
colores con las prendas y sus fotos.

- **Neutros "piedra"** (ligeramente cálidos) en lugar de grises fríos.
- **Acción principal monocroma**: botones en tinta (#171514) sobre hueso en modo claro; en
  hueso (#F5F4F2) sobre tinta en modo oscuro.
- **Un solo color de marca, índigo "iris"** (#4B3FD1 / #B3ABFF), solo para destacar: enlaces,
  promociones, punto de "no leída", estado "disponible". Nunca fondos grandes.
- **Bordes finos en lugar de sombras**; superficies planas; campos con fondo suave.
- **Una familia tipográfica**: Inter para texto e Inter Tight (600, tracking negativo) para
  títulos y el logotipo.
- Estados: éxito verde (#157F3C), alerta terracota (#B93815), con sus versiones oscuras.

## Tokens (`lib/core/theme/tokens.dart`)

| Token | Claro | Oscuro | Uso |
|---|---|---|---|
| ground | #F7F6F4 | #0D0C0B | Fondo de pantalla |
| surface | #FFFFFF | #161514 | Tarjetas, hojas |
| surfaceAlt | #F1F0EE | #201E1C | Campos, chip y nav seleccionados |
| border / borderStrong | #E7E4E0 / #D6D2CC | #2B2826 / #3B3734 | Bordes finos |
| ink / inkSoft / muted | #171514 / #3D3935 / #6B6560 | #F5F4F2 / #D3CFCA / #A39D96 | Texto |
| accent / onAccent | tinta / blanco | hueso / tinta | Botón principal, selección |
| accentInk / accentSoft | #4B3FD1 / #EFEEFB | #B3ABFF / #25223A | Marca: destacar |
| warn / warnSoft | #B93815 / #FDF1EC | #FF9B6B / #2C1810 | Alertas, agotado |
| success | #157F3C | #5FD68B | Confirmaciones |

Todos los pares texto/fondo cumplen **WCAG AA (≥ 4,5:1)**; lo verifica
`test/design_tokens_test.dart` (incluida la regla "la acción principal es monocroma").

## Componentes

- Botones: 50 px de alto, radio 12, sin sombra. Principal = tinta; secundario = borde fino.
- Chips y segmentos: píldora; seleccionado en tinta con texto claro.
- Campos: fondo `surfaceAlt`, borde fino; al enfocar, borde de tinta.
- Barra flotante y riel: el destino activo se marca con fondo `surfaceAlt` y texto tinta.
- Diálogos radio 20, hojas 24, sin elevación.
- Íconos de la app y favicon: percha hueso sobre tinta.

El catálogo en línea, la pantalla de carga web y el manifiesto usan la misma paleta.
