# 11 · Análisis de diseño y rediseño (navegación, inicio y formularios)

## Diagnóstico del diseño anterior

| Problema | Por qué importa |
|---|---|
| Barra con 4 pestañas fijas (Inicio, Productos, Vender, Equipo) iguales para todos | Un vendedor tenía una pestaña "Equipo" casi vacía; un almacenero, "Vender" sin permiso |
| Ventas, compras, transferencias, reportes, facturación y comprobantes repartidos entre botones apilados del inicio y un menú oculto en el ícono de cuenta | Funciones difíciles de descubrir; el inicio crecía como una lista sin jerarquía |
| "Vender", la tarea principal de una boutique, sin diferenciación visual | La acción más frecuente debe ser la más fácil de encontrar |
| Formularios con reglas distintas: algunos con `Form`, otros validando a mano en un banner | Errores lejos del campo, mensajes inconsistentes, se podía escribir texto en montos o 12 dígitos en un DNI |
| Sin llevar al primer error en formularios largos | En "Comprobantes electrónicos" el error podía quedar fuera de pantalla |

## Navegación nueva

Una sola definición (`core/navigation/nav.dart`) alimenta la barra, el riel y "Más".

- **Máximo 5 destinos** (guía de Material 3), **filtrados por permiso**:
  - Dueño / encargado / vendedor: **Inicio · Vender · Productos · Ventas · Más**
  - Almacén: **Inicio · Productos · Movimientos · Más**
- **Vender** va segundo y con **pastilla de acento siempre visible**: es la acción principal.
  Abre el POS a pantalla completa.
- **"Más"** agrupa por **tarea** (no por módulo técnico): Operación (compras, transferencias,
  reportes), Equipo, Configuración (comprobantes, datos del negocio, plan) y Plataforma
  (backoffice, solo superadmin). Incluye la cuenta y "Cerrar sesión" con confirmación.
- **Tablet y web**: riel lateral desde 900 px; **extendido con etiquetas** desde 1200 px.
- Probado en `test/navigation_test.dart` (≤ 5 destinos, por rol, backoffice oculto).

El mockup del canvas se actualizó con la barra de 5 destinos (Inicio, Productos y Equipo,
que ahora vive dentro de "Más").

## Inicio

- Se eliminó la pila de botones. Quedan: avisos que importan (facturación, onboarding),
  **Ventas de hoy** (si ve reportes), **accesos rápidos** y **Stock bajo**.
- **Accesos rápidos por rol** en grilla de 2 (teléfono) o 4 (web): Nueva venta (destacada),
  Recibir mercadería, Transferir, Reportes. Tarjetas grandes: objetivo táctil ≥ 48 px.

## Formularios: un solo sistema

| Pieza | Qué hace |
|---|---|
| `V` (`core/forms/validators.dart`) | Validadores puros y probados: correo, contraseña, DNI, **RUC con dígito verificador**, celular, montos, enteros con rango, URL, series SUNAT, `all([...])` para combinar |
| `F` (`core/forms/formatters.dart`) | Impiden escribir lo inválido: montos con 2 decimales, solo dígitos con tope (DNI 8, RUC 11, celular 9), mayúsculas |
| `AppTextField` (`core/forms/app_form.dart`) | Campo único con teclado, autocompletado del sistema, formateo y tope según el tipo; etiqueta siempre visible; error en línea; validación **al interactuar**; "Siguiente" en el teclado; mostrar/ocultar contraseña |
| `submitForm(key)` | Valida todo y **lleva la vista al primer campo con error** |

Reglas de mensajes: dicen qué hacer ("Ingresa un correo válido"), son cortos y usan **los
mismos límites que la API**, para no aceptar en la app lo que el servidor rechazará.

Formularios migrados: login, registro, datos del negocio, producto, proveedor (con lupa de
SUNAT), invitación al equipo y comprobantes electrónicos. El selector de comprobante del POS
ahora limita los dígitos según el documento.

### Detalles de criterio

- En el **login** solo se exige que la contraseña no esté vacía; las reglas de fortaleza van
  en el **registro** (letras y números, mínimo 8).
- **Costo mayor al precio** no bloquea (liquidaciones existen); el costo indica que solo lo
  ven dueño y encargado.
- El botón de enviar ignora toques mientras guarda: no hay envíos dobles.

## Migración completa

Los diálogos que quedaban se migraron en la etapa siguiente (ver `12-diseno-v2.md`).
