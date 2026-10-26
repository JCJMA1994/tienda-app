# 02 · Punto de venta

## Disposición

- **Tablet (≥ 900 px)**: catálogo a la izquierda, ticket fijo a la derecha (como el mockup).
- **Teléfono**: catálogo y una barra inferior "Ver ticket · 3 prendas · S/ 389.60".

## Flujo de una venta

1. **Caja**: si no hay caja abierta en la sucursal, el POS pide el fondo inicial.
2. **Agregar**: escaneando (cámara o lector USB/Bluetooth) o tocando un producto y eligiendo
   talla/color. Las combinaciones agotadas se ven deshabilitadas.
3. **Ticket**: cantidades, descuento y método de pago. Los totales son una vista previa con la
   misma fórmula de la API (probado en `test/cart_test.dart`).
4. **Cobrar**: en efectivo pide con cuánto paga (botones "Exacto", S/ 50, 100, 200) para
   el vuelto. La app envía solo variantes, cantidades, descuento y pago: **la API pone los
   precios** y responde con el total oficial.
5. **Recibo**: número de venta, total, IGV y vuelto.

## Lector de códigos

El campo de búsqueda trata Enter como "¿es un código exacto?": primero consulta
`/variants/lookup` y, si no existe, busca por nombre. Los lectores USB/Bluetooth escriben el
código y envían Enter, así que funcionan sin configuración. El foco vuelve al campo después
de cada lectura.

## Casos que maneja la API y la app traduce

| Respuesta | Qué hace la app |
|---|---|
| `APPROVAL_REQUIRED` | Pide el PIN del supervisor y reintenta |
| `APPROVAL_INVALID` | Avisa "PIN incorrecto" y lo vuelve a pedir una vez |
| `INSUFFICIENT_STOCK` | Muestra cuántas unidades quedan |
| `CASH_CLOSED` | Pide abrir la caja |

Si el descuento ya supera el límite y el vendedor no tiene permiso, el PIN se pide **antes**
de enviar, para no hacer un viaje de ida y vuelta innecesario.

## Cambio de vendedor y cierre de caja

- **Cambiar (PIN)**: el vendedor ingresa su PIN y la tablet pasa a su sesión; las ventas
  quedan a su nombre. La sesión anterior se revoca para no acumular sesiones abiertas.
  No se permite con un ticket a medias.
- **Cerrar caja**: se ingresa el efectivo contado sin mostrar el esperado (conteo honesto);
  luego se muestra esperado, contado y diferencia.

## Ventas, devoluciones y cambios

Desde el menú del POS o el inicio: **Ventas, devoluciones y cambios** (`/sales`).

- Búsqueda por **número de ticket** (`GET /sales?number=`): el cliente llega con su comprobante.
- El detalle muestra líneas, cuántas unidades ya se devolvieron, pagos y reversos.

### Anular (`/sales/:id`)

Para errores del mismo turno (cobro duplicado, digitación). Pide motivo y, si el rol no tiene
`sales.void`, el PIN de un encargado (con un reintento si el PIN es incorrecto). Si la API
responde `USE_RETURN` (turno cerrado o venta con devoluciones), se indica usar la devolución.

### Devolver o cambiar (`/sales/:id/return`)

Una pantalla en tres pasos:

1. **Qué vuelve**: unidades por línea, con tope en lo que queda por devolver. Se muestra lo
   que pagó por unidad (con su parte del descuento).
2. **Qué se lleva** (opcional): escaneo o búsqueda; si no es un código exacto, se busca por
   nombre y se elige talla/color. Sin prendas nuevas es una devolución con reembolso.
3. **Diferencia**: "Cliente paga", "Devolver al cliente" o cambio parejo, y el método.

La vista previa usa `ReturnDraft`, con la **misma fórmula que la API** (probada con el mismo
caso que el test del backend: vestido con S/ 50 de descuento → vuelve a S/ 139.90 y el
cambio cuesta S/ 50). La API sigue siendo quien decide el monto final.

Requiere caja abierta: una devolución mueve dinero y stock.

## Pendiente

Pagos mixtos (la API ya los acepta), selección de cliente, impresión de ticket y modo sin
conexión.
