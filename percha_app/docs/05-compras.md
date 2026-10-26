# 05 · Compras y recepción

## Pantallas

| Ruta | Qué hace | Permiso |
|---|---|---|
| `/purchases` | Órdenes filtradas: Por recibir (por defecto), Borradores, Cerradas, Todas. Proveedores desde el ícono del camión | `purchasing.read` |
| `/purchases/new`, `/:id/edit` | Crear orden o editar un borrador | `purchasing.write` |
| `/purchases/:id` | Detalle, progreso de recepción, confirmar, cancelar, historial de recepciones | `purchasing.read` |
| `/purchases/:id/receive` | Contar lo que llegó | `purchasing.receive` |

El rol **Almacén** puede ver y recibir, pero no crear órdenes: la matriz de la API se
respeta también en el router (`_allowed`), aunque quien decide es la API.

## Crear una orden

1. Proveedor (se puede crear ahí mismo) y fecha estimada de llegada.
2. **Agregar**: buscar un producto y escribir cuántas unidades pedir de cada combinación.
   A diferencia del POS, aquí se ven también las **agotadas**, que son justamente las que se
   reponen; cada fila muestra cuánto hay hoy. El costo se precarga con el del producto y se
   puede ajustar por línea.
3. **Guardar borrador** (editable) o **Confirmar pedido** (queda como compromiso con el
   proveedor y ya no se edita, igual que en la API).

`PoDraft` fusiona la misma variante en una sola línea, porque la API exige una por variante.

## Recibir mercadería

Pensado para el momento de desempacar:

- **Escanear cada prenda** (cámara o lector USB/Bluetooth): suma uno a su línea. Si la prenda
  no es de esa orden o su línea ya está completa, lo avisa sin sumar.
- **Recibir todo lo pendiente** con un toque, para cuando el proveedor es de confianza.
- **Costo de factura**: manteniendo presionada una línea se registra un costo distinto al de
  la orden. Es el dato que usa la API para recalcular el **costo promedio ponderado**.
- Si faltan prendas, se avisa que la recepción será **parcial**: lo pendiente queda en la
  orden y se recibe después.

`ReceiveDraft` limita cada línea a lo pendiente (la API rechazaría recibir de más) y solo
envía el costo cuando difiere del de la orden. Está probado en `test/purchasing_drafts_test.dart`.
