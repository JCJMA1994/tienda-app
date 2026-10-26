# 19 · POS sin conexión e idempotencia en la app

## Idempotencia

Toda operación que mueve stock o dinero envía `Idempotency-Key` (UUID v4 de `core/ids.dart`):
ventas, devoluciones, transferencias, recepciones, ajustes, apartados y gift cards. Si el
interceptor reenvía la petición tras renovar la sesión, la cabecera viaja igual: la API la
aplica una sola vez. El cobro crea una clave nueva por intento (cambia el PIN de aprobación,
cambia el contenido).

## Vender sin internet

- **Foto local** (`pos/offline/pos_snapshot.dart`): variantes, precios, códigos y stock de la
  sucursal, guardados en el equipo. Se actualiza al abrir el POS, cada 10 minutos y tras
  sincronizar. Sin conexión, la grilla, el selector de talla/color y la búsqueda por código o
  SKU la usan; la caja abierta se recuerda.
- **Cobro**: si la API no responde por falta de red, la venta se guarda en la **cola**
  (`offline_queue.dart`) con la misma clave del intento y la hora real, se descuenta del
  stock local y se ve "Venta guardada · se enviará sola".
- Sin conexión se puede cobrar con **efectivo, tarjeta o Yape/Plin**. Vales y descuentos con
  aprobación necesitan verificarse en el servidor en ese momento: el POS lo indica.
- **Sincronización**: sola cada 30 segundos y con "Sincronizar" en el aviso del POS; de a una
  y en orden. Una venta sale de la cola solo cuando la API la confirma.
- **Rechazadas** (p. ej. más de 72 h): quedan "por revisar" con el motivo; se reintentan o se
  descartan con confirmación. Si la caja estaba cerrada, simplemente esperan.
- El comprobante electrónico se emite al sincronizar, con la fecha real de la venta.

Pruebas: `test/offline_test.dart` (claves, foto local, cola).

## Correcciones tras la revisión

- **La cola no marca como "por revisar" lo que es temporal**: sesión vencida (401), sin
  permiso momentáneo (403), plan impago (402), demasiadas peticiones (429) o error del
  servidor (5xx) se reintentan solos. Solo un rechazo de negocio (datos inválidos, más de
  72 h) pide revisión.
- **No se pierde una venta encolada** mientras la app todavía lee la cola del disco.
- **Cierre de caja**: si hay ventas sin conexión de esa sucursal, primero intenta enviarlas;
  si no puede, no deja cerrar (su efectivo está en ESA caja y si no, sobraría hoy y faltaría
  mañana).
- **La caja abierta se recuerda en el equipo**: el POS sigue funcionando sin internet aunque
  se reinicie la app.
- **Vendedor**: la venta guarda quién la hizo, aunque otra persona sincronice después.
