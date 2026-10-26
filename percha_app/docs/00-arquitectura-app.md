# 00 · Arquitectura de la app

## Stack

| Pieza | Elección | Por qué |
|---|---|---|
| Estado | Riverpod 2 (sin generación de código) | Providers testeables, sin `build_runner` que frene el ciclo de desarrollo. |
| Navegación | go_router | Redirecciones declarativas según la sesión. |
| HTTP | Dio | Interceptores para token y refresh. |
| Tokens | flutter_secure_storage | Keychain/Keystore; SharedPreferences no es seguro para credenciales. |
| Escáner | mobile_scanner | Cámara; los lectores USB/Bluetooth funcionan como teclado. |

## Estructura (por funcionalidad)

```
lib/
├── core/            config, tema, red, almacenamiento, router, widgets comunes
└── features/
    ├── auth/        data (API, modelos) · application (sesión) · presentation (pantallas)
    ├── onboarding/  datos del negocio y atributos de variantes
    ├── home/        navegación inferior e inicio
    └── pos/         caja, catálogo, ticket y cobro
```

Cada funcionalidad tiene tres capas: **data** (habla con la API y convierte JSON), **application**
(estado y reglas, sin widgets) y **presentation** (pantallas). Las pantallas nunca llaman a Dio
directamente y nunca ven un `DioException`: todo error llega como `ApiError` con el mismo
`code` que devuelve percha-api (`APPROVAL_REQUIRED`, `INSUFFICIENT_STOCK`...).

## Sesión y navegación

`SessionController` es la única fuente de verdad: `SessionRestoring`, `SignedOut`,
`ChoosingTenant` o `SignedIn`. El router **deriva** la pantalla de ese estado; las pantallas
no navegan después de iniciar sesión. Resultado: no existe forma de quedar en una pantalla
privada sin sesión, ni de volver al login con "atrás" estando conectado.

## Refresh de tokens sin cerrar sesiones por accidente

La API rota el refresh token y trata un refresh repetido como robo (cierra todas las sesiones).
Si la app refrescara en paralelo desde cinco peticiones que vencieron a la vez, se
autodestruiría la sesión. Por eso `AuthInterceptor` es un `QueuedInterceptor`: los 401 se
procesan en fila, el primero refresca y los demás detectan que el token ya cambió y solo
reintentan.

## Permisos en la UI

`Me.can('sales.void')` oculta lo que el rol no puede hacer. Es **comodidad, no seguridad**:
quien decide es la API. Un vendedor no ve costos porque la API no se los envía.

## Dinero

Igual que la API: céntimos enteros. `formatCents()` solo al mostrar, `parseCents()` al
leer lo que escribe el usuario (acepta punto o coma).

## Configuración

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000/v1        # emulador Android
flutter build apk --dart-define=API_BASE_URL=https://api.system-failed-tech.com/v1
```
