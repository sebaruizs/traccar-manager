import 'dart:io';

const appName = 'Ridder GPS';
const packageId = 'com.ridder.manager';
const version = '1.0.0+1';
const url = "https://track.ridder.com.py";
final iconPath = 'assets/icon.png';

// Fuera del repo: la firma nunca se versiona.
const keystoreFilePath = '../environment/android.keystore';
const keystoreAlias = 'key';
final keystorePassword = Platform.environment['KEYSTORE_PASSWORD'] ?? '';

Future<void> safeDelete(String path) async {
  final file = File(path);
  if (await file.exists()) {
    await file.delete();
  }
}

Future<void> main() async {
  await _generateIcons(iconPath);
  await _updateTitle(appName);
  await _updatePackageId(packageId);
  await _updateVersion(version);
  await _updateUrl(url);
  await _createKeystore();
  stdout.writeln('Please run `flutterfire configure` now.');
}

Future<void> _generateIcons(String icon) async {
  final dir = Directory('ios/Runner/Assets.xcassets/AppIcon.appiconset');
  if (await dir.exists()) {
  await dir.delete(recursive: true);
  }
  await dir.create(recursive: true);


  await safeDelete('android/app/src/main/res/drawable/ic_launcher_foreground.xml');
  await safeDelete('android/app/src/main/res/drawable-v24/ic_launcher_foreground.xml');
  await safeDelete('android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml');


  final f = await _writeTempYaml('flutter_launcher_icons.yaml', '''
flutter_launcher_icons:
  android: true
  ios: true
  image_path: "$icon"
  remove_alpha_ios: true
''');
  await _run('dart', ['run', 'flutter_launcher_icons']);
  await f.delete();

  await _replaceInFile(
    'android/app/src/main/AndroidManifest.xml',
    RegExp(r'\s*<meta-data\s+android:name="com\.google\.firebase\.messaging\.default_notification_icon"[\s\S]*?/>', multiLine: true),
    '',
  );
}

Future<void> _updateTitle(String name) async {
  await _replaceInFile(
    'android/app/src/main/AndroidManifest.xml',
    RegExp(r'android:label="[^"]*"'),
    'android:label="$name"',
  );

  await _replaceInFile(
    'ios/Runner/Info.plist',
    RegExp(r'<key>CFBundleDisplayName</key>\s*<string>.*?</string>'),
    '<key>CFBundleDisplayName</key>\n\t<string>$name</string>',
  );
}

Future<void> _updatePackageId(String id) async {
  await _replaceInFile(
    'android/app/build.gradle.kts',
    RegExp(r'applicationId = ".*?"'),
    'applicationId = "$id"',
  );

  await _replaceInFile(
    'ios/Runner.xcodeproj/project.pbxproj',
    
    RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = .*?;'),
    'PRODUCT_BUNDLE_IDENTIFIER = $id;',
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
    RegExp(r"_lockedUrl = 'https?://[^']*'"),
    "_lockedUrl = '$url'",
  );
}

Future<void> _createKeystore() async {
  if (keystorePassword.length < 12) {
    throw Exception('Definí KEYSTORE_PASSWORD (12+ caracteres) antes de crear el keystore.');
  }
  await Directory('../environment').create(recursive: true);
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

  final file = File('../environment/key.properties');
  final content = '''
storePassword=$keystorePassword
keyPassword=$keystorePassword
keyAlias=$keystoreAlias
storeFile=../../$keystoreFilePath
''';
  await file.writeAsString(content);

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
