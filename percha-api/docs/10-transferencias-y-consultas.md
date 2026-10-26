# 10 · Transferencias entre sucursales y consulta RUC/DNI

## Transferencias

```
POST /transfers                 enviar (sale del origen → en tránsito)
POST /transfers/:id/receive     recibir en el destino lo que llegó
POST /transfers/:id/cancel      cancelar en tránsito (vuelve al origen)
GET  /transfers?status=&branchId=     GET /transfers/:id
```

Permisos: `inventory.adjust` para enviar/recibir/cancelar, `inventory.read` para ver.

- **Dos pasos, como en la realidad.** Al enviar sale el stock del origen (`transfer_out`) y
  queda **en tránsito**: no está disponible en ninguna sucursal, así nadie vende dos veces la
  misma prenda. Al recibir entra al destino (`transfer_in`) **lo que realmente llegó**.
- **Faltantes**: si llega menos, se registra por ítem (`missing`) y queda en la auditoría
  como `transfer.received_with_shortage`. No se puede recibir más de lo enviado.
- **Todo o nada**: si falta stock de una prenda, no se envía nada (misma regla que la venta).
- **Por sucursal**: quien envía debe tener acceso al origen; quien recibe, al destino. Un
  miembro con sucursal fija ve lo que envió y lo que le llega.
- **Costo**: viaja con el costo promedio del momento del envío; las transferencias no
  cuentan como venta en los reportes.

## Consulta RUC y DNI

```
GET /lookup/ruc/:numero   → { ruc, name, address, status, condition, warnings[] }
GET /lookup/dni/:numero   → { dni, name }
```

### Fuentes (en orden) y su costo

| Fuente | RUC | DNI | Costo | Notas |
|---|:-:|:-:|---|---|
| **Padrón reducido SUNAT** (local) | ✓ | | **Gratis**, oficial | Se descarga a diario de SUNAT y se carga con `npm run padron:import`. Sin límites ni dependencia de terceros |
| decolecta.com | ✓ | ✓ | Plan gratuito con límite; luego de pago | `DECOLECTA_TOKEN`. Verifica rutas y campos con tu token |
| peru-consult-api (GitHub, autoalojado) | ✓ | ✓ | Gratis (tu servidor) | `PERU_CONSULT_URL` + `PERU_CONSULT_TOKEN`. Obtiene datos de páginas públicas: puede romperse si cambian; no se actualiza hace años. Solo respaldo |

Se usa la primera que encuentre el documento; si una fuente externa está caída se prueba la
siguiente. **Para DNI no existe una fuente pública oficial y gratuita** (RENIEC cobra su
servicio): con el plan gratuito de decolecta alcanza para una boutique; si se agota, el
vendedor escribe el nombre a mano.

### Padrón SUNAT

```bash
# https://www.sunat.gob.pe/descargaPRR/mrc137_padron_reducido.html → padron_reducido_ruc.zip
unzip padron_reducido_ruc.zip
DATABASE_OWNER_URL=... npm run padron:import -- padron_reducido_ruc.txt --only-active
```

- Lee el archivo en **Latin-1** (como lo publica SUNAT), arma la dirección desde sus columnas
  y carga con **COPY** a una tabla temporal; al final reemplaza el padrón en una transacción
  (nunca se consulta a medias). Probado con una muestra real en el formato de SUNAT.
- **Espacio**: el padrón completo tiene alrededor de 14 millones de filas (varios GB).
  `--only-active` reduce bastante. El plan gratuito de Neon no alcanza; usa un plan con más
  almacenamiento o limita a activos.
- Programa la carga semanal o diaria (los estados "no habido" cambian).

### Comportamiento

- **Se valida antes de consultar** (RUC con dígito verificador, DNI de 8 dígitos): un error de
  tipeo no consume una consulta.
- **Caché global** para fuentes externas (`identity_cache`): RUC 7 días, DNI 180 días; si
  todas caen, se usa el dato en caché aunque esté vencido.
- **Advertencias**: RUC no ACTIVO o contribuyente NO HABIDO.
- **Datos personales** (Ley 29733): del DNI solo se guarda el nombre.
- 30 consultas por minuto por IP. Sin fuente disponible: `503 LOOKUP_UNAVAILABLE` y la app
  permite escribir a mano.
