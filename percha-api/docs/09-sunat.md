# 09 · Facturación electrónica SUNAT

Boletas, facturas y notas de crédito a través de un **OSE/PSE**. Viene con adaptador para
**Nubefact**; otro proveedor se suma implementando `EInvoiceProvider` (`send` y `query`).
Cada tienda usa **su propia cuenta** del OSE (su RUC, su ruta y su token).

## Configuración por tienda (`PUT /einvoice/settings`, permiso `settings.manage`)

```json
{
  "enabled": true,
  "provider": "nubefact",
  "legalName": "ALMA BOUTIQUE S.A.C.",
  "fiscalAddress": "Av. Larco 123, Miraflores",
  "apiUrl": "https://api.nubefact.com/api/v1/<tu-ruta>",
  "token": "<token de Nubefact>",
  "series": [{ "branchId": "…", "boleta": "B001", "factura": "F001", "ncBoleta": "BC01", "ncFactura": "FC01" }]
}
```

- El **token se guarda cifrado** (AES-256-GCM con `EINVOICE_ENC_KEY`, que vive solo en el
  entorno) y **nunca se devuelve**: `GET` solo dice `hasToken`.
- Series por sucursal. Las de nota de crédito empiezan con B o F según lo que modifican.
- Para probar con Nubefact usa su cuenta demo (series FFF1 / BBB1).

`GET /einvoice/status` (cualquier vendedor) le dice al POS si emitir y el tope de boleta
anónima, sin exponer la configuración.

## Cómo se emite: patrón "outbox"

1. **En la transacción de la venta** se valida al cliente, se calcula el IGV por línea, se
   toma el siguiente correlativo de la serie y se guarda el comprobante `pending` con una
   **foto completa** del documento (`payload`).
   - Si la venta falla, el número no se consume: **correlativo sin huecos** (SUNAT y
     Nubefact exigen orden).
   - Dos ventas simultáneas nunca reciben el mismo número (mismo bloqueo que el resto de
     correlativos).
2. **Después del commit** se envía al OSE. En `EINVOICE_DISPATCH=async` (producción) la
   venta no espera al OSE: el POS nunca se traba porque el OSE esté lento o caído.
3. Resultado: `accepted`, `rejected` (no se reintenta; se emite otro comprobante) o, si no
   hubo conexión, `error` con reintento.
4. **Reintentos**: `npm run einvoice:run` (cron cada 5–15 min) o el botón "Reintentar"
   (`POST /einvoices/:id/retry`). Si un documento ya se había enviado, primero se
   **consulta** al OSE: un corte a mitad de camino no genera duplicados.

Las boletas suelen quedar "recibidas" hasta que SUNAT procesa el resumen diario: siguen en
`pending` (enviadas) y el job las consulta hasta que queden aceptadas.

## Reglas que se validan

| Regla | Respuesta |
|---|---|
| Factura sin RUC válido (prefijo + dígito verificador módulo 11) | `400 INVALID_RUC` |
| Factura sin razón social | `400 CUSTOMER_NAME_REQUIRED` |
| Boleta mayor a S/ 700 sin DNI, RUC o CE | `400 DOCUMENT_CUSTOMER_REQUIRED` |
| DNI ≠ 8 dígitos, CE inválido | `400 INVALID_CUSTOMER_DOC` |
| Sucursal sin series | `409 EINVOICE_SERIES_MISSING` |

Sin indicar nada, la venta emite **boleta a "CLIENTES VARIOS"** (si no supera S/ 700).

## Correcciones: siempre nota de crédito

Un comprobante emitido no se edita ni se borra (`percha_app` no tiene `DELETE` sobre la tabla).

| Operación en la tienda | Comprobante |
|---|---|
| Anular venta | NC motivo **01** (anulación de la operación) por el total, copiando los ítems |
| Devolución | NC motivo **07** (devolución por ítem) al precio realmente cobrado |
| Cambio de talla | NC 07 por lo devuelto **+** nuevo comprobante por lo que se lleva (mismo tipo y cliente) |
| Comprobante rechazado | No lleva NC (para SUNAT no existe) |

Una NC se envía solo cuando su comprobante original ya fue aceptado.

## Montos

IGV **por línea** y totales como **suma de líneas**: el OSE valida que cuadren. Valores
unitarios con hasta 10 decimales (lo que admite Nubefact). Tiendas exoneradas (tasa 0) emiten
con tipo de IGV exonerado.

## Antes de producción

- Probar con la **cuenta demo de Nubefact**: formato de fecha, cabecera `Authorization`,
  tipo de documento "-" para clientes varios y códigos de respuesta están en
  `nubefact.provider.ts`, el único archivo a ajustar.
- Configurar `EINVOICE_ENC_KEY` y el cron `einvoice:run`.
- Fuera de alcance por ahora: comunicación de baja, guías de remisión, consulta de RUC/DNI
  para autocompletar nombre, envío del PDF por correo al cliente.

## Pruebas

`test/einvoice.spec.ts` (con OSE simulado): token cifrado, boleta por defecto con IGV por
línea, tope de S/ 700, RUC con dígito verificador, factura, NC por anulación y por devolución,
OSE caído y reintento, rechazo sin NC y correlativos con ventas simultáneas.
