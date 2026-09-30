import 'package:flutter_test/flutter_test.dart';
import 'package:garrix_offre/core/models/enums.dart';
import 'package:garrix_offre/features/dashboard/data/dashboard_models.dart';
import 'package:garrix_offre/features/dashboard/widgets/dashboard_sections.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  test('DashboardOverview lit GET /monitoring/overview', () {
    // Réponse réelle de l'API locale (exécutions n8n retirées).
    final overview = DashboardOverview.fromJson({
      'date': '2026-09-30',
      'jobs_found_today': 305,
      'new_jobs_today': 296,
      'jobs_analyzed_today': 296,
      'matching_jobs_today': 2,
      'matching_jobs_total': 2,
      'matching_threshold': 70,
      'applications_total': 3,
      'applications_by_status': {'preparing': 2, 'interview': 1, 'unknown_status': 4},
      'responses_total': 1,
      'responses_last_7_days': 1,
      'scraping_errors_24h': 0,
      'unread_notifications': 2,
      'last_n8n_executions': [],
      'services': {'api': 'ok', 'postgres': 'ok', 'redis': 'error'},
    });
    expect(overview.date, DateTime(2026, 9, 30));
    expect(overview.jobsFoundToday, 305);
    expect(overview.newJobsToday, 296);
    expect(overview.matchingThreshold, 70);
    expect(overview.applicationsByStatus, {
      ApplicationStatus.preparing: 2,
      ApplicationStatus.interview: 1,
    });
    expect(overview.unreadNotifications, 2);
    expect(overview.services['redis'], 'error');
    expect(overview.allServicesOk, isFalse);
  });

  test('DashboardOverview : valeurs par défaut et services détaillés', () {
    final overview = DashboardOverview.fromJson({
      'services': {
        'api': {'status': 'ok'},
        'postgres': {'status': 'ok', 'latency_ms': 1.2},
      },
    });
    expect(overview.matchingThreshold, 70);
    expect(overview.applicationsTotal, 0);
    expect(overview.applicationsByStatus, isEmpty);
    expect(overview.services, {'api': 'ok', 'postgres': 'ok'});
    expect(overview.allServicesOk, isTrue);
  });

  test('ApplicationStats lit GET /monitoring/applications', () {
    final stats = ApplicationStats.fromJson({
      'total': 4,
      'by_status': {'submitted': 2, 'offer': 1, 'rejected': 1},
      'submitted_total': 4,
      'with_response': 2,
      'response_rate': 0.5,
      'average_response_days': 3.5,
      'interviews': 1,
      'offers': 1,
      'submitted_per_week': {'2026-W39': 3, '2026-W40': 1},
      'responses_received': 2,
    });
    expect(stats.total, 4);
    expect(stats.byStatus[ApplicationStatus.submitted], 2);
    expect(stats.responseRate, 0.5);
    expect(stats.averageResponseDays, 3.5);
    expect(stats.submittedPerWeek['2026-W39'], 3);
  });

  test('ApplicationStats vide (compte neuf)', () {
    final stats = ApplicationStats.fromJson({
      'total': 0,
      'by_status': {},
      'submitted_total': 0,
      'with_response': 0,
      'response_rate': 0.0,
      'average_response_days': null,
      'interviews': 0,
      'offers': 0,
      'submitted_per_week': {},
      'responses_received': 0,
    });
    expect(stats.byStatus, isEmpty);
    expect(stats.averageResponseDays, isNull);
    expect(stats.responseRate, 0);
  });

  test('todayLabel : date en toutes lettres, majuscule initiale', () {
    expect(todayLabel(DateTime(2026, 9, 30)), 'Mercredi 30 septembre');
  });
}
