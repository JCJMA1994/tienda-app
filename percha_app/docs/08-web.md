# 08 · Web admin y backoffice

La **web admin es la misma app Flutter compilada para web**: un solo código para teléfono,
tablet y navegador. En pantallas de 900 px o más la navegación pasa a un **riel lateral** y
el contenido se centra con ancho máximo.

## Publicar en app.system-failed-tech.com

La base web ya está en el repositorio (`web/index.html`, `manifest.json`, íconos, pantalla de
carga y `flutter_bootstrap.js`): **no hace falta `flutter create`**.

```bash
flutter build web --release --no-web-resources-cdn \
  --dart-define=API_BASE_URL=https://api.system-failed-tech.com/v1 \
  --dart-define=INVITE_BASE_URL=https://app.system-failed-tech.com/invite \
  --dart-define=PLIN_INSTRUCTIONS="Plin al …"
# sube build/web a Cloudflare Pages o Netlify y apunta el subdominio app.
```

`--no-web-resources-cdn` sirve CanvasKit desde tu dominio (la CSP de `web/_headers` no permite
cargarlo de gstatic.com). `index.html` y el arranque no se cachean; los recursos sí.

En la API: `CORS_ORIGINS=https://app.system-failed-tech.com` (con credenciales) y, como la
app y la API comparten dominio, la cookie de sesión queda `SameSite=Strict`.

## Sesión en el navegador (cookie HttpOnly)

- La app web envía `X-Client: web`. La API entrega el **refresh token en una cookie
  `HttpOnly`, `Secure`, `SameSite=Strict`, solo para `/v1/auth`**, y no lo pone en el JSON:
  un script inyectado no puede robarlo.
- El access token (15 min) vive **solo en memoria**. Al recargar la página, la primera
  petición renueva la sesión con la cookie. En el almacenamiento del navegador solo queda la
  marca "hay sesión" (no es un secreto).
- Cerrar sesión borra la cookie y la revoca. La app móvil sigue igual (Keychain/Keystore).
- Si algún día la API está en otro dominio (no un subdominio), usa
  `WEB_COOKIE_SAMESITE=none` (exige HTTPS).

## Diferencias en web

- **Lector de códigos**: en lugar de la cámara se abre un campo listo para un **lector USB**
  (escribe el código y Enter) o para tipearlo. El buscador del POS también acepta el lector.
- **Sin conexión**: el POS sigue vendiendo si se corta el internet con la página abierta,
  pero si se recarga sin red no abre. Para trabajar sin conexión, mejor la app del
  celular o la tablet.
- **Capturas de pantalla**: la protección de pantallas con secretos es solo de Android.
- **Notificaciones push**: en web aparecen en la campana (cada minuto); el push del navegador
  requiere configurar Firebase para web.

## Qué cambia en la web

| Función | En la web |
|---|---|
| Escáner con cámara | Funciona en navegadores modernos, solo con HTTPS. Un lector USB funciona como teclado |
| Importar Excel | Funciona (el archivo se lee en el navegador) |
| Pagos (Culqi / Stripe) | Se abren en otra pestaña |
| Tokens | `flutter_secure_storage` en web usa el almacenamiento del navegador cifrado con WebCrypto. **Es menos aislado que Keychain/Keystore**: un XSS podría leerlos. Mitigación actual: CSP estricta y access token de 15 min. Mejora futura: refresh token en cookie `httpOnly` solo para web |

## Cobro automático con tarjeta

Desde **Plan y facturación → Activar cobro automático** (app o web): la API entrega un enlace
firmado de 30 minutos a una página con Culqi Checkout solo-tarjeta. Culqi tokeniza en el
navegador; la tarjeta nunca toca nuestros servidores.

## Backoffice (`/admin`)

Visible en el menú de cuenta solo si `/auth/me` dice `isPlatformAdmin` (y cada endpoint
`/admin` lo vuelve a verificar en la BD). Para darte acceso:
`DATABASE_OWNER_URL=… npm run admin:make -- tu@correo.com` en percha-api.

- **Métricas**: MRR, tiendas por estado, en riesgo (gracia + suspendidas), pruebas por vencer.
- **Tiendas**: búsqueda y filtro por estado; plan, uso, deuda y última venta.
- **Acciones por tienda**: +7 días de cortesía (reactiva si estaba en gracia o suspendida),
  bloqueo duro / desbloqueo, cambio de plan.
- **Facturas** de la tienda y **Registrar pago** para Plin o transferencia, con número de
  operación (queda en la bitácora de la tienda).
- **Correr facturación** a mano (además del cron).
