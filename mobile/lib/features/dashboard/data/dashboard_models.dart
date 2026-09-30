import '../../../core/models/enums.dart';
import '../../../core/utils/json.dart';

/// Compte par statut de candidature (`{"submitted": 3, ...}`), statuts inconnus ignorés.
Map<ApplicationStatus, int> _countsByStatus(Object? value) {
  final result = <ApplicationStatus, int>{};
  parseMap(value).forEach((key, count) {
    final status = ApplicationStatus.fromApi(key);
    final n = parseInt(count);
    if (status != null && n != null && n > 0) result[status] = n;
  });
  return result;
}

/// Vue d'ensemble du tableau de bord (`GET /monitoring/overview`).
class DashboardOverview {
  const DashboardOverview({
    this.date,
    this.jobsFoundToday = 0,
    this.newJobsToday = 0,
    this.jobsAnalyzedToday = 0,
    this.matchingJobsToday = 0,
    this.matchingJobsTotal = 0,
    this.matchingThreshold = 70,
    this.applicationsTotal = 0,
    this.applicationsByStatus = const {},
    this.responsesTotal = 0,
    this.responsesLast7Days = 0,
    this.scrapingErrors24h = 0,
    this.unreadNotifications = 0,
    this.services = const {},
  });

  final DateTime? date;

  /// Offres vues par les collectes aujourd'hui (nouvelles ou déjà connues).
  final int jobsFoundToday;
  final int newJobsToday;
  final int jobsAnalyzedToday;
  final int matchingJobsToday;
  final int matchingJobsTotal;
  final int matchingThreshold;
  final int applicationsTotal;
  final Map<ApplicationStatus, int> applicationsByStatus;
  final int responsesTotal;
  final int responsesLast7Days;
  final int scrapingErrors24h;
  final int unreadNotifications;

  /// État des services : `{"api": "ok", "postgres": "ok", "redis": "error"}`.
  final Map<String, String> services;

  bool get allServicesOk => services.values.every((status) => status == 'ok');

  factory DashboardOverview.fromJson(Map<String, dynamic> json) => DashboardOverview(
    date: parseDate(json['date']),
    jobsFoundToday: parseInt(json['jobs_found_today']) ?? 0,
    newJobsToday: parseInt(json['new_jobs_today']) ?? 0,
    jobsAnalyzedToday: parseInt(json['jobs_analyzed_today']) ?? 0,
    matchingJobsToday: parseInt(json['matching_jobs_today']) ?? 0,
    matchingJobsTotal: parseInt(json['matching_jobs_total']) ?? 0,
    matchingThreshold: parseInt(json['matching_threshold']) ?? 70,
    applicationsTotal: parseInt(json['applications_total']) ?? 0,
    applicationsByStatus: _countsByStatus(json['applications_by_status']),
    responsesTotal: parseInt(json['responses_total']) ?? 0,
    responsesLast7Days: parseInt(json['responses_last_7_days']) ?? 0,
    scrapingErrors24h: parseInt(json['scraping_errors_24h']) ?? 0,
    unreadNotifications: parseInt(json['unread_notifications']) ?? 0,
    services: {
      for (final entry in parseMap(json['services']).entries)
        entry.key: entry.value is Map
            ? ((entry.value as Map)['status']?.toString() ?? 'unknown')
            : entry.value.toString(),
    },
  );
}

/// Statistiques des candidatures (`GET /monitoring/applications`).
class ApplicationStats {
  const ApplicationStats({
    this.total = 0,
    this.byStatus = const {},
    this.submittedTotal = 0,
    this.withResponse = 0,
    this.responseRate = 0,
    this.averageResponseDays,
    this.interviews = 0,
    this.offers = 0,
    this.responsesReceived = 0,
    this.submittedPerWeek = const {},
  });

  final int total;
  final Map<ApplicationStatus, int> byStatus;
  final int submittedTotal;
  final int withResponse;

  /// 0.0 à 1.0
  final double responseRate;
  final double? averageResponseDays;
  final int interviews;
  final int offers;
  final int responsesReceived;

  /// Semaine ISO (`2026-W39`) -> candidatures envoyées.
  final Map<String, int> submittedPerWeek;

  factory ApplicationStats.fromJson(Map<String, dynamic> json) => ApplicationStats(
    total: parseInt(json['total']) ?? 0,
    byStatus: _countsByStatus(json['by_status']),
    submittedTotal: parseInt(json['submitted_total']) ?? 0,
    withResponse: parseInt(json['with_response']) ?? 0,
    responseRate: parseDouble(json['response_rate']) ?? 0,
    averageResponseDays: parseDouble(json['average_response_days']),
    interviews: parseInt(json['interviews']) ?? 0,
    offers: parseInt(json['offers']) ?? 0,
    responsesReceived: parseInt(json['responses_received']) ?? 0,
    submittedPerWeek: {
      for (final entry in parseMap(json['submitted_per_week']).entries)
        entry.key: parseInt(entry.value) ?? 0,
    },
  );
}
