import 'dart:developer' as developer;

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class TokenStore {
  static const _tokenKey = 'token';
  final _storage = const FlutterSecureStorage();
  final _auth = LocalAuthentication();

  Future<void> save(String token) async {
    try {
      await _storage.delete(key: _tokenKey);
      await _storage.write(key: _tokenKey, value: token);
    } on PlatformException catch (e) {
      developer.log('Failed to write token.', error: e);
    }
  }

  Future<bool> _canUseBiometrics() async {
    final canCheckBiometrics = await _auth.canCheckBiometrics;
    final isDeviceSupported = await _auth.isDeviceSupported();

    if (!canCheckBiometrics || !isDeviceSupported) {
      return false;
    }

    final biometrics = await _auth.getAvailableBiometrics();
    return biometrics.isNotEmpty;
  }


  Future<String?> read(bool authenticate) async {
  try {
    final hasToken = await _storage.containsKey(key: _tokenKey);
    if (!hasToken) return null;

    bool authenticated = !authenticate;

    if (authenticate) {
      final hasBiometric = await _canUseBiometrics();
      if (!hasBiometric) {
        developer.log('Biometric authentication not available.');
        return null;
      }

      authenticated = await _auth.authenticate(
        localizedReason: 'Authenticate with Face ID to access login token',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
        sensitiveTransaction: true,
      );
    }

    if (!authenticated) return null;

    return await _storage.read(key: _tokenKey);
  } on LocalAuthException catch (e) {
    developer.log('Failed to read token.', error: e);
    return null;
  } on PlatformException catch (e) {
    developer.log('Failed to read token.', error: e);
    return null;
  }
}

  Future<void> delete() async {
    _storage.delete(key: _tokenKey);
  }
}
