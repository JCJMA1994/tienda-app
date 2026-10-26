# 13 · Integraciones (Apachiy) y pendientes de seguridad

## En la app

| Función | Dónde |
|---|---|
| **¿Olvidaste tu contraseña?** | Login → enlace por correo (30 min, un solo uso) → `/reset?token=…` |
| **Verificación en dos pasos** | Más → Seguridad. QR para la app autenticadora (siempre sobre blanco, también en modo oscuro), clave manual, 10 códigos de recuperación. Al ingresar se pide el código; "No tengo mi teléfono" usa un código de recuperación |
| **Comprobante por WhatsApp** | Recibo del POS y detalle de venta → celular del cliente. Si ya se envió hace poco, pregunta antes de reenviar |
| **WhatsApp de la tienda** | Más → Configuración (número vinculado en Apachiy + token, guardado cifrado en el servidor) |
| **Factura del proveedor** | Recibir mercadería → serie, número, fecha y total. Se valida en SUNAT al registrar; una anulada no se acepta |
| **DNI y RUC** | Igual que antes (lupa en el POS y en proveedores); ahora también responde Apachiy |

## Bloquear capturas de pantalla (Android)

`SecureScreen` envuelve las pantallas con secretos (QR y códigos de 2FA). Necesita este código
en `android/app/src/main/kotlin/.../MainActivity.kt` (después de `flutter create`):

```kotlin
package com.systemfailedtech.percha_app

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "percha/secure").setMethodCallHandler { call, result ->
            when (call.method) {
                "enable" -> { window.addFlags(WindowManager.LayoutParams.FLAG_SECURE); result.success(null) }
                "disable" -> { window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }
}
```

Sin ese código la app funciona igual (el widget ignora el canal faltante). En iOS no existe un
bloqueo equivalente; la app no muestra secretos en la vista previa de multitarea porque esas
pantallas no se abren solas.

## Push con Firebase (pasos)

El backend ya envía (FCM HTTP v1). En la app falta tu proyecto de Firebase:

1. `dart pub global activate flutterfire_cli && flutterfire configure` (crea
   `firebase_options.dart`, `google-services.json` y `GoogleService-Info.plist`).
2. `flutter pub add firebase_core firebase_messaging`.
3. En `main.dart`: `await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);`
4. Tras iniciar sesión: pedir permiso (`FirebaseMessaging.instance.requestPermission()`),
   leer `getToken()` y enviarlo a `POST /v1/devices {token, platform}`. Al cerrar sesión,
   `DELETE /v1/devices/:token`.
5. Al tocar un push, abrir `message.data['link']` **solo si empieza con `/`** (misma regla que
   la bandeja).

No se agregó a `pubspec.yaml` porque sin esos archivos de configuración la app no compila.
