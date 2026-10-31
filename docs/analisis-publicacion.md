# Análisis del fork de Traccar Manager para publicarlo como "Ridder GPS"

Fecha del análisis: 31 de octubre de 2026.
Commit analizado: `4527a49` (rama `main`, después del cambio de servidor a `https://track.ridder.com.py`).
Upstream comparado: `traccar/traccar-manager` en `32bbc6b` (29 de octubre de 2026).

Resumen en una línea: es la app móvil de Traccar (Flutter), no el servidor. Ya tiene marca parcial de Ridder, pero el fork rompió el puente web↔nativo (push y sesión persistente no funcionan), tiene el keystore de firma con contraseña `password` subido al repo, y con el Flutter estable actual el proyecto Android no compila sin actualizar Gradle/AGP/Kotlin. Conviene rehacer el fork sobre el upstream actual antes de publicar.

---

## 1. Qué es y cómo está hecho

### Framework y versiones

| Dato | Valor |
|---|---|
| Framework | Flutter (Dart). Proyecto creado con Flutter 3.29.3 según `.metadata` |
| Restricción de Dart en `pubspec.yaml` | `^3.7.2` |
| Lo que exige `pubspec.lock` | Dart ≥ 3.10.3, Flutter ≥ 3.38.4 (el lock lo generó upstream con un Flutter más nuevo que el del `.metadata`) |
| Versión de la app | `1.0.0+1` (versionName 1.0.0, versionCode 1) |
| Nombre del paquete Dart | `traccar_manager` |
| Android | Kotlin, AGP 8.9.1, Gradle 8.11.1, Kotlin 2.1.21, Java 11, `minSdk`/`targetSdk`/`compileSdk` delegados al SDK de Flutter, NDK 27.0.12077973 |
| iOS | Swift, CocoaPods (Podfile con `platform :ios, '15.0'`), deployment target 15.0, Xcode `LastUpgradeCheck = 1510` |
| Firebase | Core, Messaging (push), Crashlytics, Analytics. Proyecto `ridder-f7fb3` en los archivos nativos |

### Estructura de carpetas

```
.github/            workflows/analyze.yml (flutter analyze en CI), dependabot, FUNDING (de Traccar)
android/            proyecto Gradle Kotlin DSL; app/src/main (manifest, MainActivity.kt, íconos, estilos,
                    network_security_config.xml); google-services.json; android.keystore y key.properties (!)
ios/                proyecto Xcode "Runner"; Info.plist, entitlements, AppIcon, LaunchScreen, GoogleService-Info.plist,
                    Podfile/Podfile.lock
assets/icon.png     ícono fuente 1024x1024 del que se generan los demás
lib/                código Dart (5 archivos, ~700 líneas)
tool/brand.dart     script de "marca blanca": cambia nombre, package id, versión, URL, genera íconos y keystore
firebase.json       config de FlutterFire (apunta todavía al proyecto de Traccar, ver más abajo)
LICENSE.txt         Apache 2.0 completo
README.md           el README original de Traccar
pubspec.yaml / .lock
```

### Cómo arranca

1. `lib/main.dart`: inicializa Flutter, `Firebase.initializeApp()` (sin opciones explícitas, usa `google-services.json` / `GoogleService-Info.plist`), engancha errores de Flutter a Crashlytics, muestra el diálogo de "calificá la app" (`rate_my_app`) y monta `MaterialApp` con tema claro/oscuro con semilla azul.
2. `lib/main_screen.dart` (`MainScreen`): es la única pantalla real. Abre un `InAppWebView` (paquete `flutter_inappwebview`) con la URL fija del servidor y maneja todo lo nativo alrededor del WebView.
3. `lib/error_screen.dart`: pantalla de "sin conexión" con campo para la URL. En el fork nunca se muestra (ver sección 7).
4. `lib/token_store.dart`: guarda/lee el token de sesión en almacenamiento seguro (`flutter_secure_storage`) y, si se le pide, exige biometría (`local_auth`) antes de leerlo.
5. `lib/firebase_options.dart`: generado por FlutterFire pero **no se usa** (main no lo pasa a `initializeApp`). Sigue apuntando al proyecto Firebase de Traccar (`traccar-manager-app`).

### Pantallas y funciones

La app es un envoltorio nativo de la interfaz web de Traccar (`traccar-web`, React) que sirve el propio servidor. Login, mapa, dispositivos, reportes, geocercas, comandos, configuración, etc. **no están en la app: los dibuja el servidor** dentro del WebView. Lo que sí es nativo:

- **Servidor fijo**: `_lockedUrl = 'https://track.ridder.com.py'`. El fork eliminó la pantalla y la preferencia de "cambiar servidor" que tenía el original.
- **Notificaciones push (FCM)**: pide permiso, obtiene el token y se lo pasa a la web con `updateNotificationToken(...)`; al tocar una notificación abre `/event/<id>`; mientras la app está abierta muestra el aviso en un snackbar y se lo reenvía a la web.
- **Sesión persistente**: la web manda `login|<token>` y la app lo guarda en el almacenamiento seguro; al volver a la pantalla de login la web manda `authentication` y la app devuelve el token (`handleLoginToken`) tras pedir biometría.
- **Descarga de reportes**: intercepta URLs que terminan en `xlsx/kml/csv/gpx`, las baja con el token (`Authorization: Bearer`) y abre la hoja de "compartir" (`share_plus`).
- **Enlaces externos**: cualquier URL de otro dominio se abre en el navegador externo; las URLs de OAuth (con `response_type`, `client_id`, `redirect_uri`, `scope`) también.
- **Deep links**: esquema `org.traccar.manager://` (manifest Android e `Info.plist`); se reescribe al host del servidor.
- **Botón atrás** Android: navega atrás dentro del WebView salvo en `/` o `/login`.
- **Script inyectado**: oculta por DOM el botón de QR/cambiar servidor de la pantalla de login de la web (busca un `<path d="...">` concreto). Es frágil: se rompe si Traccar cambia el ícono o las clases de Material UI.

### Cómo se conecta al servidor

Solo HTTPS a `track.ridder.com.py` dentro del WebView (cookies de sesión las maneja el WebView) más una llamada `http.get` directa con `Bearer` para descargas. No hay API client propio. El puente web→nativo es `window.appInterface.postMessage('cmd|arg')` que la web de Traccar llama si detecta ese objeto; los comandos son `login|token`, `authentication`, `authenticated`, `logout`, `download|base64`, `server|url`. **En el fork ese objeto ya no se inyecta** (ver sección 2 y 7).

---

## 2. Estado del fork

### Qué cambió respecto al original

Base del fork: commit upstream `9fcf90f` "Remove testing doc" (1 de febrero de 2026, versión upstream en ese momento ~6.0). Encima hay 9 commits propios (febrero–abril 2026):

| Commit | Qué hizo |
|---|---|
| `8467282` Cambio de logo | Íconos Android/iOS regenerados desde `assets/icon.png`; borró el ícono adaptativo (`mipmap-anydpi-v26`, `ic_launcher_foreground`); `applicationId` → `com.ridder.manager`; **subió `android/android.keystore` y `android/key.properties`**; cambió `build.gradle.kts` para leer `key.properties` desde la raíz de `android/`; borró `Package.resolved` (SwiftPM) y agregó `Podfile.lock`; `pubspec` `version: 1.0.0+1` |
| `8d40a4d`, `2a72ae7` Cambio de nombre | Nombre visible "Ridder GPS" en manifest, `Info.plist` y `tool/brand.dart` |
| `6ee0240` Cambio de imagen | Movió el ícono a `assets/`, ajustó `brand.dart` |
| `23a958e` Eliminar icono de cambio de servidor | Reescribió `main_screen.dart`: URL fija, quitó `shared_preferences`, quitó la lógica de OAuth redirect, agregó el script que oculta el botón QR |
| `fb6e7ea` Agregar botones desaparecidos | **Eliminó el `UserScript` que inyecta `window.appInterface`** (el puente) y la intercepción de XLSX por Blob; dejó solo el script que oculta el botón |
| `bdfca6e` Configuraciones ios y android | `google-services.json` y `GoogleService-Info.plist` del proyecto Firebase `ridder-f7fb3`; `DEVELOPMENT_TEAM = 2N378K4VZ6` en Xcode; textos de permisos en español |
| `5e6bbbf`, `3828337` Face ID | Intento de forzar biometría y luego revertido; neto: `token_store.dart` casi igual al original |

Consecuencia del commit `fb6e7ea`: la web de Traccar decide si está "dentro de la app" con `window.appInterface || window.webkit.messageHandlers.appInterface` (`src/common/components/NativeInterface.js` de traccar-web). Sin la inyección, la web se comporta como en un navegador común: no manda `login|token` (no hay sesión persistente ni biometría), no manda `authenticated` (la app nunca sube el token FCM al usuario → **no llegan notificaciones push**), y muestra el botón QR que después hay que ocultar a mano con el hack de DOM. El `addJavaScriptHandler('appInterface')` del lado Dart quedó registrado pero nadie lo llama.

### Qué tan atrasado está

El upstream tiene **132 commits** posteriores a la base del fork (febrero → 29 de octubre de 2026) y pasó de la versión 6.0 a `6.2.4+87`. Lo relevante:

- **Toolchain Android**: Gradle 8.11.1 → 9.3.1, AGP 8.9.1 → 9.1.0, Kotlin 2.1.21 → 2.4.0, Java 11 → 17, `compileSdk = 37`, flags `android.builtInKotlin=false` / `android.newDsl=false`. Con el Flutter estable de hoy (3.47.9) **las versiones del fork están por debajo del mínimo que Flutter exige y el build Android falla** (mínimos: Gradle 8.14, AGP 8.11.1, Kotlin 2.2.20, Java 17).
- **iOS**: eliminó CocoaPods y pasó a Swift Package Manager; adoptó `UIScene`/`FlutterSceneDelegate` y `FlutterImplicitEngineDelegate` (requeridos por Flutter reciente con iOS 26 SDK); agregó `NSLocationAlwaysAndWhenInUseUsageDescription`; deshabilitó deep linking automático de Flutter; sube dSYMs a Crashlytics.
- **Firebase**: `firebase_core` 4 → 5, `firebase_messaging` 16 → 17, `firebase_crashlytics` 5 → 6, `firebase_analytics` 12 → 13. Nuevo flujo de push basado en Installation ID (`firebase_messaging_installation_id_enabled`, `_messaging.register()`, "Register push on authentication", "Support old notification flow"). El servidor Traccar nuevo espera ese flujo.
- **Otras dependencias**: `flutter_inappwebview` 6.1 → 6.2.0-beta.3, `flutter_secure_storage` 10 → 11, `share_plus` 12 → 13, `permission_handler` 12 → 13, `app_links` 7.2.
- **Robustez**: validación de URLs (`Safer URL validation`, `Handle invalid URLs`), captura de errores asíncronos con `PlatformDispatcher.onError`, fix de crash del diálogo de calificación, `onReceivedError` más preciso en iOS, `supportZoom: false`.
- **Release**: workflow `release.yml` que compila, firma y publica en Play y App Store desde GitHub Actions con secretos (sin keystore en el repo), y deja de versionar `pubspec.lock` y `Podfile.lock`.

### Recomendación

Sí, traer upstream antes de publicar, y hacerlo **al revés de un merge**: partir del `main` de upstream actual y reaplicar encima la marca Ridder como un parche chico. Motivos: `main_screen.dart` fue reescrito en el fork (el merge sería un conflicto total), el fork rompió el puente, y el toolchain del fork ya no compila. El parche Ridder debería limitarse a:

1. `applicationId`/bundle id, nombre, íconos, Firebase propio (lo que ya hace `tool/brand.dart`).
2. URL por defecto fija (`_getUrl()` devuelve `https://track.ridder.com.py` y se ignora la preferencia) manteniendo el `UserScript` del puente intacto.
3. Para que no aparezca el botón "cambiar servidor", **usar la configuración del servidor** en vez del hack de DOM: la web lo oculta cuando el atributo del servidor `disableChange` está activo (en Traccar: Ajustes → Servidor → atributo "Deshabilitar cambio de servidor"). Así no hace falta ningún script inyectado.

---

## 3. Lo que hay que cambiar para que sea de Ridder (archivo por archivo)

Lo que ya está hecho se marca ✅; lo pendiente ❌. No se modificó nada de esto en este análisis salvo el servidor.

| Archivo | Qué | Estado |
|---|---|---|
| `android/app/build.gradle.kts` | `applicationId = "com.ridder.manager"` | ✅ |
| `android/app/build.gradle.kts` | `namespace = "org.traccar.manager"` → `com.ridder.manager` (el namespace define el paquete de `R` y `BuildConfig`; dejarlo como Traccar funciona pero es confuso y la clase `MainActivity` sigue en el paquete de Traccar) | ❌ |
| `android/app/src/main/kotlin/org/traccar/manager/MainActivity.kt` | Mover a `kotlin/com/ridder/manager/` y cambiar `package` (debe coincidir con el `namespace`) | ❌ |
| `android/app/src/main/AndroidManifest.xml` | `android:label="Ridder GPS"` | ✅ |
| `android/app/src/main/AndroidManifest.xml` | Esquema de deep link `android:scheme="org.traccar.manager"` → esquema propio (p. ej. `com.ridder.manager`) y actualizar `lib/main_screen.dart` (`uri.scheme == 'org.traccar.manager'`) | ❌ |
| `android/app/src/main/AndroidManifest.xml` | Restaurar `com.google.firebase.messaging.default_notification_icon` apuntando a `@drawable/ic_stat_notify` (el fork lo borró; sin él el ícono de la notificación es el genérico/cuadrado blanco) y rediseñar `ic_stat_notify.xml` con la silueta de Ridder | ❌ |
| `android/app/src/main/res/mipmap-*/ic_launcher.png` | Íconos legacy regenerados con el logo Ridder | ✅ |
| `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml` + `drawable/ic_launcher_foreground.xml` | Ícono adaptativo (Android 8+). El fork lo borró; sin él Android recorta el PNG cuadrado en un círculo y Play lo marca como mala práctica. Generar con `flutter_launcher_icons` (`adaptive_icon_background`/`adaptive_icon_foreground`) | ❌ |
| `android/app/src/main/res/values/styles.xml`, `values-night/styles.xml` | Color de fondo del splash (`windowBackground`) con el color de marca; hoy usa el del sistema | ❌ (opcional) |
| `android/app/google-services.json` | Proyecto Firebase `ridder-f7fb3`, paquete `com.ridder.manager` | ✅ |
| `ios/Runner.xcodeproj/project.pbxproj` | `PRODUCT_BUNDLE_IDENTIFIER = com.ridder.manager` (Runner y RunnerTests), `DEVELOPMENT_TEAM = 2N378K4VZ6` | ✅ |
| `ios/Runner/Info.plist` | `CFBundleDisplayName` y `CFBundleName` = "Ridder GPS" | ✅ |
| `ios/Runner/Info.plist` | `CFBundleURLSchemes` = `org.traccar.manager` → esquema propio | ❌ |
| `ios/Runner/Info.plist` | Textos de permisos ya en español; corregir tilde "Cámara" | ✅ / ❌ menor |
| `ios/Runner/Assets.xcassets/AppIcon.appiconset/*` | 25 tamaños generados, 1024 sin alfa | ✅ |
| `ios/Runner/Base.lproj/LaunchScreen.storyboard` | Splash en blanco (solo color de fondo). Agregar logo/color de marca | ❌ (opcional) |
| `ios/Runner/GoogleService-Info.plist` | Proyecto `ridder-f7fb3`, bundle `com.ridder.manager` | ✅ |
| `ios/Runner/Runner.entitlements` | `aps-environment = development`; Xcode lo cambia a `production` al archivar con perfil de distribución, pero conviene verificarlo | ⚠️ |
| `lib/firebase_options.dart` | Sigue con el proyecto Firebase de Traccar (`traccar-manager-app`, API keys de Traccar, `iosBundleId: org.traccar.TraccarManager`). No se usa, pero hay que regenerarlo con `flutterfire configure` o borrarlo | ❌ |
| `firebase.json` | Ídem: apunta a `traccar-manager-app` | ❌ |
| `lib/main.dart` | Colores: `ColorScheme.fromSeed(seedColor: Colors.blue)` → color de marca Ridder | ❌ |
| `lib/main_screen.dart` | Texto `'Unknown'`, y `'Invalid URL'` en `error_screen.dart`, `'Authenticate to access login token'` en `token_store.dart`: pasar a español | ❌ |
| `pubspec.yaml` | `name: traccar_manager` (afecta los `import 'package:traccar_manager/...'`; se puede dejar) y `description: "Traccar Manager"` → "Ridder GPS" | ❌ |
| `README.md` | Es el de Traccar (badges a Play/App Store de Traccar, equipo de Traccar). Reescribir para Ridder manteniendo la atribución (ver sección 6) | ❌ |
| `.github/FUNDING.yml` | `github: traccar` (pide donaciones para Traccar desde tu repo). Borrar | ❌ |
| `tool/brand.dart` | Ya tiene `appName`, `packageId`, `url`. Le falta cambiar `namespace`, mover `MainActivity.kt`, el esquema de deep link y los `UsageDescription` | ❌ parcial |
| Textos "Traccar" en la UI web | El login, el título de la pestaña, etc. los sirve el servidor: se cambian en el servidor Traccar (atributos `ui.*`, logo, título) no en la app | n/a |

---

## 4. Requisitos de Google Play

| Requisito | Estado | Detalle |
|---|---|---|
| **Firma: keystore de subida** | ❌ **Crítico** | `android/android.keystore` y `android/key.properties` están versionados en el repo. La contraseña del keystore y de la clave es literalmente `password` (verificado con `keytool`). El certificado es `CN=Brand, OU=Dev, O=Company`, válido 2026-02-09 → 2053-06-27. Cualquiera con acceso al repo puede firmar actualizaciones de la app. Hay que: generar un keystore nuevo con contraseña fuerte, guardarlo fuera del repo (en secretos de CI, como hace el `release.yml` de upstream), sacar ambos archivos de git y, si el repo fue alguna vez público, considerar comprometido el actual. |
| **Play App Signing** | ⚠️ | Es obligatorio para apps nuevas: Google guarda la clave de firma y vos subís con una "clave de subida". El keystore local pasa a ser solo la clave de subida (se puede resetear si se pierde). Se configura en la consola al crear la app. |
| **Android App Bundle (.aab)** | ⚠️ | Play exige `.aab`, no APK. El proyecto puede generarlo (`flutter build appbundle --release`), pero el `release.yml` de upstream genera APK; adaptar. |
| **`targetSdk`** | ✅ condicionado | Desde el 31 de agosto de 2026 las apps nuevas y actualizaciones deben apuntar a **API 36 (Android 16)**. El proyecto usa `flutter.targetSdkVersion`, que en Flutter 3.47.9 es 36 y `compileSdk` 36. Se cumple **solo si se compila con Flutter actual**, lo que a su vez exige actualizar Gradle/AGP/Kotlin (sección 7). Upstream ya puso `compileSdk = 37`. |
| **`minSdk`** | ✅ | `flutter.minSdkVersion` = 24 (Android 7.0). |
| **Permisos declarados** | ⚠️ | `INTERNET` ✅ necesario. `USE_BIOMETRIC` ✅ justificado por `local_auth` (pero hoy el flujo que lo usa no se dispara por el puente roto). `ACCESS_FINE_LOCATION` + `ACCESS_COARSE_LOCATION` ⚠️: la app no usa GPS nativo; están para que el WebView pueda conceder geolocalización a la web (botón "mi ubicación" del mapa). Es justificable como "ubicación en primer plano para mostrar tu posición en el mapa", pero hay que declararlo así en la ficha; **no hay ubicación en segundo plano** (no se declara `ACCESS_BACKGROUND_LOCATION`, correcto). `CAMERA` ❌: solo servía para escanear el QR de cambio de servidor, que el fork eliminó. Quitar el permiso (y `PERMISSION_CAMERA=1` del Podfile) para no tener que justificarlo. `POST_NOTIFICATIONS` (Android 13+) lo agrega el plugin de Firebase Messaging automáticamente ✅. |
| **Política de privacidad** | ❌ | Obligatoria (la app pide ubicación y usa Firebase Analytics/Crashlytics). Hace falta una URL pública de Ridder con la política, cargada en la ficha y accesible también desde la app o la web del servidor. |
| **Formulario de seguridad de datos (Data safety)** | ❌ | Hay que declarar: ubicación aproximada/precisa (uso en la app, no compartida), identificadores de dispositivo y datos de uso/diagnóstico (Firebase Analytics y Crashlytics → "compartido con terceros" = Google), credenciales (email/contraseña del login web), token push. Datos cifrados en tránsito (HTTPS) ✅; mecanismo de borrado de cuenta ❌ (Play lo pide si hay creación de cuenta; en Traccar la cuenta la crea el administrador, se puede declarar que las cuentas las gestiona la organización). |
| **Declaración de ubicación** | ⚠️ | En la consola hay que responder el cuestionario de permisos sensibles de ubicación. Al ser solo primer plano, no requiere video de demostración. |
| **Versión y `versionCode`** | ⚠️ | `1.0.0+1`. Está bien para el primer envío; cada subida posterior necesita `versionCode` mayor (`pubspec.yaml` → `version: 1.0.1+2`, etc.). |
| **Cuenta de desarrollador** | ❌ | Si la cuenta es **personal** y creada después de noviembre de 2023, Play exige una prueba cerrada con **al menos 12 testers inscritos durante 14 días seguidos** antes de dar acceso a producción. Con cuenta de **organización** (requiere D-U-N-S de Ridder) no aplica. Recomendación: cuenta de organización. |
| **Ícono adaptativo / recursos gráficos** | ❌ | Falta ícono adaptativo (ver sección 3). Para la ficha: ícono 512×512, gráfico destacado 1024×500, mínimo 2 capturas de teléfono (hasta 8), opcional tablet. |
| **Deep links / App Links** | ✅ | Solo esquema personalizado, no hay `assetlinks.json` que mantener. |
| **Tráfico en texto claro** | ⚠️ | `network_security_config.xml` tiene `cleartextTrafficPermitted="true"` y confía en certificados de usuario. Con servidor fijo HTTPS no hace falta; ponerlo en `false` y sacar `<certificates src="user"/>` (ver sección 7). No bloquea la publicación, pero es una observación de seguridad. |
| **Formulario de anuncios / contenido** | ⚠️ | Sin anuncios; clasificación de contenido IARC (cuestionario simple); público objetivo adultos (no es app para niños). |
| **Firebase Analytics y consentimiento** | ⚠️ | Si se mantiene Analytics, declararlo en Data safety. Si no se necesita, quitar `firebase_analytics` de `pubspec.yaml` (no se usa explícitamente en el código) y simplificar las declaraciones. |

---

## 5. Requisitos de App Store

| Requisito | Estado | Detalle |
|---|---|---|
| **Cuenta Apple Developer Program** | ⚠️ | Hay un `DEVELOPMENT_TEAM = 2N378K4VZ6` en el proyecto, así que existe un equipo. Para publicar a nombre de Ridder debe ser una cuenta de **organización** (D-U-N-S), no individual; si es individual, la ficha mostrará el nombre de la persona. US$ 99/año. |
| **Bundle ID** | ✅ | `com.ridder.manager` en los 3 build configs. Hay que registrarlo en Certificates, Identifiers & Profiles con la capacidad **Push Notifications** activada, y crear la app en App Store Connect con ese ID. |
| **Certificados y perfiles** | ❌ | `CODE_SIGN_STYLE = Automatic`: Xcode puede generarlos solo si se inicia sesión con la cuenta. Para CI (como el `release.yml` de upstream) hacen falta: certificado de distribución (Apple Distribution), perfil App Store, y una **API key de App Store Connect** (`.p8`). |
| **Clave APNs para Firebase** | ❌ | Para que lleguen push en iOS hay que subir la clave APNs (`.p8`, Keys → Apple Push Notifications service) al proyecto Firebase `ridder-f7fb3` en Project settings → Cloud Messaging → Apple apps. Sin eso no hay notificaciones en iOS. |
| **`aps-environment`** | ⚠️ | El entitlement dice `development`; Xcode lo cambia a `production` al exportar para App Store con el perfil correcto. Verificar en el `.ipa`. |
| **Textos de uso de permisos en `Info.plist`** | ✅ parcial | `NSLocationWhenInUseUsageDescription` ✅ (español). `NSFaceIDUsageDescription` ✅. `NSCameraUsageDescription` ✅ pero debería eliminarse junto con el permiso (QR ya no existe). Falta `NSLocationAlwaysAndWhenInUseUsageDescription` que upstream agregó porque algunos plugins lo requieren para no fallar la validación; si no se usa ubicación en segundo plano, agregar el texto igual (Apple rechaza binarios con APIs de ubicación sin la cadena). `UIBackgroundModes` tiene `remote-notification` ✅ y `fetch` ⚠️ (no se usa background fetch; quitarlo evita preguntas en revisión). |
| **Política de privacidad** | ❌ | URL obligatoria en App Store Connect. Misma que para Play. |
| **Etiquetas de privacidad (App Privacy)** | ❌ | Declarar: Ubicación precisa (funcionalidad de la app), Datos de contacto/credenciales (login), Identificadores (token push, ID de instalación Firebase), Diagnósticos (Crashlytics), Datos de uso (Analytics). Marcar "datos vinculados al usuario" para lo que va asociado a la cuenta. Si se quita Analytics, menos ítems. Además, en el binario se exige **Privacy Manifest** (`PrivacyInfo.xcprivacy`): los SDKs de Firebase ya traen el suyo; Flutter lo genera para el runner. Con los Firebase 4.x del fork puede faltar la cobertura completa; upstream usa 5.x/17.x que sí lo traen. |
| **Xcode e iOS mínimo** | ❌ con el fork actual | Desde el **28 de abril de 2026** App Store Connect solo acepta binarios compilados con **Xcode 26 y el SDK de iOS 26**. El proyecto del fork tiene `LastUpgradeCheck = 1510` (Xcode 15.1), CocoaPods, sin `UIScene`. Flutter 3.47 con Xcode 26 funciona, pero hay que ejecutar la migración de Xcode (upstream ya la hizo: `UIApplicationSceneManifest`, `FlutterSceneDelegate`, SwiftPM). Deployment target 15.0 ✅ (Flutter 3.47 exige ≥ 13; 15 es razonable). |
| **Pantallas de distintos tamaños** | ⚠️ | `TARGETED_DEVICE_FAMILY = "1,2"` → también iPad. Eso obliga a subir capturas de iPad (13") además de iPhone (6.9"/6.5") y a que la app se vea bien en iPad; el WebView se adapta, pero si no se quiere mantener iPad, poner `TARGETED_DEVICE_FAMILY = 1`. Orientaciones: iPhone retrato + horizontal, iPad todas ✅. |
| **Guideline 4.2 (funcionalidad mínima) y 4.2.2** | ⚠️ **Riesgo real** | Apple rechaza apps que son "un sitio web empaquetado". Esta app lo es casi por definición. El original de Traccar está aprobado porque aporta funciones nativas: push, login con biometría, deep links, compartir reportes, integración con el servidor del usuario. **En el fork, con el puente roto, dos de esas funciones (push, sesión con biometría) no operan**, lo que deja a la app como un WebView puro y aumenta el riesgo de rechazo. Antes de enviar: restaurar el puente, verificar que las push lleguen en iOS, y en las "App Review notes" explicar las funciones nativas y proporcionar una **cuenta demo** con dispositivos que se muevan (Apple necesita ver contenido real; si el reviewer ve un login vacío, rechaza por 2.1). |
| **Guideline 5.1.1 / 5.1.2 (datos)** | ⚠️ | Pedir permiso de ubicación solo cuando se use (la web lo pide al tocar "mi ubicación", bien). No pedir Face ID al abrir si no hay token guardado (el código ya lo hace). |
| **Guideline 2.3 (metadata precisa)** | ⚠️ | No decir "Traccar" en el nombre de la ficha ni usar el logo de Traccar. Descripción, capturas y nombre deben ser de Ridder. |
| **Encryption export compliance** | ⚠️ | Solo HTTPS estándar → `ITSAppUsesNonExemptEncryption = NO` en `Info.plist` evita el cuestionario en cada subida. No está puesto. |
| **Cuenta de prueba para revisión** | ❌ | Obligatoria: usuario y contraseña en App Store Connect → App Review Information. |
| **TestFlight** | recomendado | Probar push, login, descargas y deep links en dispositivo real antes de enviar. |

---

## 6. Licencia (Apache 2.0)

Traccar Manager se distribuye bajo Apache License 2.0 (`LICENSE.txt`). Publicar un fork con otra marca y de forma cerrada está permitido; **no obliga a liberar tu código ni a usar la misma licencia** para tus cambios, pero sí obliga a lo siguiente (sección 4 de la licencia):

1. **Conservar el aviso de licencia**: mantener `LICENSE.txt` en el repo y entregar una copia de la licencia junto con la app. En la práctica, una pantalla "Acerca de / Licencias de código abierto" en la app (o un enlace en la ficha / en la web del servidor) que diga que la app está basada en Traccar Manager © Anton Tananaev, licenciado bajo Apache 2.0, con enlace a la licencia. Flutter puede generar la lista de licencias de los paquetes con `showLicensePage`; Traccar Manager hay que agregarlo a mano con `LicenseRegistry.addLicense`.
2. **Indicar los cambios**: los archivos modificados deben llevar "avisos destacados de que fueron modificados". Alcanza con una nota en el README / un archivo `NOTICE` ("Este software es una versión modificada de Traccar Manager, modificada por Ridder") y un encabezado de copyright en los archivos Dart que toques.
3. **Avisos de copyright y atribución**: no quitar los avisos de copyright existentes. El código actual casi no tiene encabezados, pero el README y la licencia nombran a Anton Tananaev; conservar esa atribución.
4. **Archivo `NOTICE`**: el upstream no incluye uno, así que no hay obligación de redistribuirlo, pero conviene crear `NOTICE` propio con: nombre del producto (Ridder GPS), copyright de Ridder sobre las modificaciones, "Incluye software de Traccar Manager, Copyright Anton Tananaev, Apache License 2.0", y el aviso de que "Traccar" es una marca de su titular y no está afiliada.
5. **Marcas**: la licencia **no concede** derecho a usar el nombre ni el logo "Traccar" (sección 6). Por eso hay que quitar todo rastro de la marca Traccar en nombre, ícono, ficha y descripción, exactamente lo que ya se está haciendo. Mencionar "basado en Traccar" en los créditos es atribución, no uso de marca, y está bien.
6. **Sin garantía**: la app se publica bajo tu responsabilidad; Traccar no responde por ella.

Además: `traccar-web` (lo que se ve dentro del WebView) y el servidor Traccar también son Apache 2.0; si personalizás la web, aplican las mismas reglas allí. Las licencias de los paquetes de pub.dev (BSD/MIT en su mayoría) se cubren con la pantalla de licencias de Flutter.

---

## 7. Seguridad y calidad

### Credenciales y token

- **Credenciales de login**: nunca las ve el código Dart; las maneja la web dentro del WebView y la sesión queda como cookie del WebView (`JSESSIONID` de Traccar). Correcto.
- **Token de sesión de larga duración** (6 meses, lo genera la web con `api/session/token`): se guarda con `flutter_secure_storage` (Keystore en Android, Keychain en iOS) y se lee pidiendo biometría/credencial del dispositivo con `local_auth`. Es el diseño correcto. **Pero en el fork nunca se guarda** porque la web no detecta la app (puente roto).
- **Token FCM**: se pasa a la web por `evaluateJavascript` con interpolación directa en una cadena JS (`"updateNotificationToken?.('$token')"`). El token FCM no tiene comillas, así que no hay inyección práctica, pero upstream tampoco lo escapa; sería más prudente `jsonEncode(token)`.
- **Datos en Crashlytics**: solo trazas; no se registran identificadores de usuario a mano.

### HTTPS y certificados

- URL fija `https://` ✅. `ErrorScreen` acepta `http://` pero en el fork es inalcanzable.
- **Android**: `network_security_config.xml` permite tráfico en texto claro (`cleartextTrafficPermitted="true"`) y confía en CAs instaladas por el usuario. Esto permite interceptar el tráfico con un proxy si alguien instala una CA en el teléfono. Con servidor fijo HTTPS, poner `cleartextTrafficPermitted="false"` y dejar solo `<certificates src="system"/>`. Se puede ir más lejos con pinning del certificado de `track.ridder.com.py`, con el riesgo de romper la app al renovar el certificado.
- **iOS**: `NSAllowsArbitraryLoads = true` desactiva ATS por completo. Con servidor HTTPS, eliminar la clave `NSAppTransportSecurity`. Apple pregunta por esto en la revisión si la detecta.
- Validación de certificados: la hace el sistema (WebView y `http`), no está deshabilitada en código ✅.
- La URL `track.ridder.com.py` no es alcanzable desde este entorno (bloqueo de red del sandbox), así que **no pude verificar que el servidor exista, responda por HTTPS ni tenga un certificado válido**. Hay que confirmarlo a mano antes de compilar.

### Dependencias

`flutter pub get` con Flutter 3.47.9 resolvió sin conflictos y **pub.dev no reportó avisos de seguridad** (security advisories) para el conjunto actual. Sí hay atraso importante (`flutter pub outdated`, solo directas):

| Paquete | Fork | Última | Salto |
|---|---|---|---|
| firebase_core | 4.4.0 | 5.1.0 | mayor |
| firebase_messaging | 16.1.1 | 17.0.1 | mayor |
| firebase_crashlytics | 5.0.7 | 6.0.1 | mayor |
| firebase_analytics | 12.1.1 | 13.0.1 | mayor |
| flutter_secure_storage | 10.0.0 | 11.2.0 | mayor |
| share_plus | 12.0.1 | 13.3.1 | mayor |
| permission_handler | 12.0.1 | 13.0.2 | mayor (y no se usa) |
| flutter_inappwebview | 6.1.5 (lock) | 6.2.0-beta.3 (upstream) | menor |
| app_links, local_auth, path_provider, rate_my_app, shared_preferences*, url_launcher | — | — | parches/menores |

Las versiones mayores de Firebase traen los Privacy Manifests de Apple actualizados y el soporte de iOS 26 / Android 16; los Firebase 4.x–16.x del fork quedarán sin soporte. No encontré CVEs publicados para las versiones exactas del fork; el riesgo es de compatibilidad más que de vulnerabilidad conocida.

### Código muerto y deuda

- `lib/error_screen.dart` y `_loadingError`: en el fork **nunca se asigna un error** (se quitó `onReceivedError`), así que si el servidor está caído el usuario ve la página de error del WebView o una pantalla en blanco en vez de `ErrorScreen`. Y `onUrlSubmitted` ignora la URL ingresada.
- `lib/firebase_options.dart` y `firebase.json`: no se usan y apuntan al proyecto Firebase de Traccar (con sus API keys públicas de cliente).
- Dependencias declaradas y no importadas: `permission_handler`, `shared_preferences`, `shared_preferences_android`, `firebase_analytics` (este último se inicializa solo al estar en el árbol, así que sí recolecta datos aunque no se llame).
- `addJavaScriptHandler('appInterface')` sin emisor (puente roto).
- `tool/brand.dart`: la función `_updateUrl` buscaba `https://demo.traccar.org`, que ya no existe en el código, así que no hacía nada; se corrigió en el commit del servidor para que reemplace `_lockedUrl`. Sigue creando el keystore con contraseña fija `password` y escribiendo `key.properties` dentro del repo: hay que cambiar eso.
- Hack de DOM para ocultar el botón QR: innecesario si se restaura el puente y se usa el atributo `disableChange` del servidor.
- `permission_handler`: el `Podfile` define `PERMISSION_CAMERA=1` para un plugin que ya no se importa.
- Formato: `build()` en `main_screen.dart` quedó con indentación inconsistente (2 niveles menos que el resto); cosmético.
- `ios/Podfile.lock` y `pubspec.lock` versionados mientras upstream dejó de hacerlo; el `pubspec.lock` exige Flutter ≥ 3.38.4 pero `.metadata` dice 3.29.3.

### Warnings de compilación y si compila hoy

Lo que pude ejecutar en este entorno (Linux, sin Android SDK ni Xcode; descargué Flutter 3.47.9 estable):

| Comprobación | Resultado |
|---|---|
| `flutter pub get` | ✅ Resuelve. Cambia 6 paquetes transitivos del lock (test_api, vector_math, etc.) por el Flutter más nuevo. |
| `flutter analyze` | ✅ **0 issues** (lints de `flutter_lints` 6). |
| `flutter test` | ⚠️ No hay carpeta `test/`: la app no tiene ninguna prueba automatizada. `ios/RunnerTests` tiene un test vacío. |
| `flutter build apk --debug` | ❌ No se pudo: "No Android SDK found". El entorno bloquea `dl.google.com`, de donde se baja el SDK de Android, así que no se puede instalar aquí. |
| `flutter build ios` | ❌ Imposible en Linux (requiere macOS + Xcode). |
| Chequeo estático del toolchain Android | ❌ **Fallaría con Flutter 3.47.9**: Flutter aborta el build si Gradle < 8.14 (fork: 8.11.1), AGP < 8.11.1 (fork: 8.9.1), Kotlin < 2.2.20 (fork: 2.1.21) o Java < 17 (fork: 11). Con un Flutter viejo (3.29–3.32) sí compilaría, pero entonces el `targetSdk` sería 35 y Play lo rechazaría para apps nuevas desde agosto de 2026. |
| Chequeo estático iOS | ⚠️ Compilaría con Xcode 26 solo tras migrar el proyecto (SwiftPM/`UIScene`) como hizo upstream; Flutter 3.47 avisa que el `AppDelegate` sin `FlutterImplicitEngineDelegate` queda obsoleto. |

Conclusión: **hoy el fork no está en condiciones de compilar un binario publicable para ninguna de las dos tiendas** sin actualizar el toolchain, y el camino más corto para hacerlo es adoptar el `main` de upstream.

---

## 8. Plan de publicación

Orden sugerido. "Yo" = cambios en el código de este repo; "Vos" = consolas de Google/Apple, cuentas, pagos y material de la ficha.

### Fase 0: higiene urgente (yo, hoy)

1. Sacar `android/android.keystore` y `android/key.properties` del repo (`git rm`), agregarlos a `.gitignore`, y modificar `tool/brand.dart` para que no genere keystores con contraseña fija dentro del repo. Si el repo fue público, dar por comprometida esa clave.
2. Borrar `.github/FUNDING.yml`.

### Fase 1: rebase sobre upstream (yo)

3. Crear rama `ridder` a partir de `traccar/traccar-manager@main` (6.2.4+87).
4. Reaplicar la marca con `tool/brand.dart` corregido: nombre "Ridder GPS", `com.ridder.manager` (incl. `namespace` y mover `MainActivity.kt`), íconos (con adaptativo y `ic_stat_notify`), esquema de deep link propio, `flutterfire configure` con el proyecto `ridder-f7fb3` (regenera `firebase_options.dart`, `firebase.json`, `google-services.json`, `GoogleService-Info.plist`).
5. Fijar el servidor: `_getUrl()` devuelve `https://track.ridder.com.py` ignorando preferencias; conservar el `UserScript` del puente y la intercepción de descargas; quitar el hack de DOM; eliminar `ErrorScreen` o dejarla sin campo editable.
6. Permisos: quitar `CAMERA` (Android), `NSCameraUsageDescription`, `PERMISSION_CAMERA` (iOS), `fetch` de `UIBackgroundModes`; agregar `NSLocationAlwaysAndWhenInUseUsageDescription` e `ITSAppUsesNonExemptEncryption = NO`; `cleartextTrafficPermitted="false"` sin CAs de usuario; eliminar `NSAllowsArbitraryLoads`.
7. Limpiar dependencias no usadas (`permission_handler`, `shared_preferences*`, decidir `firebase_analytics`); traducir los 3 textos en inglés; color de marca en `ColorScheme.fromSeed`.
8. Licencia: `NOTICE`, README propio con atribución a Traccar Manager, pantalla "Acerca de" con `LicenseRegistry`.
9. Versión: `version: 1.0.0+1` para el primer envío; definir regla (`versionCode` siempre creciente).
10. Adaptar `release.yml` de upstream: generar `.aab` en vez de APK, `IOS_BUNDLE_ID: com.ridder.manager`, y usar los secretos de GitHub para keystore y claves de Apple. Agregar al menos un test de widget para que CI no esté vacío.
11. Compilar `flutter build appbundle --release` y `flutter build ipa` en una máquina con Android SDK y macOS/Xcode 26 (o en GitHub Actions), y probar en dispositivos reales: login, token persistente con biometría, push (tocar la notificación abre el evento), descarga de reporte, botón atrás, deep link.

### Fase 2: servidor (vos, con mi ayuda si hace falta)

12. Confirmar que `https://track.ridder.com.py` responde con certificado válido y que es la versión de Traccar que espera el nuevo flujo de push (Installation ID; Traccar ≥ 6.x reciente).
13. En Traccar: Ajustes → Servidor → activar el atributo `disableChange` (oculta "cambiar servidor"), y configurar título/logo/colores de la web para que no digan "Traccar".
14. Configurar notificaciones push del servidor hacia Firebase `ridder-f7fb3` (`notificator.firebase.*` en `traccar.xml` con la service account del proyecto).
15. Publicar la **política de privacidad** de Ridder en una URL estable y crear una **cuenta demo** con dispositivos reales para los revisores.

### Fase 3: Google Play (vos)

16. Cuenta de desarrollador de Play, preferiblemente de **organización** (D-U-N-S, US$ 25 único, verificación de identidad). Evita la regla de 12 testers × 14 días.
17. Crear la app, activar Play App Signing, subir el `.aab` a prueba interna.
18. Completar: ficha (nombre, descripciones, ícono 512, gráfico 1024×500, 2–8 capturas), política de privacidad, Data safety, clasificación de contenido, público objetivo, declaración de permisos de ubicación, anuncios (no).
19. Probar la prueba interna en varios teléfonos, pasar a producción (o cerrada si la cuenta es personal). Revisión típica: días.

### Fase 4: App Store (vos)

20. Apple Developer Program de organización (D-U-N-S, US$ 99/año). Confirmar que el team `2N378K4VZ6` es ese.
21. Identifiers: registrar `com.ridder.manager` con Push Notifications; crear clave APNs y subirla a Firebase; certificado Apple Distribution y perfil App Store (o dejar que Xcode automático / `release.yml` lo haga con una API key de App Store Connect).
22. Crear la app en App Store Connect: nombre, subtítulo, categoría (Navegación o Utilidades), capturas 6.9" y 6.5" (y 13" iPad si se mantiene iPad), descripción, palabras clave, URL de soporte y de privacidad, etiquetas de privacidad, clasificación por edades, cuenta demo en App Review Information y **notas para el revisor** explicando las funciones nativas (push, biometría, deep links, compartir reportes) y que la app se conecta al servidor propio de Ridder.
23. Subir el build (Xcode 26 / `flutter build ipa` + Transporter o `altool`), probar en TestFlight, enviar a revisión. Si rechazan por 4.2, responder con el detalle de funciones nativas y, si hace falta, agregar alguna más (p. ej. pantalla nativa de ajustes/acerca de, o un widget).

### Fase 5: mantenimiento

24. Mantener la rama `ridder` como parche pequeño sobre upstream y rebasear ante cada release de Traccar Manager (el proyecto saca versiones casi semanales). Dependabot ya está configurado.
25. Rotar el `versionCode`/`CFBundleVersion` en cada subida y vigilar los plazos anuales de `targetSdk` (agosto) y del SDK de iOS (abril).

---

## Fuentes consultadas

- Código del repo y de `traccar/traccar-manager` (`main`, 29-oct-2026) y `traccar/traccar-web` (`master`), clonados localmente.
- Flutter 3.47.9 estable: `FlutterExtension.kt` (valores por defecto `compileSdk`/`targetSdk` 36, `minSdk` 24) y `DependencyVersionChecker.kt` (mínimos de Gradle/AGP/Kotlin/Java).
- Google Play, nivel de API objetivo: https://developer.android.com/google/play/requirements/target-sdk
- Google Play, pruebas cerradas para cuentas personales (12 testers / 14 días): https://support.google.com/googleplay/android-developer/answer/14151465
- Apple, requisitos próximos (Xcode 26 / SDK iOS 26 desde el 28-abr-2026): https://developer.apple.com/news/upcoming-requirements/
- Apple, App Store Review Guidelines 4.2 Minimum Functionality: https://developer.apple.com/app-store/review/guidelines/#minimum-functionality
- Apache License 2.0, secciones 4 y 6: https://www.apache.org/licenses/LICENSE-2.0
