import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

/// Version affichée dans « À propos » (voir `version` dans pubspec.yaml).
const kAppVersion = '1.0.0';

/// État du serveur (`GET /ready`) : `{"status": "ready", "checks": {"api": "ok", ...}}`.
class ServerHealth {
  const ServerHealth({required this.status, required this.checks, this.latency});

  final String status;

  /// Dépendance -> `ok` / `error` (api, postgres, redis).
  final Map<String, String> checks;

  /// Temps de réponse mesuré par l'application.
  final Duration? latency;

  bool get isReady => status == 'ready';

  factory ServerHealth.fromJson(Map<String, dynamic> json, {Duration? latency}) {
    final raw = json['checks'];
    return ServerHealth(
      status: json['status']?.toString() ?? 'unknown',
      checks: raw is Map
          ? raw.map((key, value) => MapEntry(key.toString(), value.toString()))
          : const {},
      latency: latency,
    );
  }

  /// Libellé lisible d'une dépendance.
  static String checkLabel(String key) => switch (key) {
    'api' => 'API',
    'postgres' => 'PostgreSQL',
    'redis' => 'Redis',
    _ => key,
  };
}

/// Nom lisible du fournisseur d'IA configuré sur le serveur.
String aiProviderLabel(String provider) => switch (provider.toLowerCase()) {
  'anthropic' => 'Anthropic (Claude)',
  'openai' => 'OpenAI',
  'ollama' => 'Ollama',
  'none' || '' => 'Aucun',
  _ => provider,
};

/// Règles du mot de passe (identiques au serveur) : 8 caractères, une lettre, un chiffre.
typedef PasswordChecks = ({bool length, bool letter, bool digit});

PasswordChecks passwordChecks(String value) => (
  length: value.length >= 8,
  letter: RegExp(r'[A-Za-z]').hasMatch(value),
  digit: RegExp(r'\d').hasMatch(value),
);

/// Opérations du compte (mot de passe) et du serveur (santé).
class SettingsRepository {
  const SettingsRepository(this._api);

  final ApiClient _api;

  /// `PUT /users/me/password` (`PasswordChange`). Code `INVALID_PASSWORD` si l'actuel est faux.
  Future<void> changePassword({required String current, required String newPassword}) => _api.put(
    '/users/me/password',
    body: {'current_password': current, 'new_password': newPassword},
  );

  Future<ServerHealth> health() async {
    final watch = Stopwatch()..start();
    final data = await _api.health();
    watch.stop();
    return ServerHealth.fromJson(data, latency: watch.elapsed);
  }
}

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(apiClientProvider)),
);

/// État du serveur courant (recalculé quand l'adresse change).
/// Pas de nouvelle tentative automatique : l'utilisateur relance le test lui-même.
final serverHealthProvider = FutureProvider.autoDispose<ServerHealth>(
  (ref) => ref.watch(settingsRepositoryProvider).health(),
  retry: (_, _) => null,
);
