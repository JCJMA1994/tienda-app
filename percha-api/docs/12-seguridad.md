# 12 · Seguridad

Resumen de amenazas consideradas y su control. Lo marcado con **nuevo** se agregó en esta etapa.

## Aislamiento entre tiendas

| Riesgo | Control |
|---|---|
| Ver o modificar datos de otra tienda por un bug | **RLS** en Postgres para todo lo de negocio; la API usa un rol sin privilegios de dueño |
| Referenciar un registro ajeno por UUID | **FK compuestas** `(tenant_id, id)` |
| Variable de tienda filtrada entre requests | `set_config(..., true)` local a la transacción |
| SQL crudo en reportes | También pasa por RLS (`withTenant`) |

## Autenticación y sesiones

| Riesgo | Control |
|---|---|
| Robo de contraseñas en BD | Argon2id |
| Enumeración de correos | Mismo mensaje y tiempo de respuesta (hash ficticio) |
| **Fuerza bruta / relleno de credenciales** | **nuevo** Bloqueo por correo: 5 fallos → 15 min (`429 TOO_MANY_ATTEMPTS`, con `retryAfterSeconds`). Aplica aunque el correo no exista. Además, límite por IP |
| **PIN de 4 dígitos adivinable** | **nuevo** Cambio de vendedor: 5 fallos → 5 min por sucursal. PIN de aprobación: 5 fallos → 5 min para quien lo intenta |
| Robo de refresh token | Rotación + detección de reuso (cierra todas las sesiones) |
| **Contraseña comprometida** | **nuevo** `POST /auth/password`: exige la actual, cierra TODAS las demás sesiones. `POST /auth/logout-all` para "perdí el teléfono" |
| **Token de otro sistema con el mismo secreto** | **nuevo** JWT con `alg` fijo (HS256), `iss=percha-api` y `aud=percha-app` verificados |
| Cambios de rol tardan en aplicarse | Access token de 15 min; el refresh relee la membresía |

Los fallos se cuentan en `auth_attempts` con el pool de sistema y en **su propia
transacción**: aunque la operación haga rollback, el intento queda registrado.

## Autorización

- Permisos granulares en cada endpoint (guard global, seguro por defecto: `@Public()` explícito).
- Sucursal fija respetada en ventas, inventario, compras y transferencias.
- Backoffice: superadmin verificado **en la BD en cada request**.
- Notificaciones: cada persona solo lee y marca las suyas.

## Entrada y salida

| Riesgo | Control |
|---|---|
| Datos inválidos | zod en cada endpoint (mismos límites en la app) |
| **Cuerpos gigantes (DoS)** | **nuevo** Tope de 2 MB; responde `413` |
| **Abuso por volumen** | **nuevo** Límite global por IP (300/min) + límites estrictos en login, PIN, cambio de contraseña y consultas RUC/DNI. Webhooks exentos (las pasarelas reintentan en ráfaga) |
| Errores que filtran internos | Filtro global: mensajes genéricos; nunca stack traces al cliente |
| Cabeceras | helmet en la API; CSP propia en páginas de pago; CORS con orígenes explícitos en producción |

## Pagos, comprobantes y secretos

- Webhooks verificados (HMAC en Stripe; *fetch-back* en Culqi) e idempotentes.
- La tarjeta nunca toca el servidor (Culqi.js tokeniza); enlaces firmados con vencimiento.
- Tokens de OSE de cada tienda **cifrados** (AES-256-GCM); la clave solo en el entorno.
- Kardex, auditoría y comprobantes: sin `UPDATE`/`DELETE` para la API.
- Pasarelas y OSE simulados **impiden arrancar** en producción.

## En la app

- Tokens en Keychain/Keystore (en web, almacenamiento cifrado del navegador + CSP).
- **nuevo** **Bloqueo por inactividad del POS**: tras unos minutos sin uso, la tablet pide PIN
  para seguir (nadie vende a nombre de otro si el vendedor se aleja).
- **nuevo** Cambiar contraseña y cerrar sesión en todos los dispositivos desde "Más".
- Validación local idéntica a la del servidor; la API siempre vuelve a validar.

## Operación recomendada

- `npm audit` y actualización de dependencias en el CI; Dependabot/Renovate en GitHub.
- Secretos en el gestor del hosting (nunca en el repositorio); rotar `JWT_ACCESS_SECRET`
  invalida todas las sesiones de acceso.
- Respaldos automáticos de la BD y prueba de restauración periódica.
- Hecho: recuperación de contraseña por correo, 2FA (obligatorio para el backoffice en
  producción) y bloqueo de capturas en pantallas con secretos. Ver `13-integraciones.md`.
- Pendiente: *certificate pinning* en la app y llave de seguridad (WebAuthn) para superadmin.
