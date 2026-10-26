# 01 · Autenticación y onboarding

## Flujos

```
Registro ──▶ Paso 1: negocio ──▶ Paso 2: atributos ──▶ Inicio
Login ──┬─▶ Inicio
        └─▶ (varias tiendas) Elegir tienda ──▶ Inicio
Abrir la app ──▶ Splash (restaura sesión con /auth/me) ──▶ Inicio o Login
```

- **Restaurar**: si hay tokens guardados se valida con `/auth/me`; si el access venció, el
  interceptor refresca solo. Sin red no se borra la sesión.
- **Varias tiendas**: el login devuelve la lista y la app muestra el selector; la contraseña
  se reutiliza en memoria solo hasta elegir.
- **Sesión expirada**: si el refresh falla, el interceptor avisa al controlador y el router
  lleva al login con el mensaje "Tu sesión terminó".
- **Cerrar sesión**: se borran los tokens locales primero y luego se revoca en el servidor;
  si no hay red, el token expira solo.

## Onboarding

Los pasos 1 y 2 tienen asistente; los demás (catálogo, equipo, primera venta) se completan
usando la app y el progreso lo **calcula la API** desde los datos reales.

- Se puede saltar con "Después" en cualquier paso; la tarjeta "Configura tu tienda" del
  inicio lleva al siguiente paso pendiente.
- El paso de atributos sugiere Talla (XS–XL) y Color, editables. Si los atributos ya
  existen, se muestran como "Configurado" y no se duplican al repetir el paso.
- Solo quien tiene `settings.manage` ve la tarjeta.
