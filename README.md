# Ridder GPS

App móvil (Android e iOS) de rastreo GPS de Ridder. Se conecta al servidor
`https://track.ridder.com.py` y muestra la interfaz web de Traccar dentro de la
app, sumando las funciones nativas: notificaciones push, inicio de sesión
guardado con biometría, deep links y descarga/compartir de reportes.

## Origen y licencia

Este proyecto es una versión modificada de
[Traccar Manager](https://github.com/traccar/traccar-manager), la app oficial
del proyecto de código abierto [Traccar](https://www.traccar.org), creada por
Anton Tananaev y publicada bajo la
[Apache License 2.0](LICENSE.txt). Ver [NOTICE](NOTICE) para la atribución
completa. "Traccar" es una marca de su titular; Ridder GPS no está afiliada al
proyecto Traccar.

Cambios principales respecto al original:

- Marca Ridder (nombre, ícono, colores, identificadores `com.ridder.manager`).
- Servidor fijo: la app no permite cambiar de servidor.
- Permisos reducidos (sin cámara) y tráfico solo por HTTPS.
- Proyecto Firebase propio para notificaciones push y Crashlytics.

## Desarrollo

Requisitos: Flutter estable (3.47 o superior), Android Studio con SDK 36/37 y
JDK 17; para iOS, macOS con Xcode 26.

```sh
flutter pub get
flutter analyze
flutter test
flutter build appbundle --release   # Android (requiere environment/key.properties)
flutter build ipa --release         # iOS (requiere macOS y firma configurada)
```

La firma de Android se lee de `../environment/key.properties` (fuera del repo).
Nunca versionar keystores ni contraseñas.

El análisis completo para la publicación en las tiendas está en
[`docs/analisis-publicacion.md`](docs/analisis-publicacion.md).
