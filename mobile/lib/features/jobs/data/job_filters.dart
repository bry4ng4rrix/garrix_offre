import '../../../core/models/enums.dart';

/// Critères de recherche de `GET /jobs` (immuable, comparable : sert de clé à la liste).
class JobFilters {
  const JobFilters({
    this.search,
    this.minScore,
    this.contractType,
    this.remote,
    this.location,
    this.skill,
    this.company,
    this.source,
    this.experienceLevel,
    this.sourceCategory,
    this.status,
    this.publishedAfter,
    this.publishedBefore,
    this.sortBy = JobSortField.publishedAt,
    this.sortDesc = true,
  });

  final String? search;
  final int? minScore;

  /// Code du type de contrat (`cdi`, `freelance`...).
  final String? contractType;

  /// true : télétravail complet uniquement ; false : hors télétravail complet.
  final bool? remote;
  final String? location;
  final String? skill;
  final String? company;

  /// Nom ou identifiant de la source.
  final String? source;

  /// Code du niveau (`junior`, `mid`...).
  final String? experienceLevel;
  final SourceCategory? sourceCategory;

  /// null : comportement par défaut du serveur (offres nouvelles/actives non ignorées).
  final JobStatusFilter? status;
  final DateTime? publishedAfter;
  final DateTime? publishedBefore;
  final JobSortField sortBy;
  final bool sortDesc;

  static const _unset = Object();

  /// Copie ; passez explicitement `null` pour effacer un critère.
  JobFilters copyWith({
    Object? search = _unset,
    Object? minScore = _unset,
    Object? contractType = _unset,
    Object? remote = _unset,
    Object? location = _unset,
    Object? skill = _unset,
    Object? company = _unset,
    Object? source = _unset,
    Object? experienceLevel = _unset,
    Object? sourceCategory = _unset,
    Object? status = _unset,
    Object? publishedAfter = _unset,
    Object? publishedBefore = _unset,
    JobSortField? sortBy,
    bool? sortDesc,
  }) {
    T? pick<T>(Object? value, T? current) => identical(value, _unset) ? current : value as T?;
    return JobFilters(
      search: _clean(pick<String>(search, this.search)),
      minScore: pick<int>(minScore, this.minScore),
      contractType: _clean(pick<String>(contractType, this.contractType)),
      remote: pick<bool>(remote, this.remote),
      location: _clean(pick<String>(location, this.location)),
      skill: _clean(pick<String>(skill, this.skill)),
      company: _clean(pick<String>(company, this.company)),
      source: _clean(pick<String>(source, this.source)),
      experienceLevel: _clean(pick<String>(experienceLevel, this.experienceLevel)),
      sourceCategory: pick<SourceCategory>(sourceCategory, this.sourceCategory),
      status: pick<JobStatusFilter>(status, this.status),
      publishedAfter: pick<DateTime>(publishedAfter, this.publishedAfter),
      publishedBefore: pick<DateTime>(publishedBefore, this.publishedBefore),
      sortBy: sortBy ?? this.sortBy,
      sortDesc: sortDesc ?? this.sortDesc,
    );
  }

  static String? _clean(String? value) {
    final text = value?.trim();
    return (text == null || text.isEmpty) ? null : text;
  }

  /// Nombre de filtres actifs (hors recherche texte et tri).
  int get activeCount => [
    minScore != null && minScore! > 0,
    contractType != null,
    remote != null,
    location != null,
    skill != null,
    company != null,
    source != null,
    experienceLevel != null,
    sourceCategory != null,
    status != null,
    publishedAfter != null,
    publishedBefore != null,
  ].where((active) => active).length;

  bool get hasSearch => search != null;

  bool get isSortDefault => sortBy == JobSortField.publishedAt && sortDesc;

  /// Paramètres de requête (valeurs API ; les valeurs nulles sont retirées par l'ApiClient).
  Map<String, dynamic> toQuery() => {
    'search': search,
    'min_score': (minScore ?? 0) > 0 ? minScore : null,
    'contract_type': contractType,
    'remote': remote,
    'location': location,
    'skill': skill,
    'company': company,
    'source': source,
    'experience_level': experienceLevel,
    'source_category': sourceCategory?.apiValue,
    'status': status?.apiValue,
    'published_after': publishedAfter,
    'published_before': publishedBefore,
    'sort_by': sortBy.apiValue,
    'sort_order': sortDesc ? 'desc' : 'asc',
  };

  @override
  bool operator ==(Object other) =>
      other is JobFilters &&
      other.search == search &&
      other.minScore == minScore &&
      other.contractType == contractType &&
      other.remote == remote &&
      other.location == location &&
      other.skill == skill &&
      other.company == company &&
      other.source == source &&
      other.experienceLevel == experienceLevel &&
      other.sourceCategory == sourceCategory &&
      other.status == status &&
      other.publishedAfter == publishedAfter &&
      other.publishedBefore == publishedBefore &&
      other.sortBy == sortBy &&
      other.sortDesc == sortDesc;

  @override
  int get hashCode => Object.hash(
    search,
    minScore,
    contractType,
    remote,
    location,
    skill,
    company,
    source,
    experienceLevel,
    sourceCategory,
    status,
    publishedAfter,
    publishedBefore,
    sortBy,
    sortDesc,
  );
}
