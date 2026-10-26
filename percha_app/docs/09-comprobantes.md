# 09 · Comprobantes electrónicos (SUNAT)

## Configurar (dueño o encargado)

Menú de cuenta → **Comprobantes electrónicos**:

1. Activar "Emitir comprobantes en cada venta".
2. Razón social y dirección fiscal **tal como figuran en SUNAT**.
3. OSE (Nubefact), **ruta de la API** y **token** de tu cuenta Nubefact. El token se guarda
   cifrado en el servidor y nunca se vuelve a mostrar: solo se puede reemplazar.
4. Series por sucursal (por defecto B001 / F001 / BC01 / FC01).

Abajo, **"Comprobantes que necesitan atención"**: los que no se pudieron enviar (con
reintento), los rechazados y los que SUNAT aún procesa.

## En el POS

- Si la tienda emite, el ticket muestra el comprobante elegido: por defecto
  **"Boleta · Clientes varios"**. Al tocarlo: boleta con DNI/CE/RUC o **factura** con RUC y
  razón social.
- Las reglas de SUNAT se revisan **antes de cobrar**, con la misma lógica que la API
  (`customer_rules.dart`, probado con el mismo RUC que el backend):
  - boleta mayor a S/ 700 → pide identificar al cliente (desaparece "Clientes varios");
  - factura → RUC con dígito verificador y razón social.
- El recibo muestra **Boleta B001-12 · Aceptado** y el botón **Ver PDF**. Si el OSE no
  respondió, la venta igual queda registrada y el comprobante se envía solo después.

## En el detalle de una venta

Sección **Comprobantes**: boleta/factura y notas de crédito (anulación o devolución), con su
estado, PDF y botón **Reintentar** si quedó sin enviar. Anular, devolver o cambiar una
prenda genera la nota de crédito correspondiente automáticamente.
