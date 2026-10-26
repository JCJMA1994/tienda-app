# 12 · Diseño v2: tokens, modo oscuro, barra flotante, notificaciones y seguridad

## Identidad

Percha mantiene su base (índigo de marca, Sora en títulos, Inter en texto) y suma tres
rasgos propios:

1. **Barra flotante**: cápsula translúcida con desenfoque, separada de los bordes, y
   **"Vender" como botón central elevado**. El destino activo se expande en una píldora con
   ícono y etiqueta; los demás muestran solo el ícono (con etiqueta para lectores de
   pantalla). Vibración suave al cambiar de pestaña.
2. **Tarjetas invertidas** para lo importante (avisos, variante seleccionada), que funcionan
   igual en claro y oscuro gracias a los tokens `inverse` / `onInverse`.
3. **Modo oscuro cálido**: fondo #0F0F12 (no negro puro, cansa menos en jornadas largas) y
   acento más luminoso (#8B85FF) con texto oscuro encima.

El canvas de diseño incluye la barra flotante y una variante **Inicio · modo oscuro**.

## Tokens de color (`core/theme/tokens.dart`)

Se nombran por **función**, no por tono: `ground`, `surface`, `surfaceAlt`, `surfaceGlass`,
`border`, `borderStrong`, `ink`, `inkSoft`, `muted`, `accent`, `onAccent`, `accentInk`,
`accentSoft`, `warn`, `warnSoft`, `success`, `inverse`, `onInverse`, `shadow`.

- Cada modo (`PerchaPalette.light` / `.dark`) define todos los tokens.
- El tema de Material se **genera desde los tokens** (`buildPerchaTheme(brightness)`):
  botones, campos, tarjetas, diálogos, hojas inferiores y snackbars cambian solos.
- **Contraste probado**: `test/design_tokens_test.dart` calcula el contraste WCAG de cada par
  texto/fondo en ambos modos (todos ≥ 4.5:1).
- Tokens de forma y movimiento: radios (`field`, `card`, `sheet`, `pill`) y duraciones
  (`fast`, `normal`) con curva de desaceleración.

### Modo oscuro

**Más → Apariencia**: Sistema (por defecto; sigue al teléfono, incluso si cambia de noche),
Claro u Oscuro. Se guarda en el dispositivo. Al cambiar, se reconstruye toda la app para
que cada pantalla lea los tokens del modo activo.

## Notificaciones

- **Campana** en el inicio con contador, y el mismo contador en la barra flotante.
- **Bandeja** (`/notifications`): agrupada por día (Hoy, Ayer, fecha), no leídas resaltadas,
  ícono por tipo, "Marcar todo como leído". Tocar un aviso lo marca y **lleva a donde hay que
  actuar** (transferencia, producto, venta, facturación).
- Solo se navega a **rutas internas**: un enlace externo en un aviso se ignora (probado).
- Sin push configurado, el contador se actualiza cada 60 s y al refrescar.

## Formularios: migración completa

Todos los diálogos de un dato usan ahora `promptMoney` / `promptInt` (mismo sistema que los
formularios: error en línea, teclado correcto, Enter confirma): descuento, efectivo recibido
("Otro monto" con mínimo igual al total), abrir y cerrar caja, stock mínimo, costo en la orden
y en la recepción. El ajuste de stock y aceptar invitación pasaron a `Form` + `AppTextField`.

## Seguridad en la app

- **Bloqueo por inactividad del POS**: a los 3 minutos sin tocar la pantalla, o si la app
  pasa a segundo plano, se cubre con una pantalla que pide PIN. Quien lo ingresa queda como
  vendedor activo; el ticket en curso se conserva. Debajo, nada responde a toques.
- **Cambiar contraseña** (con confirmación y regla de fortaleza): cierra las demás sesiones.
- **Cerrar sesión en todos los dispositivos**, para un teléfono perdido.
- Los bloqueos por intentos del servidor se muestran con su mensaje ("Vuelve a intentar en
  15 min").
