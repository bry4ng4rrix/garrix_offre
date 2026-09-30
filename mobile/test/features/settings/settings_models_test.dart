import 'package:flutter_test/flutter_test.dart';
import 'package:garrix_offre/features/settings/data/settings_repository.dart';

void main() {
  group('ServerHealth', () {
    test('serveur prêt (réponse réelle de GET /ready)', () {
      final health = ServerHealth.fromJson({
        'status': 'ready',
        'checks': {'api': 'ok', 'postgres': 'ok', 'redis': 'ok'},
      }, latency: const Duration(milliseconds: 42));
      expect(health.isReady, isTrue);
      expect(health.checks, {'api': 'ok', 'postgres': 'ok', 'redis': 'ok'});
      expect(health.latency?.inMilliseconds, 42);
    });

    test('serveur dégradé (HTTP 503) et réponse incomplète', () {
      final degraded = ServerHealth.fromJson({
        'status': 'not_ready',
        'checks': {'api': 'ok', 'postgres': 'error', 'redis': 'ok'},
      });
      expect(degraded.isReady, isFalse);
      expect(degraded.checks['postgres'], 'error');

      final empty = ServerHealth.fromJson(const {});
      expect(empty.isReady, isFalse);
      expect(empty.status, 'unknown');
      expect(empty.checks, isEmpty);
    });

    test('libellés des dépendances', () {
      expect(ServerHealth.checkLabel('postgres'), 'PostgreSQL');
      expect(ServerHealth.checkLabel('redis'), 'Redis');
      expect(ServerHealth.checkLabel('api'), 'API');
      expect(ServerHealth.checkLabel('autre'), 'autre');
    });
  });

  test('libellé du fournisseur d\'IA', () {
    expect(aiProviderLabel('anthropic'), 'Anthropic (Claude)');
    expect(aiProviderLabel('none'), 'Aucun');
    expect(aiProviderLabel('Mistral'), 'Mistral');
  });

  test('règles du mot de passe (identiques au serveur)', () {
    expect(passwordChecks(''), (length: false, letter: false, digit: false));
    expect(passwordChecks('abcdefgh'), (length: true, letter: true, digit: false));
    expect(passwordChecks('12345678'), (length: true, letter: false, digit: true));
    expect(passwordChecks('Passw0rd'), (length: true, letter: true, digit: true));
  });
}
