# 07 · Plan y facturación

Ruta `/billing` (también desde el menú de cuenta del inicio). Todos ven el estado; solo
quien tiene `billing.manage` (el dueño) paga, cambia de plan o cancela.

## Qué muestra

- **Estado** en lenguaje simple: prueba (días restantes), al día (próxima factura), pago
  pendiente (hasta cuándo sigue todo funcionando), solo lectura o terminada.
- **Uso del plan**: sucursales, usuarios y productos contra el límite (naranja al 90%).
- **Facturas por pagar** con el botón **Pagar**, **planes** para cambiar y **pagos** hechos.

## Pagar

| Opción | Cómo funciona |
|---|---|
| **Yape** (Culqi) | Abre la página de pago de la API con Culqi Checkout; pagas desde tu app de Yape |
| **Otras billeteras (QR)** (Culqi) | Igual, según los medios habilitados en tu cuenta Culqi |
| **Tarjeta (Stripe)** | Abre Stripe Checkout (útil para tarjetas internacionales) |
| **Plin o transferencia** | Muestra los datos de pago (`--dart-define=PLIN_INSTRUCTIONS=…`); el superadmin lo registra al verificar |

Solo aparecen las pasarelas que el servidor tiene configuradas (`providers` en `/billing`).
El checkout se abre en el navegador (`url_launcher`); **al volver a la app se recarga el
estado** (el pago se acredita por webhook, no desde la app).

**Cobro automático**: "Activar cobro automático" abre una página de la API (enlace firmado de
30 min) con Culqi Checkout solo-tarjeta. Culqi tokeniza en el navegador; la tarjeta nunca
pasa por nuestro servidor. Funciona igual desde el teléfono y desde la web.

## Avisos globales

- **Banner en el inicio** cuando importa: prueba por vencer (≤ 5 días), pago pendiente,
  solo lectura o cancelación programada.
- **Cualquier 402 de la API**, en cualquier pantalla, muestra un aviso con acción directa:
  `PLAN_LIMIT` → "Mejorar plan"; `SUBSCRIPTION_SUSPENDED` → "Ver facturación". Se maneja en un
  solo lugar (`ApiClient.onPaymentRequired` + `rootMessengerKey`), sin tocar cada pantalla.
