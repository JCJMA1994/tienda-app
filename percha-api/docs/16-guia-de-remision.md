# 16 · Guía de remisión electrónica en transferencias

Mover mercadería entre tus propias tiendas también requiere **guía de remisión remitente**
(motivo SUNAT **04**: traslado entre establecimientos de la misma empresa). Si la tienda emite
comprobantes electrónicos, Percha la emite **al enviar** cada transferencia.

## Qué hace falta

| Dato | Dónde |
|---|---|
| RUC de la tienda y razón social | Datos del negocio / Comprobantes electrónicos |
| **Dirección y ubigeo** (6 dígitos INEI) de cada sucursal | Más → Sucursales (`PATCH /branches/:id { address, ubigeo }`) |
| Serie de guías por sucursal de origen (empieza con **T**, p. ej. T001) | Comprobantes electrónicos → series |
| Datos del traslado | Al enviar la transferencia (`shipment`) |

## Datos del traslado (`shipment`)

```json
{ "mode": "private", "lightVehicle": true, "vehiclePlate": "ABC-123",
  "driver": { "dni": "45678912", "firstName": "Diego", "lastName": "Rojas", "license": "Q1234" },
  "weightKg": 1.5, "packages": 1, "startDate": "2026-10-27" }
```

- **Privado** (auto propio, taxi, moto): placa y conductor obligatorios; el **brevete** se puede
  omitir en vehículos livianos (M1/L).
- **Público** (Olva, Shalom…): RUC y razón social de la empresa de transporte (lupa SUNAT).
- Peso bruto en kg (la app sugiere ~0,3 kg por prenda: corrígelo al real) y número de bultos.
- Todo se valida **antes de numerar**: con datos incompletos no se mueve stock ni se consume
  número (probado).

## Cómo se emite

- Igual que los comprobantes: numerada en la transacción del envío (outbox) y enviada al OSE
  después; reintento y consulta previa para no duplicar. Destinatario: la propia empresa.
- Ítems: código (SKU), descripción y cantidad (unidad NIU). Sin precios (la guía no los lleva).
- El PDF que devuelve el OSE debe **acompañar a la mercadería** (en la app: detalle de la
  transferencia → PDF).
- **Cancelar** una transferencia con guía aceptada genera un aviso para **darla de baja en el
  portal del OSE** (la mercadería no se movió).

## Nubefact

`generar_guia` / `consultar_guia`, `tipo_de_comprobante: 7`, `motivo_de_traslado: "04"`,
`tipo_de_transporte` 01/02, fechas DD-MM-YYYY, peso en KGM, puntos de partida y llegada con
ubigeo. **Verifica con la cuenta demo** (serie de prueba TTT1) antes de producción, en
particular cómo indicar el traslado en vehículos M1/L: está en `toGuideJson`
(`nubefact.provider.ts`), el único lugar a ajustar.

## Pruebas

`test/gre.spec.ts`: sin datos del traslado no se envía, ubigeo obligatorio, reglas de transporte
privado/público, guía emitida con la serie de origen y motivo 04, aviso de baja al cancelar y el
JSON de Nubefact.
