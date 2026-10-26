# 04 · Equipo, roles e invitaciones

## Qué ve cada quien en "Equipo"

- **Todos**: "Mi PIN", para cambiar de vendedor en el POS y aprobar operaciones.
- **Con `team.manage`** (dueño, encargado): miembros, invitaciones pendientes, botón
  "Invitar" y la matriz de permisos por rol.

## Reglas reflejadas en la UI (y aplicadas por la API)

- Nadie edita su propio rol ni estado: su fila no se puede tocar.
- Solo se gestiona a quien tu rol puede asignar (un encargado: vendedores y almaceneros).
- Un encargado con sucursal fija solo invita y asigna a su sucursal.
- Desactivar a alguien: sus sesiones dejan de renovarse (hasta 15 min, lo que dura su
  token actual).
- Si un PIN ya lo usa otra persona de la sucursal, la API responde 409 y se muestra el aviso.

La matriz de permisos y los roles que cada quien puede asignar vienen de **`GET /roles`**
(`roles_api.dart`), que la API genera desde la misma matriz que aplican sus guards. Si
mañana cambia un permiso en el backend, la app lo muestra sin tocar código. Se agrupa por
área (Ventas, Catálogo e inventario, Compras, Administración) y se mantiene en memoria
durante la sesión.

## Invitaciones

1. Dueño o encargado ingresa correo, rol y sucursal → la API devuelve un token **una vez**.
2. La app arma `https://app.system-failed-tech.com/invite?token=…` y lo copia para enviarlo
   por WhatsApp o correo. Vence en 72 h y se puede revocar mientras esté pendiente.
3. La persona abre el enlace → `/invite` → pone nombre y contraseña (o su contraseña actual
   si ya usa Percha en otra tienda) → entra directo con su rol.

### Para que el enlace abra la app

Hay que configurar **App Links** (Android) y **Universal Links** (iOS) para el dominio
`app.system-failed-tech.com`:

- Android: `intent-filter` con `autoVerify="true"` y el archivo
  `/.well-known/assetlinks.json` en el dominio.
- iOS: capacidad *Associated Domains* (`applinks:app.system-failed-tech.com`) y el archivo
  `/.well-known/apple-app-site-association`.

Mientras tanto, se puede probar con `adb shell am start -d "https://…/invite?token=…"` o
navegando a `/invite?token=…` en Flutter web. Si quien abre el enlace ya tiene una sesión
iniciada, primero debe cerrar sesión (la app lo lleva al inicio).
