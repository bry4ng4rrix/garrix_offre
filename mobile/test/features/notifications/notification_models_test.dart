import 'package:flutter_test/flutter_test.dart';
import 'package:garrix_offre/core/models/enums.dart';
import 'package:garrix_offre/core/router/routes.dart';
import 'package:garrix_offre/features/notifications/data/notification_models.dart';
import 'package:garrix_offre/features/notifications/widgets/notification_filter_bar.dart';

/// Charge utile réelle de `GET /notifications` (API locale).
Map<String, dynamic> _json({
  String type = 'high_match',
  Map<String, dynamic> data = const {},
  bool isRead = false,
}) => {
  'id': '86e8ca04-fcf2-4234-a561-8ac91049694a',
  'type': type,
  'title': 'Offre compatible à 90% : Développeur Full Stack',
  'message': 'Développeur Full Stack — Exemple SAS',
  'data': data,
  'is_read': isRead,
  'read_at': null,
  'delivered_channels': ['telegram', 'email'],
  'created_at': '2026-09-30T08:40:06.316794Z',
};

AppNotification _notification(String type, Map<String, dynamic> data) =>
    AppNotification.fromJson(_json(type: type, data: data));

void main() {
  group('AppNotification', () {
    test('lit une notification complète', () {
      final n = AppNotification.fromJson(
        _json(
          data: {
            'job_id': '0707986c-5bf8-434c-a30f-ddf5e2de01a6',
            'score': 90,
            'matched_skills': ['Python', 'React'],
          },
        ),
      );
      expect(n.id, '86e8ca04-fcf2-4234-a561-8ac91049694a');
      expect(n.type, NotificationType.highMatch);
      expect(n.typeValue, 'high_match');
      expect(n.isRead, isFalse);
      expect(n.readAt, isNull);
      expect(n.createdAt, DateTime.utc(2026, 9, 30, 8, 40, 6, 316, 794).toLocal());
      expect(n.score, 90);
      expect(n.deliveredLabel, 'Telegram, Email');
      expect(n.data['matched_skills'], ['Python', 'React']);
    });

    test('tolère un type inconnu et des champs absents', () {
      final n = AppNotification.fromJson({'id': 'x', 'type': 'nouveau_type'});
      expect(n.type, isNull);
      expect(n.typeValue, 'nouveau_type');
      expect(n.title, '');
      expect(n.data, isEmpty);
      expect(n.deliveredChannels, isEmpty);
      expect(n.score, isNull);
      expect(n.deliveredLabel, '');
    });

    test('markedRead marque comme lue sans toucher au reste', () {
      final n = AppNotification.fromJson(_json());
      final read = n.markedRead();
      expect(read.isRead, isTrue);
      expect(read.readAt, isNotNull);
      expect(read.id, n.id);
      expect(read.title, n.title);
      expect(read.type, n.type);
    });
  });

  group('notificationLink', () {
    test('offre très compatible -> détail de l\'offre', () {
      final link = notificationLink(_notification('high_match', {'job_id': 'job-1'}));
      expect(link?.location, Routes.job('job-1'));
      expect(link?.switchTab, isFalse);
    });

    test('nouvelles offres : une seule -> détail, plusieurs -> onglet Offres', () {
      final one = notificationLink(
        _notification('new_job', {
          'count': 1,
          'job_ids': ['job-1'],
        }),
      );
      expect(one?.location, Routes.job('job-1'));

      final many = notificationLink(
        _notification('new_job', {
          'count': 3,
          'job_ids': ['a', 'b', 'c'],
        }),
      );
      expect(many?.location, Routes.jobs);
      expect(many?.switchTab, isTrue);
    });

    test('statut de candidature -> détail de la candidature (même sans job_id)', () {
      final link = notificationLink(
        _notification('application_status', {
          'application_id': 'app-1',
          'job_id': null,
          'status': 'submitted',
        }),
      );
      expect(link?.location, Routes.application('app-1'));
    });

    test('réponse recruteur : candidature liée, sinon liste des réponses', () {
      expect(
        notificationLink(
          _notification('recruiter_response', {'application_id': 'app-1', 'response_id': 'r'}),
        )?.location,
        Routes.application('app-1'),
      );
      expect(
        notificationLink(
          _notification('recruiter_response', {'application_id': null, 'response_id': 'r'}),
        )?.location,
        Routes.recruiterResponses,
      );
    });

    test('erreur de collecte et monitoring : réservés aux administrateurs', () {
      final scraping = _notification('scraping_error', {'source_id': 'src-1', 'run_id': 'run'});
      expect(notificationLink(scraping), isNull);
      expect(notificationLink(scraping, isAdmin: true)?.location, Routes.adminSource('src-1'));
      expect(
        notificationLink(_notification('scraping_error', {}), isAdmin: true)?.location,
        Routes.adminRuns,
      );

      final monitoring = _notification('monitoring', {'level': 'warning'});
      expect(notificationLink(monitoring), isNull);
      expect(notificationLink(monitoring, isAdmin: true)?.location, Routes.adminSystem);
    });

    test('notification système sans données -> aucune destination', () {
      expect(notificationLink(_notification('system', {})), isNull);
      expect(notificationLink(_notification('system', {'job_id': '  '})), isNull);
    });
  });

  group('NotificationSettings', () {
    const payload = {
      'telegram_enabled': true,
      'telegram_chat_id': null,
      'email_enabled': false,
      'email_to': null,
      'external_types': [
        'high_match',
        'application_status',
        'recruiter_response',
        'scraping_error',
        'system',
        'monitoring',
        'inconnu',
      ],
      'telegram_configured': false,
      'email_configured': true,
    };

    test('lit les préférences (types inconnus ignorés)', () {
      final settings = NotificationSettings.fromJson(payload);
      expect(settings.telegramEnabled, isTrue);
      expect(settings.telegramChatId, isNull);
      expect(settings.emailEnabled, isFalse);
      expect(settings.emailTo, isNull);
      expect(settings.telegramConfigured, isFalse);
      expect(settings.emailConfigured, isTrue);
      expect(settings.externalTypes, {
        NotificationType.highMatch,
        NotificationType.applicationStatus,
        NotificationType.recruiterResponse,
        NotificationType.scrapingError,
        NotificationType.system,
        NotificationType.monitoring,
      });
    });

    test('toUpdateJson : champs vides à null, types dans l\'ordre de l\'API', () {
      const settings = NotificationSettings(
        telegramEnabled: true,
        telegramChatId: '  ',
        emailEnabled: true,
        emailTo: ' moi@exemple.com ',
        externalTypes: {NotificationType.system, NotificationType.newJob},
      );
      expect(settings.toUpdateJson(), {
        'telegram_enabled': true,
        'telegram_chat_id': null,
        'email_enabled': true,
        'email_to': 'moi@exemple.com',
        'external_types': ['new_job', 'system'],
      });
    });

    test('format du chat id Telegram (même règle que le serveur)', () {
      expect(telegramChatIdPattern.hasMatch('123456789'), isTrue);
      expect(telegramChatIdPattern.hasMatch('-1001234567890'), isTrue);
      expect(telegramChatIdPattern.hasMatch('@mon_canal'), isTrue);
      expect(telegramChatIdPattern.hasMatch('abc x'), isFalse);
      expect(telegramChatIdPattern.hasMatch('12 34'), isFalse);
    });
  });

  group('Filtres', () {
    test('égalité (utilisée comme clé de rechargement de la liste)', () {
      expect(
        const NotificationFilter(unreadOnly: true, type: NotificationType.newJob),
        const NotificationFilter(unreadOnly: true, type: NotificationType.newJob),
      );
      expect(const NotificationFilter(unreadOnly: true), isNot(const NotificationFilter()));
      expect(const NotificationFilter().isEmpty, isTrue);
    });

    test('types d\'administration masqués pour un utilisateur', () {
      final user = filterableTypes(isAdmin: false);
      expect(user, isNot(contains(NotificationType.scrapingError)));
      expect(user, isNot(contains(NotificationType.monitoring)));
      expect(filterableTypes(isAdmin: true), NotificationType.values);
    });
  });
}
