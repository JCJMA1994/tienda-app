# 11 · Notificaciones

## Qué se notifica y a quién

Se notifica **por rol y sucursal**: llega a quien puede actuar, no a todos.

| Evento | Destinatarios | Enlace |
|---|---|---|
| Transferencia enviada | `inventory.adjust` de la sucursal **destino** (no a quien envía) | `/transfers/:id` |
| Una salida deja una variante en su mínimo o la agota | `inventory.adjust` de esa sucursal | `/products/:id` |
| Comprobante rechazado por SUNAT | `settings.manage` | `/sales/:id` |
| Plan pendiente de pago / tienda en solo lectura | `billing.manage` (dueño) | `/billing` |
| Alguien aceptó una invitación | `team.manage` | `/team` |

- Se crean **dentro de la transacción del evento**: si el evento se revierte, no hay aviso.
- **Antiruido**: el mismo aviso (tipo + enlace + título) sin leer no se repite. El stock bajo
  avisa solo **al cruzar** el mínimo, no en cada venta posterior.
- El enlace es una **ruta de la app**, nunca una URL externa (no sirve para phishing).

## API

```
GET  /notifications?limit=&before=     bandeja de la persona (más nuevas primero)
GET  /notifications/unread-count
POST /notifications/:id/read           solo el destinatario (otro → 404)
POST /notifications/read-all
POST /devices { token, platform }      registrar el dispositivo para push
DELETE /devices/:token
```

## Push (opcional)

- Firebase Cloud Messaging **API HTTP v1** sin SDK: el servidor firma un JWT (RS256) con la
  cuenta de servicio y lo canjea por un token OAuth. Configura `FCM_SERVICE_ACCOUNT_B64`.
- Outbox: `npm run push:run` cada minuto envía las no leídas y aún no enviadas; borra tokens
  de apps desinstaladas.
- **Contenido mínimo** en el push (título y frase); montos y datos de clientes solo dentro de la
  app, con sesión. Un token de dispositivo pertenece al **último** usuario que inició sesión en
  él (tablet compartida del POS): nadie recibe avisos de otro.
- En la app, registrar el dispositivo requiere configurar Firebase (`firebase_messaging` +
  `google-services.json` / `GoogleService-Info.plist`). Mientras tanto, la bandeja funciona por
  consulta periódica.
