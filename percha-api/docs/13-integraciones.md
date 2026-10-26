# 13 · Apachiy, WhatsApp, recuperación de contraseña y verificación en dos pasos

## Análisis de Apachiy (apachiy.mytems.cloud)

API REST con token Bearer (`myt_live_…`) y respuestas `{ success, data, request_id }`.
Errores: `{ success:false, error:{ code, message } }` con 401, 403, 422 y 429.

| Servicio | Endpoint | Uso en Percha |
|---|---|---|
| DNI | `GET /api/v1/consulta/dni/{dni}` | Autocompletar clientes en boletas |
| RUC | `GET /api/v1/consulta/ruc/{ruc}` | Facturas y proveedores |
| Validez de comprobante | `POST /api/v1/consulta/cpe` | **Nuevo**: validar la factura del proveedor al recibir |
| WhatsApp texto / archivo | `POST /api/v1/message/sendtext\|sendmedia/{instancia}` | **Nuevo**: enviar el comprobante al cliente |

Planes: consultas 130/mes gratis, S/ 10 (15 000), S/ 20 (35 000), S/ 40 (120 000);
WhatsApp 100 mensajes/mes gratis, S/ 15/mes por dispositivo ilimitado.

### Cómo se integró

- **Un solo cliente** (`integrations/apachiy.client.ts`): autenticación, tiempos de espera y
  errores tipados (`unavailable` = caído o cupo agotado; `uncertain` = 502 de WhatsApp).
- **DNI/RUC** como una fuente más, en este orden: padrón SUNAT local (gratis) → Apachiy →
  decolecta → peru-consult. Con la caché de 7/180 días, las 130 consultas gratis rinden mucho.
  El estado del RUC a veces llega como **código**: solo se muestra si es texto legible, para no
  dar advertencias falsas (el padrón local sí trae el texto).
- **Validez de comprobantes**: `POST /lookup/cpe` y, al recibir mercadería con
  `supplierInvoice`, una factura **anulada, inexistente o no autorizada** se rechaza
  (`422 SUPPLIER_INVOICE_INVALID`). Si el servicio no responde, se registra como
  `unverified` para no frenar la recepción.
- **WhatsApp por tienda**: cada boutique conecta **su** número (instancia) y **su** token
  (guardado cifrado). El token de consultas es de la plataforma (`APACHIY_TOKEN`).

### Riesgos y cómo se mitigan

| Riesgo | Mitigación |
|---|---|
| Proveedor pequeño y nuevo: puede cambiar o caer | Detrás de interfaces; padrón local y otras fuentes como respaldo; nada se bloquea si no responde |
| Datos personales (DNI) enviados a un tercero (Ley 29733) | Solo se envía el número; se guarda solo el nombre. Revisa sus términos y política de privacidad antes de producción |
| **WhatsApp por instancia vinculada** (el número se vincula como dispositivo escaneando un QR, no es la API oficial de Meta) | Solo mensajes que el cliente pide, nunca masivos. Aviso en la configuración. Para volumen alto, migrar a **WhatsApp Business Platform (Cloud API)** con plantillas aprobadas |
| Mensajes duplicados | Un `502 provider_error` significa "sin confirmación": se marca `uncertain` y **no se reintenta**. Reenviar al mismo número en menos de 10 min exige confirmación (`force`) |
| Token expuesto | Solo en el servidor (Apachiy lo exige: nunca en la app ni el navegador). Cifrado AES-256-GCM |
| SSRF al adjuntar el PDF | Solo se descarga por https desde dominios del OSE, sin redirecciones, con tope de 8 MB; si no, se envía el enlace |
| Registro de mensajes | Número enmascarado (`51•••••321`) y hash para el antiduplicado; nunca el número completo |

## Recuperar contraseña

`POST /auth/password/forgot {email}` → siempre `202` (no revela cuentas). Enlace a
`${APP_URL}/reset?token=…` por correo (Resend), **30 min, un solo uso**, se guarda solo el hash;
pedir otro invalida el anterior. `POST /auth/password/reset {token, newPassword}` cambia la
contraseña, **cierra todas las sesiones** y quita el bloqueo por intentos. No desactiva 2FA.

## Verificación en dos pasos (TOTP)

- RFC 6238 sin dependencias (probado con los vectores oficiales), ±30 s de tolerancia.
- `POST /auth/2fa/setup` → secreto + `otpauth://` · `POST /auth/2fa/enable {code}` → 10 códigos
  de recuperación (se muestran una vez; se guarda su hash) · `POST /auth/2fa/disable` exige
  contraseña **y** código.
- Login con 2FA: devuelve `{ requiresTwoFactor, challenge }` (JWT de 5 min con audiencia
  `percha-2fa`: **no sirve como sesión**, probado). `POST /auth/2fa/verify` con código o código
  de recuperación. Si el usuario tiene varias tiendas, la respuesta trae un desafío ya
  verificado para elegir sin repetir el código.
- Sin atajos: registrar una tienda nueva o aceptar una invitación con una cuenta que tiene 2FA
  también pide el código.
- 5 códigos errados → 15 min de bloqueo.
- **Backoffice**: en producción exige 2FA (`ADMIN_REQUIRE_2FA`, por defecto activo en
  producción).

## Variables nuevas

`APACHIY_TOKEN`, `APACHIY_BASE_URL`, `SECRETS_ENC_KEY`, `RESEND_API_KEY`, `EMAIL_FROM`,
`ADMIN_REQUIRE_2FA`.
