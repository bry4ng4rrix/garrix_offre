import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Serveur de production par défaut (modifiable dans l'écran de connexion et les réglages).
const kDefaultServerUrl = 'http://185.215.167.79:8000';
const kApiPrefix = '/api/v1';
const kAppName = 'Garrix Offre';

/// Injecté dans `main()` (voir `ProviderScope.overrides`).
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider doit être surchargé dans main()'),
);

/// URL du serveur (sans `/api/v1`), persistée localement.
class ServerUrlNotifier extends Notifier<String> {
  static const _key = 'server_url';

  @override
  String build() => ref.read(sharedPreferencesProvider).getString(_key) ?? kDefaultServerUrl;

  Future<void> update(String url) async {
    final normalized = normalize(url);
    await ref.read(sharedPreferencesProvider).setString(_key, normalized);
    state = normalized;
  }

  Future<void> reset() => update(kDefaultServerUrl);

  /// `185.215.167.79:8000/` -> `http://185.215.167.79:8000`
  static String normalize(String url) {
    var value = url.trim();
    if (value.isEmpty) return kDefaultServerUrl;
    if (!value.startsWith(RegExp(r'https?://'))) value = 'http://$value';
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    if (value.endsWith(kApiPrefix)) value = value.substring(0, value.length - kApiPrefix.length);
    return value;
  }
}

final serverUrlProvider = NotifierProvider<ServerUrlNotifier, String>(ServerUrlNotifier.new);
