# 10 · Transferencias y consulta RUC/DNI

## Transferencias entre sucursales (`/transfers`)

Desde el inicio → **Transferencias entre sucursales** (permiso `inventory.read`; enviar y
recibir requieren `inventory.adjust`). Aparece el botón **Enviar** cuando hay dos o más
sucursales.

- **Me llegan / Envié**: lo que viene en camino a tu sucursal (primero lo pendiente) y lo que
  mandaste.
- **Enviar**: destino, nota y prendas. El buscador solo muestra productos con stock en tu
  sucursal y cada variante tiene tope en lo disponible. Al enviar, el stock sale de tu
  sucursal y queda **en tránsito** (no se puede vender en ninguna).
- **Recibir**: se asume que llegó todo; con − se marca lo que faltó y se anota qué pasó. El
  faltante queda registrado en la transferencia y en la auditoría.
- **Cancelar** (solo en tránsito y desde el origen): el stock vuelve.
- En el kardex se ven como "Transferencia enviada / recibida".

## Consulta RUC y DNI

- **En el POS**, al elegir boleta con DNI/RUC o factura: el ícono de lupa (o Enter) busca en
  RENIEC/SUNAT y completa nombre o razón social y dirección.
- **En proveedores**: lupa junto al RUC para completar la razón social.
- Si SUNAT indica que el RUC no está activo o el contribuyente no está habido, se muestra un
  **aviso** (no bloquea; decide el vendedor).
- Si el servicio no responde, se avisa y se puede escribir a mano: **nunca bloquea una venta**.
- El carné de extranjería no tiene consulta pública: se escribe a mano.
