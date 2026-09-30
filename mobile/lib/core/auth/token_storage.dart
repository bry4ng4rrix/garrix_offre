import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

/// Stocke les tokens JWT.
///
/// Android : Keystore (flutter_secure_storage). Linux : trousseau (libsecret) ; si aucun
/// trousseau n'est disponible sur la machine, repli sur les préférences locales.
class TokenStorage {
  TokenStorage(this._prefs);

  static const _accessKey = 'garrix_access_token';
  static const _refreshKey = 'garrix_refresh_token';

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  bool _useFallback = false;

  String? _accessToken;
  String? _refreshToken;

  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  bool get hasSession => _refreshToken != null;

  Future<void> load() async {
    _accessToken = await _read(_accessKey);
    _refreshToken = await _read(_refreshKey);
  }

  Future<void> save({required String accessToken, required String refreshToken}) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    await _write(_accessKey, accessToken);
    await _write(_refreshKey, refreshToken);
  }

  Future<void> clear() async {
    _accessToken = null;
    _refreshToken = null;
    await _delete(_accessKey);
    await _delete(_refreshKey);
  }

  Future<String?> _read(String key) async {
    if (!_useFallback) {
      try {
        return await _secure.read(key: key);
      } catch (error) {
        _enableFallback(error);
      }
    }
    return _prefs.getString(key);
  }

  Future<void> _write(String key, String value) async {
    if (!_useFallback) {
      try {
        await _secure.write(key: key, value: value);
        return;
      } catch (error) {
        _enableFallback(error);
      }
    }
    await _prefs.setString(key, value);
  }

  Future<void> _delete(String key) async {
    try {
      await _secure.delete(key: key);
    } catch (_) {
      // Trousseau indisponible : rien à supprimer côté sécurisé.
    }
    await _prefs.remove(key);
  }

  void _enableFallback(Object error) {
    _useFallback = true;
    debugPrint('Stockage sécurisé indisponible, repli sur les préférences locales : $error');
  }
}

final tokenStorageProvider = Provider<TokenStorage>(
  (ref) => TokenStorage(ref.read(sharedPreferencesProvider)),
);
