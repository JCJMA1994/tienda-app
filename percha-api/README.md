# Percha API

Backend de **Percha**: inventario, POS y compras para boutiques, multi-tenant (SaaS).
Fases 1 a 8 del plan: fundaciones, identidad, catálogo, inventario, ventas/POS, compras, reportes capa SaaS (planes, cobro con Culqi/Stripe y backoffice) y facturación electrónica SUNAT.

**Stack:** NestJS 11 · TypeScript · PostgreSQL 16 (RLS) · Drizzle ORM · zod · Argon2id · Jest

## Arranque local

```bash
cp .env.example .env              # genera un JWT_ACCESS_SECRET propio
docker compose up -d              # Postgres + roles (db/bootstrap.sql)
npm install
npm run db:migrate                # tablas + políticas RLS
npm run start:dev                 # http://localhost:3000/v1
```

## Pruebas

```bash
npm test
```

Corren contra **Postgres real** (no mocks), porque lo más importante que hay que probar
(RLS, FK compuestas, bloqueos de concurrencia) vive en la base de datos. El test recrea la
BD `percha_test` en cada ejecución. Variables opcionales: `TEST_PG_HOST`, `TEST_ADMIN_URL`.

Cobertura actual (191 pruebas en 23 suites): aislamiento entre tiendas, rotación y robo de refresh
tokens, invitaciones, PIN único, matriz talla × color, importación todo-o-nada, compra con
recepción parcial y costo promedio, venta con IGV y vuelto, venta simultánea de la última
unidad, aprobación por PIN, cambio de talla, anulación, cierre de caja, inmutabilidad del
kardex, catálogo de roles, cada número de los reportes el ciclo completo de facturación la emisión de comprobantes electrónicos, transferencias entre sucursales, consulta RUC/DNI, notificaciones y controles de seguridad.

## Documentación

| Doc | Contenido |
|---|---|
| [00-arquitectura](docs/00-arquitectura.md) | Decisiones, módulos, flujo de un request, convenciones |
| [01-fundaciones](docs/01-fundaciones.md) | Multi-tenant con RLS, roles de BD, FK compuestas |
| [02-identidad](docs/02-identidad.md) | Sesiones, roles y permisos, equipo, PIN, onboarding |
| [03-catalogo](docs/03-catalogo.md) | Atributos, variantes, SKU, EAN-13 interno, importación |
| [04-inventario](docs/04-inventario.md) | Kardex, concurrencia, ajustes |
| [05-ventas-pos](docs/05-ventas-pos.md) | Caja, ventas, anulaciones, cambios de talla |
| [06-compras](docs/06-compras.md) | Órdenes de compra, recepciones, costo promedio |
| [07-reportes](docs/07-reportes.md) | Ventas netas, margen, más vendidos, rotación por talla, stock muerto, valorización |
| [08-saas](docs/08-saas.md) | Planes y límites, prueba, gracia y bloqueo suave, Culqi (tarjeta y Yape), Stripe, Plin manual, webhooks, backoffice |
| [09-sunat](docs/09-sunat.md) | Boletas, facturas y notas de crédito vía OSE (Nubefact), outbox, reintentos, reglas SUNAT |
| [10-transferencias-y-consultas](docs/10-transferencias-y-consultas.md) | Transferencias en dos pasos con faltantes, consulta RUC/DNI con caché y advertencias |
| [11-notificaciones](docs/11-notificaciones.md) | Avisos por rol y sucursal, bandeja, antiruido y push FCM |
| [12-seguridad](docs/12-seguridad.md) | Amenazas y controles: RLS, bloqueos por intentos, sesiones, límites, secretos |
| [13-integraciones](docs/13-integraciones.md) | Apachiy (DNI, RUC, validez de comprobantes, WhatsApp), recuperar contraseña, 2FA |
| [14-fotos-y-clientes](docs/14-fotos-y-clientes.md) | Fotos reprocesadas sin metadatos (local o R2), clientes con estadísticas y anonimización, datos del ticket |
| [15-vales-y-apartados](docs/15-vales-y-apartados.md) | Saldo a favor, gift cards, cortesías; apartados con reserva, abonos, entrega y vencidos |
| [16-guia-de-remision](docs/16-guia-de-remision.md) | Guía de remisión remitente (motivo 04) al enviar transferencias, datos del traslado, Nubefact |
| [17-arquitectura](docs/17-arquitectura.md) | Errores de dominio, eventos, límites entre módulos y reglas de arquitectura verificadas |
| [18-catalogo-en-linea](docs/18-catalogo-en-linea.md) | Vitrina pública por enlace, disponibilidad sin stock exacto, pedidos con antispam |
| [19-stock-idempotencia-sin-conexion](docs/19-stock-idempotencia-sin-conexion.md) | Matriz de movimientos, idempotencia, correlativos, integridad y ventas sin conexión |
| [20-reposicion-sugerida](docs/20-reposicion-sugerida.md) | Qué pedir por talla y color según las ventas, agrupado por proveedor |
| [21-promociones](docs/21-promociones.md) | Porcentaje y lleva X paga Y, mismo motor en API y app, cotización antes de cobrar |
| [22-comisiones-caja-conteo](docs/22-comisiones-caja-conteo.md) | Comisiones por vendedora, cierre de caja imprimible, conteo guiado con la tienda abierta |

## Despliegue (resumen)

1. Postgres gestionado (Neon): crear los roles `percha_owner`, `percha_app` y
   `percha_system` (este último con `GRANT percha_owner TO percha_system`).
2. Correr `npm run db:migrate` con `DATABASE_OWNER_URL` en el pipeline, antes de arrancar.
3. La API usa solo `DATABASE_APP_URL` y `DATABASE_SYSTEM_URL`; nunca la del dueño.
4. Crons: `npm run billing:run` cada hora, `npm run einvoice:run` cada 5–15 min `npm run push:run` cada minuto y `npm run layaways:run` a diario, y tu usuario como superadmin con `npm run admin:make -- tu@correo.com`.
5. `npm run build && npm start` en Railway/Render, con `NODE_ENV=production` y
   `CORS_ORIGINS` con el dominio de la web admin.

## Estructura

```
drizzle/              migraciones SQL (0000 tablas, 0001 RLS)
db/bootstrap.sql      roles de BD para desarrollo
scripts/migrate.mjs   aplica migraciones
src/config            entorno validado
src/database          esquema Drizzle, transacciones por tienda, correlativos
src/common            dinero, validación, filtro de errores, usuario actual
src/modules/*         un módulo por dominio
test/                 historias de integración
docs/                 documentación por etapa
```
