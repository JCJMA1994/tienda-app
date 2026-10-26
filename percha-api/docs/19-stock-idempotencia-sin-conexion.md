# 19 · Stock: análisis de movimientos, idempotencia, correlativos y POS sin conexión

## Una sola puerta para el stock

Todo cambio de stock pasa por `InventoryService.apply()`, que en la misma transacción:
1. bloquea la fila de stock (UPDATE condicional, en orden por variante → sin interbloqueos);
2. rechaza bajar de cero (salvo que la tienda lo permita);
3. escribe el movimiento en el **kardex inmutable** con el saldo resultante.

## Matriz de movimientos

| Operación | Movimiento | Sube/baja | Qué impide aplicarla dos veces |
|---|---|---|---|
| Crear producto / importar | `initial` | + | Transacción única; importación todo o nada |
| Venta | `sale` | − | **Idempotency-Key** + índice único por operación |
| Anular venta | `sale_void` | + | Estado (solo una venta `completed` se anula) + índice único |
| Devolución | `return_in` | + | Idempotency-Key + `returned_quantity ≤ quantity` (UPDATE condicional) + índice |
| Cambio (prenda que sale) | `exchange_out` | − | Idempotency-Key + índice |
| Recepción de compra | `purchase_receipt` | + | Idempotency-Key + no recibir más de lo pedido + índice |
| Ajuste por variación | `adjustment` | ± | Idempotency-Key |
| Ajuste por conteo | `adjustment` | ± | Idempotente por naturaleza (fija el conteo) + Idempotency-Key |
| Enviar transferencia | `transfer_out` | − origen | Idempotency-Key + índice |
| Recibir transferencia | `transfer_in` | + destino | Estado `in_transit` (bloqueo de fila) + índice |
| Cancelar transferencia | `transfer_in` | + origen | Estado; recibir y cancelar se excluyen |
| Apartar | `layaway_reserve` | − | Idempotency-Key + índice |
| Entregar / cancelar apartado | `layaway_release` | + | Estado `open` (bloqueo) + índice |
| Venta sin conexión con faltante | `adjustment` (`sale_offline`) | + | Ligado a la venta (índice único) |

**Índice único** `stock_movements_once_per_operation_uq` (tenant, tipo de referencia, id de
referencia, variante, tipo): aunque un error de programación llamara dos veces a `apply`
para la misma operación, la base rechaza el segundo movimiento (probado).

**Integridad verificable**: `GET /v1/inventory/integrity` compara el stock de cada variante y
sucursal con la suma de su kardex. Debe dar `ok: true`; la prueba también confirma que
detecta un stock alterado por fuera del kardex.

## Idempotencia

Cabecera `Idempotency-Key: <uuid>` en ventas, devoluciones, transferencias, recepciones,
ajustes, apartados (crear y abonar), gift cards y pedidos del catálogo público.

- La clave se registra **dentro de la transacción de la operación** (no en un interceptor):
  o quedan ambas o ninguna. No existe la ventana "se aplicó pero no se guardó la clave".
- **Reintentos simultáneos** con la misma clave: Postgres hace esperar al segundo hasta que
  el primero termina; si confirmó, responde la misma venta; si falló, el segundo la aplica.
  Probado con tres envíos en paralelo: una sola venta.
- Misma clave con **otro contenido** → `409 IDEMPOTENCY_KEY_REUSED` (no es un reintento).
- La respuesta de una repetición es el recurso actual con `replayed: true`. Los códigos de
  vale (que se muestran una sola vez) no se vuelven a entregar.

## Correlativos

`nextNumber()` hace un UPSERT que **bloquea la fila del contador hasta el fin de la
transacción**:
- sin repetidos aunque haya ventas simultáneas (probado);
- **sin huecos**: si la operación falla (p. ej. stock insuficiente), el incremento se revierte
  con ella (probado: números 1…N contiguos tras un fallo);
- los comprobantes SUNAT usan un contador por serie, con la misma garantía;
- las ventas sin conexión reciben su número **al sincronizar**: nunca hay dos dispositivos
  con el mismo número ni números "reservados" que se pierdan.

## POS sin conexión

- `GET /v1/inventory/snapshot?branchId=…`: variantes activas con precio, códigos y stock,
  para buscar y vender sin internet.
- La venta guardada sin conexión se envía con `offline: { occurredAt }` y **la misma clave** del
  intento original: si aquel llegó al servidor y solo se perdió la respuesta, se reconoce
  como la misma venta (`offline` no entra en la huella; probado).
- `occurredAt` define la fecha de la venta (reportes) y del comprobante. Máximo 72 h y sin
  fechas futuras (`OFFLINE_TOO_OLD`, `OFFLINE_CLOCK`).
- **Si al sincronizar falta stock** (otro dispositivo vendió la última unidad, o el conteo
  estaba mal): la prenda ya salió, así que la venta se registra y antes se agrega un **ajuste
  automático explícito** por la diferencia, con su motivo en el kardex, y se avisa a quien
  repone para que cuente. Nunca queda stock negativo oculto (probado).
- Si la caja está cerrada al sincronizar, la venta espera en la cola hasta que se abra.

## Correcciones tras la revisión

- **Vendedor real**: la venta sin conexión lleva `offline.sellerMembershipId` (quien vendió en
  el equipo). Si al sincronizar está otra persona (cambio de usuario con PIN), la venta queda
  igual a nombre de quien la hizo, siempre que sea un integrante activo con acceso a la
  sucursal; si no se puede verificar, queda quien sincroniza (probado).
- **Limpieza**: `npm run maintenance:run` (diario) borra claves de idempotencia de más de 7
  días: más que las 72 h de una venta sin conexión, así un reintento tardío se reconoce.
- **Catálogo desactivado**: `/c/<enlace>` responde una página 404 legible, no un JSON.
