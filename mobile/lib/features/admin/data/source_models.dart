import '../../../core/models/enums.dart';
import '../../../core/utils/json.dart';

/// Source d'offres (`SourceRead`).
class Source {
  const Source({
    required this.id,
    required this.name,
    required this.typeValue,
    required this.categoryValue,
    required this.fetchModeValue,
    this.adapter,
    this.baseUrl,
    this.enabled = true,
    this.scrapingEnabled = false,
    this.priority = 5,
    this.configuration = const {},
    this.rateLimit,
    this.termsReviewed = false,
    this.lastRunAt,
    this.lastSuccessAt,
    this.lastError,
    this.notes,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;

  /// Valeurs brutes de l'API (conservées si l'énumération est inconnue de l'app).
  final String typeValue;
  final String categoryValue;
  final String fetchModeValue;
  final String? adapter;
  final String? baseUrl;
  final bool enabled;
  final bool scrapingEnabled;
  final int priority;
  final Map<String, dynamic> configuration;
  final int? rateLimit;
  final bool termsReviewed;
  final DateTime? lastRunAt;
  final DateTime? lastSuccessAt;
  final String? lastError;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  SourceType? get type => SourceType.fromApi(typeValue);
  SourceCategory? get category => SourceCategory.fromApi(categoryValue);
  FetchMode? get fetchMode => FetchMode.fromApi(fetchModeValue);

  String get typeLabel => type?.label ?? typeValue;
  String get categoryLabel => category?.label ?? categoryValue;
  String get fetchModeLabel => fetchMode?.label ?? fetchModeValue;

  /// Le serveur ne sait collecter que les sources ayant un adapter.
  bool get hasAdapter => adapter != null && adapter!.isNotEmpty;

  /// Dernière collecte en erreur (erreur plus récente que le dernier succès).
  bool get hasError => lastError != null && lastError!.trim().isNotEmpty;

  factory Source.fromJson(Map<String, dynamic> json) => Source(
    id: json['id'] as String,
    name: json['name']?.toString() ?? '',
    typeValue: json['type']?.toString() ?? '',
    categoryValue: json['category']?.toString() ?? 'jobs',
    fetchModeValue: json['fetch_mode']?.toString() ?? 'backend',
    adapter: json['adapter'] as String?,
    baseUrl: json['base_url'] as String?,
    enabled: json['enabled'] as bool? ?? true,
    scrapingEnabled: json['scraping_enabled'] as bool? ?? false,
    priority: parseInt(json['priority']) ?? 5,
    configuration: parseMap(json['configuration']),
    rateLimit: parseInt(json['rate_limit']),
    termsReviewed: json['terms_reviewed'] as bool? ?? false,
    lastRunAt: parseDate(json['last_run_at']),
    lastSuccessAt: parseDate(json['last_success_at']),
    lastError: json['last_error'] as String?,
    notes: json['notes'] as String?,
    createdAt: parseDate(json['created_at']),
    updatedAt: parseDate(json['updated_at']),
  );

  Source copyWith({bool? enabled, bool? scrapingEnabled, bool? termsReviewed}) => Source(
    id: id,
    name: name,
    typeValue: typeValue,
    categoryValue: categoryValue,
    fetchModeValue: fetchModeValue,
    adapter: adapter,
    baseUrl: baseUrl,
    enabled: enabled ?? this.enabled,
    scrapingEnabled: scrapingEnabled ?? this.scrapingEnabled,
    priority: priority,
    configuration: configuration,
    rateLimit: rateLimit,
    termsReviewed: termsReviewed ?? this.termsReviewed,
    lastRunAt: lastRunAt,
    lastSuccessAt: lastSuccessAt,
    lastError: lastError,
    notes: notes,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// Données saisies dans le formulaire d'une source (`SourceCreate` / `SourceUpdate`).
class SourceInput {
  const SourceInput({
    required this.name,
    required this.type,
    required this.category,
    required this.fetchMode,
    this.adapter,
    this.baseUrl,
    this.enabled = true,
    this.scrapingEnabled = false,
    this.priority = 5,
    this.configuration = const {},
    this.rateLimit,
    this.termsReviewed = false,
    this.notes,
  });

  final String name;
  final SourceType type;
  final SourceCategory category;
  final FetchMode fetchMode;
  final String? adapter;
  final String? baseUrl;
  final bool enabled;
  final bool scrapingEnabled;
  final int priority;
  final Map<String, dynamic> configuration;
  final int? rateLimit;
  final bool termsReviewed;
  final String? notes;

  /// Corps complet : valable pour la création comme pour la modification (PUT).
  Map<String, dynamic> toJson() => {
    'name': name.trim(),
    'type': type.apiValue,
    'category': category.apiValue,
    'fetch_mode': fetchMode.apiValue,
    'adapter': _blankToNull(adapter),
    'base_url': _blankToNull(baseUrl),
    'enabled': enabled,
    'scraping_enabled': scrapingEnabled,
    'priority': priority,
    'configuration': configuration,
    'rate_limit': rateLimit,
    'terms_reviewed': termsReviewed,
    'notes': _blankToNull(notes),
  };
}

String? _blankToNull(String? value) {
  final text = value?.trim();
  return (text == null || text.isEmpty) ? null : text;
}

/// Champ de configuration d'un adapter (tiré de son schéma JSON).
class AdapterField {
  const AdapterField({
    required this.name,
    required this.type,
    this.title,
    this.description,
    this.isRequired = false,
    this.defaultValue,
    this.hasDefault = false,
  });

  final String name;

  /// `string`, `integer`, `number`, `boolean`, `object`, `array` (ou `any`).
  final String type;
  final String? title;
  final String? description;
  final bool isRequired;
  final Object? defaultValue;
  final bool hasDefault;
}

/// Adapter de collecte disponible côté serveur (`AdapterInfo`).
class AdapterInfo {
  const AdapterInfo({
    required this.key,
    required this.description,
    this.sourceTypes = const [],
    this.respectsRobotsTxt = false,
    this.configurationSchema = const {},
  });

  final String key;
  final String description;
  final List<String> sourceTypes;
  final bool respectsRobotsTxt;
  final Map<String, dynamic> configurationSchema;

  bool supports(SourceType? type) => type != null && sourceTypes.contains(type.apiValue);

  factory AdapterInfo.fromJson(Map<String, dynamic> json) => AdapterInfo(
    key: json['key']?.toString() ?? '',
    description: json['description']?.toString() ?? '',
    sourceTypes: parseStringList(json['source_types']),
    respectsRobotsTxt: json['respects_robots_txt'] as bool? ?? false,
    configurationSchema: parseMap(json['configuration_schema']),
  );

  /// Champs de la configuration, dans l'ordre du schéma.
  List<AdapterField> get fields {
    final properties = parseMap(configurationSchema['properties']);
    final required = parseStringList(configurationSchema['required']).toSet();
    return [
      for (final entry in properties.entries)
        () {
          final spec = parseMap(entry.value);
          return AdapterField(
            name: entry.key,
            type: _schemaType(spec),
            title: spec['title'] as String?,
            description: spec['description'] as String?,
            isRequired: required.contains(entry.key),
            defaultValue: spec['default'],
            hasDefault: spec.containsKey('default'),
          );
        }(),
    ];
  }

  /// Modèle de configuration : champs obligatoires et valeurs par défaut.
  Map<String, dynamic> template() {
    final result = <String, dynamic>{};
    for (final field in fields) {
      if (field.hasDefault && field.defaultValue != null) {
        result[field.name] = field.defaultValue;
      } else if (field.isRequired) {
        result[field.name] = switch (field.type) {
          'object' => <String, dynamic>{},
          'array' => <dynamic>[],
          'integer' || 'number' => 0,
          'boolean' => false,
          _ => '',
        };
      }
    }
    return result;
  }

  static String _schemaType(Map<String, dynamic> spec) {
    final type = spec['type'];
    if (type is String) return type;
    // `anyOf: [{type: string}, {type: null}]` → string.
    for (final option in parseMapList(spec['anyOf'])) {
      final t = option['type'];
      if (t is String && t != 'null') return t;
    }
    return 'any';
  }
}

/// Collecte (`ScrapingRunRead`).
class ScrapingRun {
  const ScrapingRun({
    required this.id,
    required this.sourceId,
    this.sourceName,
    required this.triggerValue,
    required this.statusValue,
    this.startedAt,
    this.finishedAt,
    this.jobsFound = 0,
    this.jobsCreated = 0,
    this.jobsUpdated = 0,
    this.jobsDuplicates = 0,
    this.jobsInvalid = 0,
    this.errorMessage,
    this.details = const {},
    this.externalExecutionId,
    this.createdAt,
  });

  final String id;
  final String sourceId;
  final String? sourceName;
  final String triggerValue;
  final String statusValue;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final int jobsFound;
  final int jobsCreated;
  final int jobsUpdated;
  final int jobsDuplicates;
  final int jobsInvalid;
  final String? errorMessage;
  final Map<String, dynamic> details;
  final String? externalExecutionId;
  final DateTime? createdAt;

  ScrapingRunStatus? get status => ScrapingRunStatus.fromApi(statusValue);
  ScrapingTrigger? get trigger => ScrapingTrigger.fromApi(triggerValue);
  bool get isActive => status?.isActive ?? false;

  /// Durée d'exécution (null tant que la collecte n'est pas terminée).
  Duration? get duration {
    if (startedAt == null || finishedAt == null) return null;
    final value = finishedAt!.difference(startedAt!);
    return value.isNegative ? null : value;
  }

  /// Erreurs non bloquantes rapportées dans `details.errors`.
  List<String> get detailErrors => parseStringList(details['errors']);

  factory ScrapingRun.fromJson(Map<String, dynamic> json) => ScrapingRun(
    id: json['id'] as String,
    sourceId: json['source_id']?.toString() ?? '',
    sourceName: json['source_name'] as String?,
    triggerValue: json['trigger']?.toString() ?? '',
    statusValue: json['status']?.toString() ?? '',
    startedAt: parseDate(json['started_at']),
    finishedAt: parseDate(json['finished_at']),
    jobsFound: parseInt(json['jobs_found']) ?? 0,
    jobsCreated: parseInt(json['jobs_created']) ?? 0,
    jobsUpdated: parseInt(json['jobs_updated']) ?? 0,
    jobsDuplicates: parseInt(json['jobs_duplicates']) ?? 0,
    jobsInvalid: parseInt(json['jobs_invalid']) ?? 0,
    errorMessage: json['error_message'] as String?,
    details: parseMap(json['details']),
    externalExecutionId: json['external_execution_id'] as String?,
    createdAt: parseDate(json['created_at']),
  );
}

/// Réponse de `POST /sources/{id}/run`.
class RunRequestResult {
  const RunRequestResult({required this.runId, required this.statusValue});

  final String runId;
  final String statusValue;

  ScrapingRunStatus? get status => ScrapingRunStatus.fromApi(statusValue);

  factory RunRequestResult.fromJson(Map<String, dynamic> json) => RunRequestResult(
    runId: json['run_id']?.toString() ?? '',
    statusValue: json['status']?.toString() ?? '',
  );
}

/// Offre normalisée renvoyée par le test d'une source (`NormalizedJob`, champs utiles).
class TestedJob {
  const TestedJob({
    required this.title,
    this.companyName,
    this.locationRaw,
    this.city,
    this.country,
    this.isRemote = false,
    this.isHybrid = false,
    this.contractType,
    this.experienceLevel,
    this.salaryMin,
    this.salaryMax,
    this.salaryCurrency,
    this.salaryPeriod,
    this.salaryRaw,
    this.description,
    this.sourceUrl,
    this.applicationUrl,
    this.applicationEmail,
    this.publishedAt,
    this.skills = const [],
    this.qualityIssues = const [],
  });

  final String title;
  final String? companyName;
  final String? locationRaw;
  final String? city;
  final String? country;
  final bool isRemote;
  final bool isHybrid;
  final String? contractType;
  final String? experienceLevel;
  final int? salaryMin;
  final int? salaryMax;
  final String? salaryCurrency;
  final String? salaryPeriod;
  final String? salaryRaw;
  final String? description;
  final String? sourceUrl;
  final String? applicationUrl;
  final String? applicationEmail;
  final DateTime? publishedAt;
  final List<String> skills;
  final List<String> qualityIssues;

  /// Lieu lisible : ville, pays (ou texte brut).
  String? get location {
    final parts = [city, country].whereType<String>().where((e) => e.trim().isNotEmpty).toList();
    if (parts.isNotEmpty) return parts.join(', ');
    return (locationRaw?.trim().isNotEmpty ?? false) ? locationRaw : null;
  }

  bool get hasSalary => salaryMin != null || salaryMax != null || (salaryRaw?.isNotEmpty ?? false);

  factory TestedJob.fromJson(Map<String, dynamic> json) => TestedJob(
    title: json['title']?.toString() ?? '',
    companyName: json['company_name'] as String?,
    locationRaw: json['location_raw'] as String?,
    city: json['city'] as String?,
    country: json['country'] as String?,
    isRemote: json['is_remote'] as bool? ?? false,
    isHybrid: json['is_hybrid'] as bool? ?? false,
    contractType: json['contract_type'] as String?,
    experienceLevel: json['experience_level'] as String?,
    salaryMin: parseInt(json['salary_min']),
    salaryMax: parseInt(json['salary_max']),
    salaryCurrency: json['salary_currency'] as String?,
    salaryPeriod: json['salary_period'] as String?,
    salaryRaw: json['salary_raw'] as String?,
    description: json['description'] as String?,
    sourceUrl: json['source_url'] as String?,
    applicationUrl: json['application_url'] as String?,
    applicationEmail: json['application_email'] as String?,
    publishedAt: parseDate(json['published_at']),
    skills: [
      for (final skill in parseMapList(json['skills']))
        if (skill['name'] != null) skill['name'].toString(),
    ],
    qualityIssues: parseStringList(json['quality_issues']),
  );
}

/// Résultat de `POST /sources/{id}/test` (rien n'est enregistré).
class SourceTestResult {
  const SourceTestResult({
    this.pagesFetched = 0,
    this.jobsParsed = 0,
    this.preview = const [],
    this.errors = const [],
  });

  final int pagesFetched;
  final int jobsParsed;
  final List<TestedJob> preview;
  final List<String> errors;

  factory SourceTestResult.fromJson(Map<String, dynamic> json) => SourceTestResult(
    pagesFetched: parseInt(json['pages_fetched']) ?? 0,
    jobsParsed: parseInt(json['jobs_parsed']) ?? 0,
    preview: parseMapList(json['preview']).map(TestedJob.fromJson).toList(),
    errors: parseStringList(json['errors']),
  );
}
