# 17 · Arquitectura de la app

Refactorización de los puntos 6 y 7 del análisis (sin cambios visibles para el usuario).

## Capas por funcionalidad

```
features/<x>/
  data/          API y modelos tipados (único lugar que habla HTTP)
  application/   lógica pura y controladores (Riverpod)
  presentation/  pantallas: dibujan y piden acciones
```

- **Ninguna pantalla usa el cliente HTTP**: lo verifica `test/architecture_test.dart`.
  Se movieron `MessagingApi` a `messaging/messaging_api.dart`, y el cambio de contraseña y
  "cerrar todas las sesiones" al `SessionController`.
- **Controladores** (`AsyncNotifier`) para pantallas con acciones: `LayawayController`
  (abonar, entregar, cancelar) y `TransferController` (recibir, cancelar). La pantalla llama
  `ref.read(layawayProvider(id).notifier).pay(…)`; el controlador llama a la API, actualiza su
  estado y refresca la lista.
- **Modelos tipados**: `Layaway` y `CustomerDetail` ya no exponen el JSON (`raw`).

## Una sola forma de ejecutar acciones: `ActionRunner`

`core/widgets/action_runner.dart`. Se mezcla en el `State` y da `busy`, `error`,
`runAction(…)` y `snack(…)`:

```dart
await runAction(() => ref.read(sessionProvider.notifier).login(email, pass));
await runAction(() => api.cancel(id), success: 'Cancelada', errorAsSnack: true);
```

Evita el doble toque, convierte el error en un mensaje legible y apaga el indicador aunque
falle. Ya lo usan **20 pantallas y diálogos**: login, registro, invitación, recuperar y cambiar
contraseña, verificación en dos pasos (ingreso y activación), equipo, apertura de caja,
bloqueo del POS, recepción de compras, apartados, transferencias, devoluciones, sucursales,
clientes y verificación de vales. Con `describeError` cada pantalla puede dar su propio mensaje
para errores conocidos (p. ej. "Abre la caja…").

Quedan con su propio manejo, a propósito:
- **Cobro del POS** (`ticket_panel.dart`): reintenta una vez si falta la aprobación por PIN.
- **Importación de Excel**: muestra los errores de la API fila por fila.

## Catálogos únicos

`core/catalogs.dart` (`Labels.paymentMethods`, `Labels.moneyMethods`): las etiquetas de medios
de pago estaban copiadas en 3 archivos.

## Pantallas más chicas

Partidas con `part` (mismo archivo lógico, clases privadas intactas):

| Antes | Después |
|---|---|
| `product_detail_page.dart` 574 | 155 + matriz de stock, panel de variante, selector de combinaciones |
| `pos_page.dart` 511 | 142 + barra, apertura de caja, catálogo |
| `transfers_pages.dart` 506 | 116 + nueva transferencia, detalle |
| `team_page.dart` 501 | 127 + integrantes, invitaciones, roles |

Regla verificada: **ningún archivo de `lib/` supera 500 líneas**.

## Reglas verificadas en cada `flutter test`

1. Las pantallas no importan el cliente HTTP ni Dio.
2. La lógica pura (dinero, validadores, reglas de cliente SUNAT, contenido del ticket,
   etiquetas) no importa Flutter ni Riverpod.
3. Ningún archivo supera 500 líneas.

## Capa de dominio y modelos sin dependencias

- `features/pos/domain/checkout.dart`: reglas del cobro (reparto vale + otro medio, efectivo a
  cobrar, vuelto, billetes sugeridos), con pruebas en `test/checkout_test.dart`. La API y el
  ticket la usan; la pantalla solo pregunta.
- **Modelos separados de la API**: `sales_models.dart` y `einvoice_models.dart` no importan
  red ni Riverpod (`sales_api.dart` y `einvoice_api.dart` los reexportan, así que nada más
  cambió). El contenido del ticket quedó libre de dependencias transitivas.
- La prueba de arquitectura ahora sigue las importaciones **transitivas** de la lógica pura y
  de todo lo que esté en una carpeta `domain/`.

## Caso de uso del cobro (`CheckoutController`)

`pos/application/checkout_controller.dart` decide el flujo: comprobante válido → vale y medio
para el resto → efectivo y vuelto → aprobación del descuento → registrar (con un reintento si el
PIN falló). Lo que necesita preguntar llega como **funciones** (`CheckoutPrompts`): la pantalla
pone los diálogos, el controlador no conoce widgets. Devuelve `CheckoutDone`,
`CheckoutCancelled` o `CheckoutFailed(mensaje)`, y su estado es "cobrando" (evita doble cobro).

Así el cobro se prueba **sin pantalla ni servidor** (`test/checkout_controller_test.dart`):
qué se pregunta, en qué orden y qué pasa si se cancela.

`DocumentChoice` y las reglas de cliente SUNAT pasaron a `einvoice/domain/`.

## Dirección de las capas

Nueva regla verificada: `domain/` no importa `data/`, `application/`, `presentation/` ni
Flutter; `application/` no importa `presentation/`.
