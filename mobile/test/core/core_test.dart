import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garrix_offre/core/config/app_config.dart';
import 'package:garrix_offre/core/models/enums.dart';
import 'package:garrix_offre/core/network/api_exception.dart';
import 'package:garrix_offre/core/network/paginated.dart';
import 'package:garrix_offre/core/utils/formatters.dart';
import 'package:intl/date_symbol_data_local.dart';

DioException _dioError({int? status, Object? data, DioExceptionType? type}) {
  final request = RequestOptions(path: '/test');
  return DioException(
    requestOptions: request,
    type: type ?? DioExceptionType.badResponse,
    response: status == null ? null : Response(requestOptions: request, statusCode: status, data: data),
  );
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  group('ApiException', () {
    test('lit l\'enveloppe d\'erreur de l\'API', () {
      final error = ApiException.fromDio(
        _dioError(
          status: 401,
          data: {
            'success': false,
            'error': {'code': 'INVALID_CREDENTIALS', 'message': 'Invalid email or password'},
          },
        ),
      );
      expect(error.code, 'INVALID_CREDENTIALS');
      expect(error.isUnauthorized, isTrue);
      expect(error.userMessage, 'Email ou mot de passe incorrect.');
    });

    test('détaille les erreurs de validation par champ', () {
      final error = ApiException.fromDio(
        _dioError(
          status: 422,
          data: {
            'success': false,
            'error': {
              'code': 'VALIDATION_ERROR',
              'message': 'Invalid request data',
              'details': [
                {'field': 'email', 'message': 'value is not a valid email address'},
              ],
            },
          },
        ),
      );
      expect(error.fieldErrors, {'email': 'value is not a valid email address'});
      expect(error.userMessage, contains('email'));
    });

    test('signale une erreur réseau', () {
      final error = ApiException.fromDio(_dioError(type: DioExceptionType.connectionError));
      expect(error.isNetwork, isTrue);
      expect(error.userMessage, contains('Impossible de joindre le serveur'));
    });

    test('message générique pour une erreur serveur inconnue', () {
      final error = ApiException.fromDio(_dioError(status: 500, data: 'Internal Server Error'));
      expect(error.userMessage, 'Erreur du serveur. Réessayez plus tard.');
    });
  });

  test('Paginated lit items et pagination', () {
    final page = Paginated.fromJson({
      'items': [
        {'id': 'a'},
        {'id': 'b'},
      ],
      'pagination': {'total': 42, 'page': 1, 'page_size': 2, 'pages': 21},
    }, (json) => json['id'] as String);
    expect(page.items, ['a', 'b']);
    expect(page.total, 42);
    expect(page.hasMore, isTrue);
  });

  group('ServerUrlNotifier.normalize', () {
    test('ajoute le schéma et retire le slash final', () {
      expect(ServerUrlNotifier.normalize('185.215.167.79:8000/'), 'http://185.215.167.79:8000');
    });
    test('retire /api/v1 s\'il est saisi', () {
      expect(
        ServerUrlNotifier.normalize('https://api.exemple.com/api/v1'),
        'https://api.exemple.com',
      );
    });
    test('valeur vide = serveur par défaut', () {
      expect(ServerUrlNotifier.normalize('  '), kDefaultServerUrl);
    });
  });

  group('Fmt', () {
    test('salaire', () {
      expect(Fmt.salary(min: 45000, max: 55000, currency: 'EUR', period: 'year'), '45 k – 55 k EUR / an');
      expect(Fmt.salary(min: 600, currency: 'EUR', period: 'day'), '600 EUR / jour');
      expect(Fmt.salary(raw: 'Selon profil'), 'Selon profil');
      expect(Fmt.salary(), '—');
    });
    test('taille de fichier', () {
      expect(Fmt.fileSize(512), '512 o');
      expect(Fmt.fileSize(1536), '1,5 Ko');
      expect(Fmt.fileSize(5 * 1024 * 1024), '5,0 Mo');
    });
    test('date relative', () {
      final now = DateTime(2026, 9, 30, 12);
      expect(Fmt.relative(now.subtract(const Duration(minutes: 5)), now: now), 'il y a 5 min');
      expect(Fmt.relative(now.subtract(const Duration(hours: 3)), now: now), 'il y a 3 h');
      expect(Fmt.relative(now.subtract(const Duration(days: 1)), now: now), 'hier');
    });
    test('initiales', () {
      expect(Fmt.initials('bryan.garrix@exemple.com'), 'BG');
      expect(Fmt.initials('demo@example.com'), 'DE');
      expect(Fmt.initials(null), '?');
    });
  });

  group('ApplicationStatus', () {
    test('correspond aux valeurs de l\'API', () {
      expect(ApplicationStatus.fromApi('follow_up'), ApplicationStatus.followUp);
      expect(ApplicationStatus.fromApi('inconnu'), isNull);
    });
    test('l\'envoi n\'est possible que depuis « Prête »', () {
      final canSubmit = ApplicationStatus.values
          .where((s) => s.allowedTransitions.contains(ApplicationStatus.submitted))
          .toList();
      expect(canSubmit, [ApplicationStatus.ready]);
    });
    test('refusée et abandonnée sont finales', () {
      expect(ApplicationStatus.rejected.allowedTransitions, isEmpty);
      expect(ApplicationStatus.withdrawn.allowedTransitions, isEmpty);
    });
  });
}
