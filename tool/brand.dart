import 'dart:io';

/// Herramienta de marca. La marca Ridder ya está aplicada en el repo; este
/// script existe para reaplicarla tras un merge de upstream o para cambiar
/// nombre/versión/servidor en un solo lugar.
///
/// Uso (desde la raíz del repo):
///   dart run tool/brand.dart              # nombre, package id, versión, URL
///   dart run tool/brand.dart --icons      # además regenera los íconos
///   dart run tool/brand.dart --keystore   # además crea el keystore de subida
///
/// `--keystore` exige la variable de entorno KEYSTORE_PASSWORD (12+ caracteres)
/// y nunca sobrescribe un keystore existente.
const appName = 'Ridder GPS';
const packageId = 'com.ridder.manager';
const version = '1.0.0+1';
const url = 'https://track.ridder.com.py';
const brandColor = '#0D6EFD';

/// Ícono completo (fondo incluido) para iOS y el ícono legacy de Android.
const iconPath = 'assets/icon.png';

/// Capa frontal del ícono adaptativo de Android (logo sobre transparente, con
/// margen de seguridad). Si no existe, se conservan los archivos actuales.
const iconForegroundPath = 'assets/icon_foreground.png';

// Fuera del repo: la firma nunca se versiona.
const keystoreFilePath = '../environment/android.keystore';
const keystoreAlias = 'key';
final keystorePassword = Platform.environment['KEYSTORE_PASSWORD'] ?? '';

Future<void> main(List<String> args) async {
  await _updateTitle(appName);
  await _updatePackageId(packageId);
  await _updateVersion(version);
  await _updateUrl(url);
  if (args.contains('--icons')) {
    await _generateIcons();
  }
  if (args.contains('--keystore')) {
    await _createKeystore();
  }
  stdout.writeln('Listo. Si cambiaste de proyecto Firebase, corré `flutterfire configure`.');
}

Future<void> _generateIcons() async {
  final hasForeground = await File(iconForegroundPath).exists();
  if (!hasForeground) {
    stderr.writeln(
      'Aviso: no existe $iconForegroundPath; se regeneran solo los íconos de iOS '
      'y el legacy de Android. El ícono adaptativo actual se conserva.',
    );
  }

  // No se borra nada a mano: flutter_launcher_icons sobrescribe lo que genera.
  // El ícono de notificación (ic_stat_notify) y su meta-data en el manifest
  // no se tocan.
  final f = await _writeTempYaml('flutter_launcher_icons.yaml', '''
flutter_launcher_icons:
  android: true
  ios: true
  image_path: "$iconPath"
  remove_alpha_ios: true
${hasForeground ? '''
  adaptive_icon_background: "$brandColor"
  adaptive_icon_foreground: "$iconForegroundPath"
''' : ''}''');
  try {
    await _run('dart', ['run', 'flutter_launcher_icons']);
  } finally {
    await f.delete();
  }
}

Future<void> _updateTitle(String name) async {
  await _replaceInFile(
    'android/app/src/main/AndroidManifest.xml',
    RegExp(r'android:label="[^"]*"'),
    'android:label="$name"',
  );

  for (final key in ['CFBundleDisplayName', 'CFBundleName']) {
    await _replaceInFile(
      'ios/Runner/Info.plist',
      RegExp('<key>$key</key>\\s*<string>.*?</string>'),
      '<key>$key</key>\n\t<string>$name</string>',
    );
  }
}

Future<void> _updatePackageId(String id) async {
  await _replaceInFile(
    'android/app/build.gradle.kts',
    RegExp(r'applicationId = ".*?"'),
    'applicationId = "$id"',
  );

  // El bundle de tests lleva el sufijo .RunnerTests; se reemplaza primero el
  // genérico y después se restaura el de tests.
  await _replaceInFile(
    'ios/Runner.xcodeproj/project.pbxproj',
    RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = (?!.*\.RunnerTests;).*?;'),
    'PRODUCT_BUNDLE_IDENTIFIER = $id;',
  );
  await _replaceInFile(
    'ios/Runner.xcodeproj/project.pbxproj',
    RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = .*?\.RunnerTests;'),
    'PRODUCT_BUNDLE_IDENTIFIER = $id.RunnerTests;',
  );

  // El package id también es el esquema de los deep links.
  await _replaceInFile(
    'lib/main_screen.dart',
    RegExp(r"_appScheme = '[^']*'"),
    "_appScheme = '$id'",
  );
  await _replaceInFile(
    'android/app/src/main/AndroidManifest.xml',
    RegExp(r'android:scheme="[^"]*"'),
    'android:scheme="$id"',
  );
  await _replaceInFile(
    'ios/Runner/Info.plist',
    RegExp(r'<key>CFBundleURLSchemes</key>\s*<array>\s*<string>.*?</string>'),
    '<key>CFBundleURLSchemes</key>\n\t\t\t<array>\n\t\t\t\t<string>$id</string>',
  );
}

Future<void> _updateVersion(String version) async {
  await _replaceInFile(
    'pubspec.yaml',
    RegExp(r'^version:\s*.*$', multiLine: true),
    'version: $version',
  );
}

Future<void> _updateUrl(String url) async {
  await _replaceInFile(
    'lib/main_screen.dart',
    RegExp(r"_serverUrl = 'https?://[^']*'"),
    "_serverUrl = '$url'",
  );
}

Future<void> _createKeystore() async {
  if (keystorePassword.length < 12) {
    throw Exception('Definí KEYSTORE_PASSWORD (12+ caracteres) antes de crear el keystore.');
  }
  final keystore = File(keystoreFilePath);
  if (await keystore.exists()) {
    throw Exception('Ya existe $keystoreFilePath; no se sobrescribe. Borralo a mano si de verdad querés uno nuevo.');
  }
  await keystore.parent.create(recursive: true);
  final args = [
    '-genkeypair',
    '-v',
    '-keystore', keystoreFilePath,
    '-alias', keystoreAlias,
    '-keyalg', 'RSA',
    '-keysize', '2048',
    '-validity', '10000',
    '-storepass', keystorePassword,
    '-keypass', keystorePassword,
    '-dname', 'CN=Ridder GPS, O=Ridder, C=PY',
  ];
  await _run('keytool', args);

  // Ruta relativa a android/app/, que es desde donde Gradle resuelve storeFile.
  final file = File('${keystore.parent.path}/key.properties');
  await file.writeAsString('''
storePassword=$keystorePassword
keyPassword=$keystorePassword
keyAlias=$keystoreAlias
storeFile=../../$keystoreFilePath
''');
  stdout.writeln('Keystore creado en $keystoreFilePath. Hacé un backup cifrado: si se pierde, hay que resetear la clave de subida en Play Console.');
}

Future<File> _writeTempYaml(String name, String content) async {
  final file = File(name);
  await file.writeAsString(content);
  return file;
}

Future<void> _replaceInFile(String path, RegExp pattern, String replacement) async {
  final file = File(path);
  if (!await file.exists()) return;
  final text = await file.readAsString();
  final newText = text.replaceAll(pattern, replacement);
  if (newText != text) await file.writeAsString(newText);
}

Future<void> _run(String cmd, List<String> args) async {
  final proc = await Process.start(cmd, args);
  await stdout.addStream(proc.stdout);
  await stderr.addStream(proc.stderr);
  final code = await proc.exitCode;
  if (code != 0) throw Exception('$cmd ${args.join(" ")} failed ($code)');
}
