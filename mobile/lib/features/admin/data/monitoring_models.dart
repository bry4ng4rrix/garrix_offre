import '../../../core/models/enums.dart';
import '../../../core/utils/json.dart';
import 'source_models.dart';

/// État d'un service (`services.<nom>` de `GET /monitoring/system`).
class ServiceHealth {
  const ServiceHealth({required this.key, required this.status, this.latencyMs, this.workers});

  /// `api`, `postgres`, `redis`, `worker`, `n8n`...
  final String key;

  /// `ok`, `error`, `eager` (worker exécuté en synchrone)...
  final String status;
  final double? latencyMs;
  final int? workers;

  bool get isOk => status == 'ok';
  bool get isError => status == 'error';

  factory ServiceHealth.fromJson(String key, Map<String, dynamic> json) => ServiceHealth(
    key: key,
    status: json['status']?.toString() ?? 'unknown',
    latencyMs: parseDouble(json['latency_ms']),
    workers: parseInt(json['workers']),
  );
}

/// État du système (`GET /monitoring/system`).
class SystemStatus {
  const SystemStatus({
    this.version,
    this.environment,
    this.uptimeSeconds,
    this.services = const [],
    this.websocketConnections = 0,
    this.databaseSizeBytes,
    this.storageSizeBytes,
    this.jobsByStatus = const {},
    this.users = 0,
    this.aiProvider,
    this.notificationDelivery,
    this.telegramConfigured = false,
    this.emailConfigured = false,
  });

  final String? version;
  final String? environment;
  final int? uptimeSeconds;
  final List<ServiceHealth> services;
  final int websocketConnections;
  final int? databaseSizeBytes;
  final int? storageSizeBytes;
  final Map<String, int> jobsByStatus;
  final int users;
  final String? aiProvider;
  final String? notificationDelivery;
  final bool telegramConfigured;
  final bool emailConfigured;

  int get jobsTotal => jobsByStatus.values.fold(0, (sum, value) => sum + value);
  List<ServiceHealth> get failing => services.where((s) => s.isError).toList();
  bool get aiEnabled => aiProvider != null && aiProvider != 'none' && aiProvider!.isNotEmpty;

  factory SystemStatus.fromJson(Map<String, dynamic> json) {
    final services = parseMap(json['services']);
    return SystemStatus(
      version: json['version']?.toString(),
      environment: json['environment']?.toString(),
      uptimeSeconds: parseInt(json['uptime_seconds']),
      services: [
        for (final entry in services.entries)
          ServiceHealth.fromJson(entry.key, parseMap(entry.value)),
      ],
      websocketConnections: parseInt(json['websocket_connections']) ?? 0,
      databaseSizeBytes: parseInt(json['database_size_bytes']),
      storageSizeBytes: parseInt(json['storage_size_bytes']),
      jobsByStatus: parseCountMap(json['jobs_by_status']),
      users: parseInt(json['users']) ?? 0,
      aiProvider: json['ai_provider']?.toString(),
      notificationDelivery: json['notification_delivery']?.toString(),
      telegramConfigured: json['telegram_configured'] as bool? ?? false,
      emailConfigured: json['email_configured'] as bool? ?? false,
    );
  }
}

/// Statistiques d'une source sur 7 jours (`GET /monitoring/scraping` → `sources`).
class SourceStats {
  const SourceStats({
    required this.sourceId,
    required this.name,
    required this.typeValue,
    this.enabled = true,
    this.scrapingEnabled = false,
    this.lastRunAt,
    this.lastSuccessAt,
    this.lastError,
    this.runs7d = 0,
    this.failedRuns7d = 0,
    this.jobsCreated7d = 0,
  });

  final String sourceId;
  final String name;
  final String typeValue;
  final bool enabled;
  final bool scrapingEnabled;
  final DateTime? lastRunAt;
  final DateTime? lastSuccessAt;
  final String? lastError;
  final int runs7d;
  final int failedRuns7d;
  final int jobsCreated7d;

  String get typeLabel => SourceType.fromApi(typeValue)?.label ?? typeValue;
  bool get hasError => lastError != null && lastError!.trim().isNotEmpty;

  /// Source réellement suivie : collecte active ou activité récente.
  bool get isTracked => (enabled && scrapingEnabled) || runs7d > 0 || lastRunAt != null;

  factory SourceStats.fromJson(Map<String, dynamic> json) => SourceStats(
    sourceId: json['source_id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    typeValue: json['type']?.toString() ?? '',
    enabled: json['enabled'] as bool? ?? true,
    scrapingEnabled: json['scraping_enabled'] as bool? ?? false,
    lastRunAt: parseDate(json['last_run_at']),
    lastSuccessAt: parseDate(json['last_success_at']),
    lastError: json['last_error'] as String?,
    runs7d: parseInt(json['runs_7d']) ?? 0,
    failedRuns7d: parseInt(json['failed_runs_7d']) ?? 0,
    jobsCreated7d: parseInt(json['jobs_created_7d']) ?? 0,
  );
}

/// Appel reçu de n8n (`last_n8n_executions`).
class N8nExecution {
  const N8nExecution({
    this.endpoint,
    this.workflow,
    this.executionId,
    this.status,
    this.errorCode,
    this.summary = const {},
    this.receivedAt,
    this.durationMs,
  });

  final String? endpoint;
  final String? workflow;
  final String? executionId;
  final String? status;
  final String? errorCode;
  final Map<String, dynamic> summary;
  final DateTime? receivedAt;
  final int? durationMs;

  bool get isSuccess => status == 'success';

  factory N8nExecution.fromJson(Map<String, dynamic> json) => N8nExecution(
    endpoint: json['endpoint']?.toString(),
    workflow: json['workflow']?.toString(),
    executionId: json['execution_id']?.toString(),
    status: json['status']?.toString(),
    errorCode: json['error_code']?.toString(),
    summary: parseMap(json['summary']),
    receivedAt: parseDate(json['received_at']),
    durationMs: parseInt(json['duration_ms']),
  );
}

/// Vue d'ensemble des collectes (`GET /monitoring/scraping`).
class ScrapingOverview {
  const ScrapingOverview({
    this.runsByStatus7d = const {},
    this.sources = const [],
    this.recentRuns = const [],
    this.n8nExecutions = const [],
  });

  final Map<String, int> runsByStatus7d;
  final List<SourceStats> sources;
  final List<ScrapingRun> recentRuns;
  final List<N8nExecution> n8nExecutions;

  int get runs7d => runsByStatus7d.values.fold(0, (sum, value) => sum + value);

  factory ScrapingOverview.fromJson(Map<String, dynamic> json) => ScrapingOverview(
    runsByStatus7d: parseCountMap(json['runs_by_status_7d']),
    sources: parseMapList(json['sources']).map(SourceStats.fromJson).toList(),
    recentRuns: parseMapList(json['recent_runs']).map(ScrapingRun.fromJson).toList(),
    n8nExecutions: parseMapList(json['last_n8n_executions']).map(N8nExecution.fromJson).toList(),
  );
}

/// Résultat de `POST /jobs/maintenance/expire`.
class MaintenanceResult {
  const MaintenanceResult({this.expired = 0, this.archived = 0, this.staleRunsFailed = 0});

  final int expired;
  final int archived;
  final int staleRunsFailed;

  factory MaintenanceResult.fromJson(Map<String, dynamic> json) => MaintenanceResult(
    expired: parseInt(json['expired']) ?? 0,
    archived: parseInt(json['archived']) ?? 0,
    staleRunsFailed: parseInt(json['stale_runs_failed']) ?? 0,
  );
}

/// Résultat de `POST /matching/recalculate` (`queued` ou `done`).
class RecalculateResult {
  const RecalculateResult({required this.status, this.jobsMatched});

  final String status;
  final int? jobsMatched;

  bool get isQueued => status == 'queued';

  factory RecalculateResult.fromJson(Map<String, dynamic> json) => RecalculateResult(
    status: json['status']?.toString() ?? '',
    jobsMatched: parseInt(json['jobs_matched']),
  );
}

/// `{"active": 165, "new": 131}` → `Map<String, int>`.
Map<String, int> parseCountMap(Object? value) {
  final result = <String, int>{};
  parseMap(value).forEach((key, count) {
    final number = parseInt(count);
    if (number != null) result[key] = number;
  });
  return result;
}
