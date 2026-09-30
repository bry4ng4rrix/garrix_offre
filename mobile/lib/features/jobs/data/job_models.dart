import '../../../core/models/enums.dart';
import '../../../core/utils/json.dart';

/// Modèles de l'API des offres (`JobRead` et ses blocs, résultats de matching, analyse IA).

String? _text(Object? value) {
  final text = value?.toString().trim();
  return (text == null || text.isEmpty) ? null : text;
}

/// Source d'une offre (`JobSourceInfo`).
class JobSource {
  const JobSource({this.id, this.name, this.category, this.url, this.externalId});

  final String? id;
  final String? name;
  final SourceCategory? category;
  final String? url;
  final String? externalId;

  factory JobSource.fromJson(Map<String, dynamic> json) => JobSource(
    id: _text(json['id']),
    name: _text(json['name']),
    category: SourceCategory.fromApi(json['category']),
    url: _text(json['url']),
    externalId: _text(json['external_id']),
  );
}

/// Entreprise (`JobCompanyInfo` avec adresse et contact).
class JobCompany {
  const JobCompany({
    this.id,
    this.name,
    this.website,
    this.logoUrl,
    this.street,
    this.postalCode,
    this.city,
    this.country,
    this.email,
    this.phone,
  });

  final String? id;
  final String? name;
  final String? website;
  final String? logoUrl;
  final String? street;
  final String? postalCode;
  final String? city;
  final String? country;
  final String? email;
  final String? phone;

  factory JobCompany.fromJson(Map<String, dynamic> json) {
    final address = parseMap(json['address']);
    final contact = parseMap(json['contact']);
    return JobCompany(
      id: _text(json['id']),
      name: _text(json['name']),
      website: _text(json['website']),
      logoUrl: _text(json['logo_url']),
      street: _text(address['street']),
      postalCode: _text(address['postal_code']),
      city: _text(address['city']),
      country: _text(address['country']),
      email: _text(contact['email']),
      phone: _text(contact['phone']),
    );
  }

  /// Adresse sur une ligne : `12 rue X, 75001 Paris, France`.
  String? get address {
    final town = [postalCode, city].whereType<String>().join(' ');
    final parts = [street, town.isEmpty ? null : town, country].whereType<String>().toList();
    return parts.isEmpty ? null : parts.join(', ');
  }
}

/// Recruteur / contact (`JobRecruiterInfo`).
class JobRecruiter {
  const JobRecruiter({
    this.id,
    this.name,
    this.jobTitle,
    this.email,
    this.phone,
    this.linkedin,
    this.website,
    this.contactSource,
  });

  final String? id;
  final String? name;
  final String? jobTitle;
  final String? email;
  final String? phone;
  final String? linkedin;
  final String? website;
  final ContactSource? contactSource;

  factory JobRecruiter.fromJson(Map<String, dynamic> json) => JobRecruiter(
    id: _text(json['id']),
    name: _text(json['name']),
    jobTitle: _text(json['job_title']),
    email: _text(json['email']),
    phone: _text(json['phone']),
    linkedin: _text(json['linkedin']),
    website: _text(json['website']),
    contactSource: ContactSource.fromApi(json['contact_source']),
  );

  bool get isEmpty =>
      name == null &&
      email == null &&
      phone == null &&
      linkedin == null &&
      website == null &&
      jobTitle == null;
}

/// Lieu de travail (`JobLocationInfo`).
class JobLocation {
  const JobLocation({this.raw, this.city, this.country, this.remote = false, this.hybrid = false});

  final String? raw;
  final String? city;
  final String? country;
  final bool remote;
  final bool hybrid;

  factory JobLocation.fromJson(Map<String, dynamic> json) => JobLocation(
    raw: _text(json['raw']),
    city: _text(json['city']),
    country: _text(json['country']),
    remote: json['remote'] as bool? ?? false,
    hybrid: json['hybrid'] as bool? ?? false,
  );

  /// `Paris, France` (ou le texte brut de l'annonce).
  String? get label {
    final parts = <String>{?city, ?country};
    if (parts.isNotEmpty) return parts.join(', ');
    return raw;
  }

  /// `Télétravail`, `Hybride` ou null.
  String? get workModeLabel => remote ? 'Télétravail' : (hybrid ? 'Hybride' : null);
}

/// Contrat (`JobContractInfo`) : codes (`cdi`, `freelance`, `full_time`...).
class JobContract {
  const JobContract({this.type, this.workTime});

  final String? type;
  final String? workTime;

  factory JobContract.fromJson(Map<String, dynamic> json) =>
      JobContract(type: _text(json['type']), workTime: _text(json['work_time']));
}

/// Salaire (`JobSalaryInfo`).
class JobSalary {
  const JobSalary({this.min, this.max, this.currency, this.period, this.raw});

  final int? min;
  final int? max;
  final String? currency;
  final String? period;
  final String? raw;

  factory JobSalary.fromJson(Map<String, dynamic> json) => JobSalary(
    min: parseInt(json['min']),
    max: parseInt(json['max']),
    currency: _text(json['currency']),
    period: _text(json['period']),
    raw: _text(json['raw']),
  );

  bool get isKnown => min != null || max != null || raw != null;
}

/// Expérience demandée (`JobExperienceInfo`).
class JobExperience {
  const JobExperience({this.level, this.minYears});

  final String? level;
  final int? minYears;

  factory JobExperience.fromJson(Map<String, dynamic> json) =>
      JobExperience(level: _text(json['level']), minYears: parseInt(json['min_years']));
}

/// Compétence demandée (`JobSkillInfo`).
class JobSkill {
  const JobSkill({required this.name, this.category, this.requirement = SkillRequirement.required});

  final String name;
  final String? category;
  final SkillRequirement requirement;

  bool get isRequired => requirement == SkillRequirement.required;

  factory JobSkill.fromJson(Map<String, dynamic> json) => JobSkill(
    name: json['name']?.toString() ?? '',
    category: _text(json['category']),
    requirement: SkillRequirement.fromApi(json['requirement']) ?? SkillRequirement.required,
  );
}

/// Résumé du matching joint à l'offre (`JobMatchingInfo`).
class JobMatching {
  const JobMatching({
    required this.score,
    this.matchedSkills = const [],
    this.missingSkills = const [],
    this.reasons = const [],
    this.computedAt,
  });

  final int score;
  final List<String> matchedSkills;
  final List<String> missingSkills;
  final List<String> reasons;
  final DateTime? computedAt;

  factory JobMatching.fromJson(Map<String, dynamic> json) => JobMatching(
    score: parseInt(json['score']) ?? 0,
    matchedSkills: parseStringList(json['matched_skills']),
    missingSkills: parseStringList(json['missing_skills']),
    reasons: parseStringList(json['reasons']),
    computedAt: parseDate(json['computed_at']),
  );
}

/// Comment postuler (`JobApplicationInfo`).
class JobApplyInfo {
  const JobApplyInfo({this.url, this.email});

  final String? url;
  final String? email;

  factory JobApplyInfo.fromJson(Map<String, dynamic> json) =>
      JobApplyInfo(url: _text(json['url']), email: _text(json['email']));
}

/// État de l'offre pour l'utilisateur (`JobStatusInfo`).
class JobUserState {
  const JobUserState({
    this.state = 'active',
    this.isNew = false,
    this.isExpired = false,
    this.isSaved = false,
    this.isIgnored = false,
    this.applicationStatus = ApplicationStatus.notApplied,
    this.applicationId,
  });

  /// `new`, `active`, `expired`, `archived` ou `ignored`.
  final String state;

  /// Jamais ouverte par l'utilisateur (et non expirée).
  final bool isNew;
  final bool isExpired;
  final bool isSaved;
  final bool isIgnored;
  final ApplicationStatus applicationStatus;
  final String? applicationId;

  /// Statut de publication de l'offre (null si « ignorée » par l'utilisateur).
  JobStatus? get jobStatus => JobStatus.fromApi(state);

  bool get hasApplication => applicationId != null;

  factory JobUserState.fromJson(Map<String, dynamic> json) => JobUserState(
    state: json['state']?.toString() ?? 'active',
    isNew: json['is_new'] as bool? ?? false,
    isExpired: json['is_expired'] as bool? ?? false,
    isSaved: json['is_saved'] as bool? ?? false,
    isIgnored: json['is_ignored'] as bool? ?? false,
    applicationStatus:
        ApplicationStatus.fromApi(json['application_status']) ?? ApplicationStatus.notApplied,
    applicationId: _text(json['application_id']),
  );
}

/// Offre d'emploi normalisée (`JobRead`).
class Job {
  const Job({
    required this.id,
    required this.title,
    this.excerpt,
    this.description,
    this.source = const JobSource(),
    this.otherSources = const [],
    this.company = const JobCompany(),
    this.recruiter = const JobRecruiter(),
    this.location = const JobLocation(),
    this.contract = const JobContract(),
    this.salary = const JobSalary(),
    this.experience = const JobExperience(),
    this.skills = const [],
    this.languages = const [],
    this.matching,
    this.application = const JobApplyInfo(),
    this.status = const JobUserState(),
    this.qualityIssues = const [],
    this.publishedAt,
    this.expiresAt,
    this.scrapedAt,
    this.lastCheckedAt,
    this.createdAt,
  });

  final String id;
  final String title;
  final String? excerpt;
  final String? description;
  final JobSource source;
  final List<JobSource> otherSources;
  final JobCompany company;
  final JobRecruiter recruiter;
  final JobLocation location;
  final JobContract contract;
  final JobSalary salary;
  final JobExperience experience;
  final List<JobSkill> skills;
  final List<String> languages;
  final JobMatching? matching;
  final JobApplyInfo application;
  final JobUserState status;
  final List<String> qualityIssues;
  final DateTime? publishedAt;
  final DateTime? expiresAt;
  final DateTime? scrapedAt;
  final DateTime? lastCheckedAt;
  final DateTime? createdAt;

  factory Job.fromJson(Map<String, dynamic> json) => Job(
    id: json['id'].toString(),
    title: json['title']?.toString() ?? 'Sans titre',
    excerpt: _text(json['excerpt']),
    description: _text(json['description']),
    source: JobSource.fromJson(parseMap(json['source'])),
    otherSources: parseMapList(json['other_sources']).map(JobSource.fromJson).toList(),
    company: JobCompany.fromJson(parseMap(json['company'])),
    recruiter: JobRecruiter.fromJson(parseMap(json['recruiter'])),
    location: JobLocation.fromJson(parseMap(json['location'])),
    contract: JobContract.fromJson(parseMap(json['contract'])),
    salary: JobSalary.fromJson(parseMap(json['salary'])),
    experience: JobExperience.fromJson(parseMap(json['experience'])),
    skills: parseMapList(json['skills'])
        .map(JobSkill.fromJson)
        .where((skill) => skill.name.isNotEmpty)
        .toList(),
    languages: parseStringList(json['languages']),
    matching: json['matching'] is Map ? JobMatching.fromJson(parseMap(json['matching'])) : null,
    application: JobApplyInfo.fromJson(parseMap(json['application'])),
    status: JobUserState.fromJson(parseMap(json['status'])),
    qualityIssues: parseStringList(json['quality_issues']),
    publishedAt: parseDate(json['published_at']),
    expiresAt: parseDate(json['expires_at']),
    scrapedAt: parseDate(json['scraped_at']),
    lastCheckedAt: parseDate(json['last_checked_at']),
    createdAt: parseDate(json['created_at']),
  );

  int? get score => matching?.score;

  /// Date affichée dans les listes (publication, sinon ajout).
  DateTime? get displayDate => publishedAt ?? createdAt;

  /// Lien principal vers l'annonce (source, sinon lien de candidature).
  String? get listingUrl => source.url ?? application.url;

  List<JobSkill> get requiredSkills => skills.where((s) => s.isRequired).toList();
  List<JobSkill> get preferredSkills => skills.where((s) => !s.isRequired).toList();

  /// Texte de description le plus complet disponible.
  String? get bestDescription => description ?? excerpt;

  Job copyWith({JobUserState? status, JobMatching? matching}) => Job(
    id: id,
    title: title,
    excerpt: excerpt,
    description: description,
    source: source,
    otherSources: otherSources,
    company: company,
    recruiter: recruiter,
    location: location,
    contract: contract,
    salary: salary,
    experience: experience,
    skills: skills,
    languages: languages,
    matching: matching ?? this.matching,
    application: application,
    status: status ?? this.status,
    qualityIssues: qualityIssues,
    publishedAt: publishedAt,
    expiresAt: expiresAt,
    scrapedAt: scrapedAt,
    lastCheckedAt: lastCheckedAt,
    createdAt: createdAt,
  );

  /// Garde la description déjà chargée quand l'API renvoie une version « liste » de l'offre.
  Job mergeDetails(Job previous) => description != null || previous.description == null
      ? this
      : Job(
          id: id,
          title: title,
          excerpt: excerpt,
          description: previous.description,
          source: source,
          otherSources: otherSources,
          company: company,
          recruiter: recruiter,
          location: location,
          contract: contract,
          salary: salary,
          experience: experience,
          skills: skills,
          languages: languages,
          matching: matching,
          application: application,
          status: status,
          qualityIssues: qualityIssues,
          publishedAt: publishedAt,
          expiresAt: expiresAt,
          scrapedAt: scrapedAt,
          lastCheckedAt: lastCheckedAt,
          createdAt: createdAt,
        );
}

/// Corps de `PATCH /jobs/{id}/state` (`JobStateUpdate`) : seuls les champs fournis changent.
class JobStateUpdate {
  const JobStateUpdate({this.isSaved, this.isIgnored, this.seen});

  final bool? isSaved;
  final bool? isIgnored;
  final bool? seen;

  Map<String, dynamic> toJson() => {
    if (isSaved != null) 'is_saved': isSaved,
    if (isIgnored != null) 'is_ignored': isIgnored,
    if (seen != null) 'seen': seen,
  };
}

/// Sous-score d'un critère de matching (`breakdown`).
class MatchCriterion {
  const MatchCriterion({required this.key, required this.score, required this.weight, this.matched});

  /// `skills`, `experience`, `title`, `contract`, `location`, `salary`, `language`, `experience_level`.
  final String key;

  /// 0.0 à 1.0, null si le critère n'a pas pu être évalué.
  final double? score;
  final int weight;

  /// Critère satisfait (true), non satisfait (false) ou inconnu (null).
  final bool? matched;

  bool get isEvaluated => score != null && weight > 0;
}

/// Résultat détaillé de `POST /jobs/{id}/match` (`MatchResultRead`).
class MatchResult {
  const MatchResult({
    required this.jobId,
    required this.score,
    this.matchedSkills = const [],
    this.missingSkills = const [],
    this.reasons = const [],
    this.criteria = const [],
    this.computedAt,
  });

  final String jobId;
  final int score;
  final List<String> matchedSkills;
  final List<String> missingSkills;
  final List<String> reasons;

  /// Critères triés par poids décroissant.
  final List<MatchCriterion> criteria;
  final DateTime? computedAt;

  static const _flags = {
    'skills': null,
    'experience': 'experience_match',
    'title': 'title_match',
    'contract': 'contract_match',
    'location': 'location_match',
    'salary': 'salary_match',
    'language': 'language_match',
    'experience_level': 'experience_level_match',
  };

  factory MatchResult.fromJson(Map<String, dynamic> json) {
    final breakdown = parseMap(json['breakdown']);
    final criteria = <MatchCriterion>[
      for (final entry in breakdown.entries)
        if (entry.value is Map)
          MatchCriterion(
            key: entry.key,
            score: parseDouble((entry.value as Map)['score']),
            weight: parseInt((entry.value as Map)['weight']) ?? 0,
            matched: _flags[entry.key] == null ? null : json[_flags[entry.key]] as bool?,
          ),
    ]..sort((a, b) => b.weight.compareTo(a.weight));
    return MatchResult(
      jobId: json['job_id']?.toString() ?? '',
      score: parseInt(json['score']) ?? 0,
      matchedSkills: parseStringList(json['matched_skills']),
      missingSkills: parseStringList(json['missing_skills']),
      reasons: parseStringList(json['reasons']),
      criteria: criteria,
      computedAt: parseDate(json['computed_at']),
    );
  }

  /// Version « résumé » à reporter sur l'offre.
  JobMatching toMatching() => JobMatching(
    score: score,
    matchedSkills: matchedSkills,
    missingSkills: missingSkills,
    reasons: reasons,
    computedAt: computedAt,
  );
}

/// Résultat de `POST /matching/recalculate`.
class RecalculateResult {
  const RecalculateResult({required this.status, this.jobsMatched});

  /// `queued` (tâche de fond) ou `done`.
  final String status;
  final int? jobsMatched;

  bool get isQueued => status == 'queued';

  factory RecalculateResult.fromJson(Map<String, dynamic> json) => RecalculateResult(
    status: json['status']?.toString() ?? 'queued',
    jobsMatched: parseInt(json['jobs_matched']),
  );
}

/// Analyse d'une offre (`JobAnalysis`, IA ou règles).
class JobAnalysis {
  const JobAnalysis({
    required this.summary,
    this.responsibilities = const [],
    this.requiredSkills = const [],
    this.preferredSkills = const [],
    this.experienceLevel,
    this.minYearsExperience,
    this.languages = const [],
    this.remotePolicy,
    this.highlights = const [],
    this.redFlags = const [],
    this.education,
    this.generatedBy,
  });

  final String summary;
  final List<String> responsibilities;
  final List<String> requiredSkills;
  final List<String> preferredSkills;
  final String? experienceLevel;
  final int? minYearsExperience;
  final List<String> languages;

  /// `remote`, `hybrid`, `onsite` ou `unknown`.
  final String? remotePolicy;
  final List<String> highlights;
  final List<String> redFlags;
  final String? education;
  final GeneratedBy? generatedBy;

  factory JobAnalysis.fromJson(Map<String, dynamic> json) {
    final requirements = parseMap(json['requirements']);
    return JobAnalysis(
      summary: json['summary']?.toString() ?? '',
      responsibilities: parseStringList(json['responsibilities']),
      requiredSkills: parseStringList(json['required_skills']),
      preferredSkills: parseStringList(json['preferred_skills']),
      experienceLevel: _text(json['experience_level']),
      minYearsExperience: parseInt(json['min_years_experience']),
      languages: parseStringList(json['languages']),
      remotePolicy: _text(json['remote_policy']),
      highlights: parseStringList(json['highlights']),
      redFlags: parseStringList(json['red_flags']),
      education: _text(requirements['education']),
      generatedBy: GeneratedBy.fromApi(json['generated_by']),
    );
  }
}

/// Données brutes et normalisées d'une offre (`JobRawRead`, admin).
class JobRaw {
  const JobRaw({
    required this.id,
    this.rawData = const {},
    this.normalizedData = const {},
    this.qualityIssues = const [],
    this.sources = const [],
  });

  final String id;
  final Map<String, dynamic> rawData;
  final Map<String, dynamic> normalizedData;
  final List<String> qualityIssues;
  final List<JobSource> sources;

  factory JobRaw.fromJson(Map<String, dynamic> json) => JobRaw(
    id: json['id']?.toString() ?? '',
    rawData: parseMap(json['raw_data']),
    normalizedData: parseMap(json['normalized_data']),
    qualityIssues: parseStringList(json['quality_issues']),
    sources: parseMapList(json['sources']).map(JobSource.fromJson).toList(),
  );
}
