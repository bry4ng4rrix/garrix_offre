import 'package:flutter_test/flutter_test.dart';
import 'package:garrix_offre/core/models/enums.dart';
import 'package:garrix_offre/core/network/api_exception.dart';
import 'package:garrix_offre/features/admin/data/admin_labels.dart';
import 'package:garrix_offre/features/admin/data/audit_models.dart';
import 'package:garrix_offre/features/admin/data/directory_models.dart';
import 'package:garrix_offre/features/admin/data/monitoring_models.dart';
import 'package:garrix_offre/features/admin/data/source_models.dart';

/// Extraits réels de l'API locale (GET /sources, /scraping/runs, /monitoring/...).
final _sourceJson = <String, dynamic>{
  'id': '3006d77c-aad0-4cba-9327-8bf95d26935b',
  'name': 'Adzuna',
  'type': 'api',
  'category': 'services',
  'adapter': 'json_api',
  'fetch_mode': 'backend',
  'base_url': 'https://developer.adzuna.com',
  'enabled': false,
  'scraping_enabled': true,
  'priority': 5,
  'configuration': {
    'url': 'https://api.adzuna.com/v1/api/jobs/fr/search/1',
    'secret_query_params': {'app_id': 'SOURCE_ADZUNA_APP_ID'},
  },
  'rate_limit': 10,
  'terms_reviewed': false,
  'last_run_at': '2026-09-30T07:18:16.021617Z',
  'last_success_at': null,
  'last_error': 'HTTP 403',
  'notes': 'API officielle',
  'created_at': '2026-09-30T07:17:09.808119Z',
  'updated_at': '2026-09-30T07:17:09.808119Z',
};

final _runJson = <String, dynamic>{
  'id': '2c8a8cfa-99d1-45b0-a216-c6db47731f56',
  'source_id': '5a383d16-967e-42b6-96cc-01a01f5527f0',
  'source_name': 'Codeur.com',
  'trigger': 'n8n',
  'status': 'partial_success',
  'started_at': '2026-09-30T07:18:19.685341Z',
  'finished_at': '2026-09-30T07:18:32.205695Z',
  'jobs_found': 35,
  'jobs_created': 34,
  'jobs_updated': 1,
  'jobs_duplicates': 1,
  'jobs_invalid': 0,
  'error_message': null,
  'details': {
    'errors': ['Limit of 5 jobs per run reached'],
    'pages': 2,
  },
  'external_execution_id': null,
  'created_at': '2026-09-30T07:18:02.534140Z',
};

void main() {
  group('Source', () {
    test('lit SourceRead et ses énumérations', () {
      final source = Source.fromJson(_sourceJson);
      expect(source.name, 'Adzuna');
      expect(source.type, SourceType.api);
      expect(source.category, SourceCategory.services);
      expect(source.fetchMode, FetchMode.backend);
      expect(source.hasAdapter, isTrue);
      expect(source.enabled, isFalse);
      expect(source.scrapingEnabled, isTrue);
      expect(source.rateLimit, 10);
      expect(source.hasError, isTrue);
      expect(source.lastRunAt, isNotNull);
      expect(source.lastSuccessAt, isNull);
      expect(source.configuration['url'], startsWith('https://api.adzuna.com'));
      expect(source.copyWith(enabled: true).enabled, isTrue);
    });

    test('tolère une valeur inconnue et les champs absents', () {
      final source = Source.fromJson({'id': 'x', 'name': 'N', 'type': 'ftp'});
      expect(source.type, isNull);
      expect(source.typeLabel, 'ftp');
      expect(source.category, SourceCategory.jobs);
      expect(source.hasAdapter, isFalse);
      expect(source.configuration, isEmpty);
    });

    test('SourceInput.toJson envoie les valeurs API et vide les champs blancs', () {
      const input = SourceInput(
        name: '  Flux RSS  ',
        type: SourceType.rss,
        category: SourceCategory.clients,
        fetchMode: FetchMode.n8n,
        adapter: '',
        baseUrl: ' ',
        priority: 7,
        configuration: {'feed_url': 'https://example.com/rss'},
        notes: '',
      );
      final json = input.toJson();
      expect(json['name'], 'Flux RSS');
      expect(json['type'], 'rss');
      expect(json['category'], 'clients');
      expect(json['fetch_mode'], 'n8n');
      expect(json['adapter'], isNull);
      expect(json['base_url'], isNull);
      expect(json['notes'], isNull);
      expect(json['priority'], 7);
      expect(json['configuration'], {'feed_url': 'https://example.com/rss'});
    });
  });

  group('AdapterInfo', () {
    final adapter = AdapterInfo.fromJson({
      'key': 'rss_feed',
      'description': 'Flux RSS 2.0 / Atom public',
      'source_types': ['rss'],
      'respects_robots_txt': true,
      'configuration_schema': {
        'properties': {
          'feed_url': {'type': 'string', 'format': 'uri', 'title': 'Feed Url'},
          'company_name': {
            'anyOf': [
              {'type': 'string'},
              {'type': 'null'},
            ],
            'default': null,
          },
          'fields': {'type': 'object'},
          'max_items': {'type': 'integer', 'default': 50},
        },
        'required': ['feed_url', 'fields'],
      },
    });

    test('lit les champs du schéma de configuration', () {
      expect(adapter.supports(SourceType.rss), isTrue);
      expect(adapter.supports(SourceType.html), isFalse);
      final fields = adapter.fields;
      expect(fields.map((f) => f.name), ['feed_url', 'company_name', 'fields', 'max_items']);
      expect(fields.first.isRequired, isTrue);
      expect(fields[1].type, 'string');
      expect(fields[1].isRequired, isFalse);
    });

    test('construit un modèle de configuration', () {
      expect(adapter.template(), {'feed_url': '', 'fields': <String, dynamic>{}, 'max_items': 50});
    });
  });

  group('ScrapingRun', () {
    test('lit ScrapingRunRead (statut, déclencheur, durée, erreurs)', () {
      final run = ScrapingRun.fromJson(_runJson);
      expect(run.status, ScrapingRunStatus.partialSuccess);
      expect(run.trigger, ScrapingTrigger.n8n);
      expect(run.isActive, isFalse);
      expect(run.jobsFound, 35);
      expect(run.jobsCreated, 34);
      expect(run.duration!.inSeconds, 12);
      expect(run.detailErrors, ['Limit of 5 jobs per run reached']);
    });

    test('collecte en attente : active et sans durée', () {
      final run = ScrapingRun.fromJson({
        ..._runJson,
        'status': 'pending',
        'started_at': null,
        'finished_at': null,
        'details': {},
      });
      expect(run.isActive, isTrue);
      expect(run.duration, isNull);
      expect(run.detailErrors, isEmpty);
    });

    test('RunRequestResult et SourceTestResult', () {
      final request = RunRequestResult.fromJson({'run_id': 'abc', 'status': 'pending'});
      expect(request.runId, 'abc');
      expect(request.status, ScrapingRunStatus.pending);

      final result = SourceTestResult.fromJson({
        'pages_fetched': 1,
        'jobs_parsed': 5,
        'errors': ['Limit of 5 jobs per run reached'],
        'preview': [
          {
            'title': 'Montage vidéo',
            'company_name': null,
            'city': 'Paris',
            'country': 'France',
            'is_remote': true,
            'contract_type': 'freelance',
            'skills': [
              {'name': 'design', 'requirement': 'required'},
              {'name': 'video', 'requirement': 'required'},
            ],
            'published_at': '2026-09-30T08:43:14Z',
            'quality_issues': [],
          },
        ],
      });
      expect(result.jobsParsed, 5);
      expect(result.errors, hasLength(1));
      final job = result.preview.single;
      expect(job.title, 'Montage vidéo');
      expect(job.location, 'Paris, France');
      expect(job.skills, ['design', 'video']);
      expect(job.hasSalary, isFalse);
      expect(job.publishedAt, isNotNull);
    });
  });

  group('Monitoring', () {
    test('lit GET /monitoring/system', () {
      final status = SystemStatus.fromJson({
        'version': '1.0.0',
        'environment': 'development',
        'uptime_seconds': 238,
        'services': {
          'api': {'status': 'ok'},
          'postgres': {'status': 'ok', 'latency_ms': 0.9},
          'redis': {'status': 'ok', 'latency_ms': 0.2},
          'worker': {'status': 'error', 'workers': 0},
          'n8n': {'status': 'error', 'latency_ms': 50.4},
        },
        'websocket_connections': 0,
        'database_size_bytes': 14333619,
        'storage_size_bytes': 45,
        'jobs_by_status': {'active': 165, 'new': 131},
        'users': 1,
        'ai_provider': 'none',
        'notification_delivery': 'backend',
        'telegram_configured': false,
        'email_configured': true,
      });
      expect(status.services.map((s) => s.key), ['api', 'postgres', 'redis', 'worker', 'n8n']);
      expect(status.services[1].latencyMs, 0.9);
      expect(status.services[3].workers, 0);
      expect(status.failing.map((s) => s.key), ['worker', 'n8n']);
      expect(status.jobsTotal, 296);
      expect(status.aiEnabled, isFalse);
      expect(status.emailConfigured, isTrue);
      expect(status.databaseSizeBytes, 14333619);
    });

    test('lit GET /monitoring/scraping', () {
      final overview = ScrapingOverview.fromJson({
        'runs_by_status_7d': {'success': 6, 'failed': 1},
        'sources': [
          {
            'source_id': 's1',
            'name': 'Codeur.com',
            'type': 'rss',
            'enabled': true,
            'scraping_enabled': true,
            'last_run_at': '2026-09-30T07:18:32.205666Z',
            'last_error': null,
            'runs_7d': 1,
            'failed_runs_7d': 0,
            'jobs_created_7d': 34,
          },
          {'source_id': 's2', 'name': 'APEC', 'type': 'webhook', 'enabled': true},
        ],
        'recent_runs': [_runJson],
        'last_n8n_executions': [
          {
            'endpoint': 'sources.run',
            'workflow': 'job-scraping',
            'execution_id': '1',
            'status': 'success',
            'received_at': '2026-09-30T07:18:02.912583Z',
            'duration_ms': 395,
          },
        ],
      });
      expect(overview.runs7d, 7);
      expect(overview.sources.first.isTracked, isTrue);
      expect(overview.sources.last.isTracked, isFalse);
      expect(overview.sources.first.typeLabel, 'Flux RSS');
      expect(overview.recentRuns.single.sourceName, 'Codeur.com');
      expect(overview.n8nExecutions.single.isSuccess, isTrue);
      expect(overview.n8nExecutions.single.durationMs, 395);
    });

    test('résultats de maintenance et de recalcul', () {
      final maintenance = MaintenanceResult.fromJson({'expired': 3, 'archived': 2});
      expect(maintenance.expired, 3);
      expect(maintenance.staleRunsFailed, 0);
      final queued = RecalculateResult.fromJson({'status': 'queued', 'jobs_matched': null});
      expect(queued.isQueued, isTrue);
      final done = RecalculateResult.fromJson({'status': 'done', 'jobs_matched': 296});
      expect(done.isQueued, isFalse);
      expect(done.jobsMatched, 296);
    });
  });

  group('Journal d\'audit', () {
    test('lit AuditLogRead', () {
      final log = AuditLog.fromJson({
        'id': 'b2431d7c',
        'actor_type': 'user',
        'actor_id': 'cc2ec1d7',
        'action': 'application.status_changed',
        'entity_type': 'application',
        'entity_id': '17af2549',
        'details': {'to': 'ready', 'from': 'preparing'},
        'created_at': '2026-09-30T08:43:54.085424Z',
      });
      expect(log.actorType, ActorType.user);
      expect(log.details['to'], 'ready');
      expect(auditActionLabel(log.action), 'Statut de candidature modifié');
      expect(auditActionLabel('custom.action'), 'custom.action');
      expect(entityTypeLabel('scraping_run'), 'Collecte');
    });
  });

  group('Entreprises et recruteurs', () {
    test('lit CompanyRead avec la provenance des champs', () {
      final company = Company.fromJson({
        'id': 'c1',
        'name': 'A.Team',
        'industry': 'Logiciel',
        'city': 'Paris',
        'country': 'France',
        'data_source': 'scraping',
        'source_id': 's1',
        'source_url': 'https://weworkremotely.com/remote-jobs/a-team',
        'field_sources': {'email': 'https://a.team/contact'},
      });
      expect(company.dataSource, DataOrigin.scraping);
      expect(company.subtitle, 'Logiciel · Paris, France');
      expect(company.fieldSources['email'], 'https://a.team/contact');
      expect(company.editableValues['city'], 'Paris');
    });

    test('lit RecruiterRead et calcule le nom affiché', () {
      final recruiter = Recruiter.fromJson({
        'id': 'r1',
        'name': 'Jean Rakoto',
        'first_name': 'Jean',
        'last_name': 'Rakoto',
        'email': 'jean@example.com',
        'contact_source': 'company_website',
        'source_url': 'https://example.com/contact',
      });
      expect(recruiter.displayName, 'Jean Rakoto');
      expect(recruiter.contactSource, ContactSource.companyWebsite);
      expect(recruiter.hasContact, isTrue);
      // Le nom affiché calculé n'est pas renvoyé comme champ modifiable.
      expect(recruiter.editableValues['name'], isNull);
      expect(Recruiter.fromJson({'id': 'r2'}).displayName, 'Recruteur sans nom');
    });

    test('changedFields n\'envoie que les modifications (vide = effacer)', () {
      final original = {'name': 'Zeta', 'city': 'Paris', 'website': 'https://zeta.io/'};
      final edited = {'name': 'Zeta', 'city': ' Lyon ', 'website': ''};
      expect(changedFields(original, edited), {'city': 'Lyon', 'website': null});
      expect(filledFields({'name': ' Zeta ', 'city': '', 'website': null}), {'name': 'Zeta'});
    });

    test('checkContactProvenance applique la règle RG-07', () {
      expect(checkContactProvenance(email: 'a@b.co'), isNotNull);
      expect(
        checkContactProvenance(email: 'a@b.co', contactSource: ContactSource.jobListing),
        isNull,
      );
      expect(
        checkContactProvenance(phone: '+261 34', contactSource: ContactSource.publicProfile),
        isNotNull,
      );
      expect(
        checkContactProvenance(
          phone: '+261 34',
          contactSource: ContactSource.publicProfile,
          sourceUrl: 'https://example.com/profil',
        ),
        isNull,
      );
      expect(checkContactProvenance(), isNull);
    });
  });

  group('Messages d\'erreur', () {
    test('configuration de source invalide : détail par champ', () {
      const error = ApiException(
        statusCode: 422,
        code: 'INVALID_SOURCE_CONFIGURATION',
        message: 'Invalid source configuration',
        details: [
          {'field': 'feed_url', 'message': 'Field required'},
        ],
      );
      expect(
        adminErrorMessage(error),
        'Configuration invalide pour cet adapter.\nfeed_url : Field required',
      );
    });

    test('provenance manquante renvoyée par la validation', () {
      const error = ApiException(
        statusCode: 422,
        code: 'VALIDATION_ERROR',
        message: 'Invalid request data',
        details: [
          {
            'field': '',
            'message': 'Value error, contact_source is required when an email is provided',
          },
        ],
      );
      expect(adminErrorMessage(error), contains('provenance'));
    });

    test('codes connus du cœur et codes propres à l\'administration', () {
      const exists = ApiException(statusCode: 409, code: 'SOURCE_EXISTS', message: 'x');
      expect(adminErrorMessage(exists), 'Une source porte déjà ce nom.');
      const self = ApiException(statusCode: 422, code: 'CANNOT_MODIFY_SELF', message: 'x');
      expect(adminErrorMessage(self), contains('propre compte'));
    });
  });
}
