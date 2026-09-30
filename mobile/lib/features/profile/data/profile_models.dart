import 'package:flutter/material.dart';

import '../../../core/models/enums.dart';
import '../../../core/utils/json.dart';

/// Modèles du profil professionnel et des réglages qui alimentent le matching.
/// Lecture tolérante (`fromJson`) et corps de requête prêts à envoyer (`toJson`).

// ---------------------------------------------------------------------------
// Profil
// ---------------------------------------------------------------------------

/// Langue parlée (`LanguageSkill`) : code ISO 639-1 + niveau.
class LanguageSkill {
  const LanguageSkill({required this.code, required this.level});

  final String code;
  final LanguageLevel level;

  factory LanguageSkill.fromJson(Map<String, dynamic> json) => LanguageSkill(
    code: (json['code']?.toString() ?? '').toLowerCase(),
    level: LanguageLevel.fromApi(json['level']) ?? LanguageLevel.intermediate,
  );

  Map<String, dynamic> toJson() => {'code': code, 'level': level.apiValue};
}

/// Profil professionnel (`ProfileRead`).
class Profile {
  const Profile({
    required this.id,
    this.firstName,
    this.lastName,
    this.fullName,
    this.professionalTitle,
    this.email,
    this.phone,
    this.country,
    this.city,
    this.professionalAddress,
    this.bio,
    this.availability,
    this.availableFrom,
    this.yearsOfExperience,
    this.experienceLevel,
    this.mobility,
    this.languages = const [],
    this.linkedinUrl,
    this.githubUrl,
    this.portfolioUrl,
    this.minimumSalary,
    this.currency = 'EUR',
    this.salaryPeriod = SalaryPeriod.month,
    this.remote = true,
    this.photoUrl,
    this.completionPercent = 0,
    this.updatedAt,
  });

  final String id;
  final String? firstName;
  final String? lastName;
  final String? fullName;
  final String? professionalTitle;
  final String? email;
  final String? phone;
  final String? country;
  final String? city;
  final String? professionalAddress;
  final String? bio;
  final Availability? availability;
  final DateTime? availableFrom;
  final int? yearsOfExperience;
  final String? experienceLevel;
  final Mobility? mobility;
  final List<LanguageSkill> languages;
  final String? linkedinUrl;
  final String? githubUrl;
  final String? portfolioUrl;

  // Champs partagés avec les préférences de recherche.
  final int? minimumSalary;
  final String currency;
  final SalaryPeriod salaryPeriod;
  final bool remote;

  final String? photoUrl;
  final int completionPercent;
  final DateTime? updatedAt;

  bool get hasPhoto => photoUrl != null && photoUrl!.isNotEmpty;

  /// Nom affiché : nom complet, sinon prénom/nom, sinon null.
  String? get displayName {
    final full = fullName?.trim();
    if (full != null && full.isNotEmpty) return full;
    final parts = [firstName, lastName].whereType<String>().where((p) => p.trim().isNotEmpty);
    return parts.isEmpty ? null : parts.join(' ');
  }

  /// « Paris, France ».
  String? get location {
    final parts = [city, country].whereType<String>().where((p) => p.trim().isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join(', ');
  }

  /// Champs pris en compte par le serveur pour `completion_percent`, encore vides.
  List<String> get missingFields {
    bool empty(String? v) => v == null || v.trim().isEmpty;
    return [
      if (empty(firstName)) 'prénom',
      if (empty(lastName)) 'nom',
      if (empty(professionalTitle)) 'titre',
      if (empty(email)) 'email',
      if (empty(phone)) 'téléphone',
      if (empty(city)) 'ville',
      if (empty(country)) 'pays',
      if (empty(bio)) 'présentation',
      if (availability == null) 'disponibilité',
      if (yearsOfExperience == null || yearsOfExperience == 0) 'années d\'expérience',
      if (empty(experienceLevel)) 'niveau',
      if (languages.isEmpty) 'langues',
      if (!hasPhoto) 'photo',
    ];
  }

  /// Clé de cache de la photo : change quand le profil (et donc la photo) change.
  String get photoCacheKey {
    final shortId = id.length > 8 ? id.substring(0, 8) : id;
    return '$shortId-${updatedAt?.millisecondsSinceEpoch ?? 0}';
  }

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    id: json['id']?.toString() ?? '',
    firstName: json['first_name'] as String?,
    lastName: json['last_name'] as String?,
    fullName: json['full_name'] as String?,
    professionalTitle: json['professional_title'] as String?,
    email: json['email'] as String?,
    phone: json['phone'] as String?,
    country: json['country'] as String?,
    city: json['city'] as String?,
    professionalAddress: json['professional_address'] as String?,
    bio: json['bio'] as String?,
    availability: Availability.fromApi(json['availability']),
    availableFrom: parseDate(json['available_from']),
    yearsOfExperience: parseInt(json['years_of_experience']),
    experienceLevel: json['experience_level'] as String?,
    mobility: Mobility.fromApi(json['mobility']),
    languages: parseMapList(json['languages']).map(LanguageSkill.fromJson).toList(),
    linkedinUrl: json['linkedin_url'] as String?,
    githubUrl: json['github_url'] as String?,
    portfolioUrl: json['portfolio_url'] as String?,
    minimumSalary: parseInt(json['minimum_salary']),
    currency: json['currency']?.toString() ?? 'EUR',
    salaryPeriod: SalaryPeriod.fromApi(json['salary_period']) ?? SalaryPeriod.month,
    remote: json['remote'] as bool? ?? true,
    photoUrl: json['photo_url'] as String?,
    completionPercent: parseInt(json['completion_percent']) ?? 0,
    updatedAt: parseDate(json['updated_at']),
  );
}

// ---------------------------------------------------------------------------
// Compétences
// ---------------------------------------------------------------------------

/// Compétence du profil (`ProfileSkillRead`).
class ProfileSkill {
  const ProfileSkill({
    required this.id,
    required this.skillId,
    required this.name,
    this.category,
    this.level = SkillLevel.intermediate,
    this.yearsExperience,
    this.priority = Priority.medium,
    this.enabled = true,
  });

  final String id;
  final String skillId;
  final String name;
  final String? category;
  final SkillLevel level;
  final double? yearsExperience;
  final Priority priority;
  final bool enabled;

  factory ProfileSkill.fromJson(Map<String, dynamic> json) => ProfileSkill(
    id: json['id']?.toString() ?? '',
    skillId: json['skill_id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    category: json['category'] as String?,
    level: SkillLevel.fromApi(json['level']) ?? SkillLevel.intermediate,
    yearsExperience: parseDouble(json['years_experience']),
    priority: Priority.fromApi(json['priority']) ?? Priority.medium,
    enabled: json['enabled'] as bool? ?? true,
  );
}

// ---------------------------------------------------------------------------
// Expériences
// ---------------------------------------------------------------------------

/// Expérience professionnelle (`ExperienceRead`).
class Experience {
  const Experience({
    required this.id,
    required this.companyName,
    required this.jobTitle,
    required this.startDate,
    this.location,
    this.endDate,
    this.isCurrent = false,
    this.description,
    this.technologies = const [],
    this.durationYears,
  });

  final String id;
  final String companyName;
  final String jobTitle;
  final String? location;
  final DateTime startDate;
  final DateTime? endDate;
  final bool isCurrent;
  final String? description;
  final List<String> technologies;
  final double? durationYears;

  factory Experience.fromJson(Map<String, dynamic> json) => Experience(
    id: json['id']?.toString() ?? '',
    companyName: json['company_name']?.toString() ?? '',
    jobTitle: json['job_title']?.toString() ?? '',
    location: json['location'] as String?,
    startDate: parseDate(json['start_date']) ?? DateTime(1970),
    endDate: parseDate(json['end_date']),
    isCurrent: json['is_current'] as bool? ?? false,
    description: json['description'] as String?,
    technologies: parseStringList(json['technologies']),
    durationYears: parseDouble(json['duration_years']),
  );
}

/// Corps de `POST /experiences` et `PUT /experiences/{id}` (remplacement complet).
class ExperienceInput {
  const ExperienceInput({
    required this.companyName,
    required this.jobTitle,
    required this.startDate,
    this.location,
    this.endDate,
    this.isCurrent = false,
    this.description,
    this.technologies = const [],
  });

  final String companyName;
  final String jobTitle;
  final String? location;
  final DateTime startDate;
  final DateTime? endDate;
  final bool isCurrent;
  final String? description;
  final List<String> technologies;

  Map<String, dynamic> toJson() => {
    'company_name': companyName.trim(),
    'job_title': jobTitle.trim(),
    'location': _blankToNull(location),
    'start_date': formatApiDate(startDate),
    'end_date': isCurrent || endDate == null ? null : formatApiDate(endDate!),
    'is_current': isCurrent,
    'description': _blankToNull(description),
    'technologies': technologies,
  };
}

// ---------------------------------------------------------------------------
// Technologies recherchées
// ---------------------------------------------------------------------------

/// Technologie recherchée (`ExperiencePreferenceRead`).
class TechnologyPreference {
  const TechnologyPreference({
    required this.id,
    required this.skillId,
    required this.technology,
    this.category,
    this.level = SkillLevel.intermediate,
    this.priority = Priority.medium,
    this.minYears = 0,
    this.isRequired = false,
    this.enabled = true,
  });

  final String id;
  final String skillId;
  final String technology;
  final String? category;
  final SkillLevel level;
  final Priority priority;
  final int minYears;
  final bool isRequired;
  final bool enabled;

  factory TechnologyPreference.fromJson(Map<String, dynamic> json) => TechnologyPreference(
    id: json['id']?.toString() ?? '',
    skillId: json['skill_id']?.toString() ?? '',
    technology: json['technology']?.toString() ?? '',
    category: json['category'] as String?,
    level: SkillLevel.fromApi(json['level']) ?? SkillLevel.intermediate,
    priority: Priority.fromApi(json['priority']) ?? Priority.medium,
    minYears: parseInt(json['min_years']) ?? 0,
    isRequired: json['is_required'] as bool? ?? false,
    enabled: json['enabled'] as bool? ?? true,
  );

  /// Lit la réponse de `GET /experience-preferences/grouped` (`{catégorie: [...]}`).
  static Map<String, List<TechnologyPreference>> groupedFromJson(Object? json) {
    final result = <String, List<TechnologyPreference>>{};
    parseMap(json).forEach((key, value) {
      result[key] = parseMapList(value).map(TechnologyPreference.fromJson).toList();
    });
    return result;
  }
}

// ---------------------------------------------------------------------------
// Postes recherchés
// ---------------------------------------------------------------------------

/// Poste recherché (`JobTitleRead`).
class JobTitle {
  const JobTitle({
    required this.id,
    required this.title,
    this.priority = Priority.medium,
    this.enabled = true,
  });

  final String id;
  final String title;
  final Priority priority;
  final bool enabled;

  factory JobTitle.fromJson(Map<String, dynamic> json) => JobTitle(
    id: json['id']?.toString() ?? '',
    title: json['title']?.toString() ?? '',
    priority: Priority.fromApi(json['priority']) ?? Priority.medium,
    enabled: json['enabled'] as bool? ?? true,
  );
}

// ---------------------------------------------------------------------------
// Préférences de recherche
// ---------------------------------------------------------------------------

/// Lieu souhaité (ville et/ou pays).
class LocationPreference {
  const LocationPreference({this.city, this.country});

  final String? city;
  final String? country;

  String get label =>
      [city, country].whereType<String>().where((p) => p.trim().isNotEmpty).join(', ');

  factory LocationPreference.fromJson(Map<String, dynamic> json) =>
      LocationPreference(city: json['city'] as String?, country: json['country'] as String?);

  Map<String, dynamic> toJson() => {'city': _blankToNull(city), 'country': _blankToNull(country)};

  @override
  bool operator ==(Object other) =>
      other is LocationPreference &&
      (other.city ?? '').toLowerCase() == (city ?? '').toLowerCase() &&
      (other.country ?? '').toLowerCase() == (country ?? '').toLowerCase();

  @override
  int get hashCode => Object.hash((city ?? '').toLowerCase(), (country ?? '').toLowerCase());
}

/// Préférences de recherche (`PreferencesRead`).
class SearchPreferences {
  const SearchPreferences({
    this.jobTitles = const [],
    this.contractTypes = const [],
    this.skills = const [],
    this.experienceLevels = const [],
    this.locations = const [],
    this.remote = true,
    this.hybrid = true,
    this.onsite = true,
    this.minimumSalary,
    this.currency = 'EUR',
    this.salaryPeriod = SalaryPeriod.month,
    this.languages = const [],
    this.matchingThreshold = 70,
  });

  final List<String> jobTitles;
  final List<String> contractTypes;
  final List<String> skills;
  final List<String> experienceLevels;
  final List<LocationPreference> locations;
  final bool remote;
  final bool hybrid;
  final bool onsite;
  final int? minimumSalary;
  final String currency;
  final SalaryPeriod salaryPeriod;
  final List<String> languages;
  final int matchingThreshold;

  factory SearchPreferences.fromJson(Map<String, dynamic> json) => SearchPreferences(
    jobTitles: parseStringList(json['job_titles']),
    contractTypes: parseStringList(json['contract_types']),
    skills: parseStringList(json['skills']),
    experienceLevels: parseStringList(json['experience_levels']),
    locations: parseMapList(json['locations']).map(LocationPreference.fromJson).toList(),
    remote: json['remote'] as bool? ?? true,
    hybrid: json['hybrid'] as bool? ?? true,
    onsite: json['onsite'] as bool? ?? true,
    minimumSalary: parseInt(json['minimum_salary']),
    currency: json['currency']?.toString() ?? 'EUR',
    salaryPeriod: SalaryPeriod.fromApi(json['salary_period']) ?? SalaryPeriod.month,
    languages: parseStringList(json['languages']),
    matchingThreshold: parseInt(json['matching_threshold']) ?? 70,
  );

  /// Corps de `PUT /preferences`.
  ///
  /// `job_titles` et `skills` ne sont volontairement pas envoyés : le serveur désactiverait
  /// les postes / technologies absents de la liste. Ils se gèrent sur leurs propres écrans.
  Map<String, dynamic> toUpdateJson() => {
    'contract_types': contractTypes,
    'experience_levels': experienceLevels,
    'locations': locations.map((l) => l.toJson()).toList(),
    'remote': remote,
    'hybrid': hybrid,
    'onsite': onsite,
    'minimum_salary': minimumSalary,
    'currency': currency.toUpperCase(),
    'salary_period': salaryPeriod.apiValue,
    'languages': languages,
    'matching_threshold': matchingThreshold,
  };
}

// ---------------------------------------------------------------------------
// Matching
// ---------------------------------------------------------------------------

/// Critères du score de matching, avec leur explication.
enum MatchingCriterion {
  skills(
    'skills_weight',
    'Compétences',
    'Compétences demandées par l\'offre que vous possédez. Les obligatoires comptent double, '
        'votre niveau module la part reconnue.',
    Icons.psychology_outlined,
  ),
  experience(
    'experience_weight',
    'Technologies recherchées',
    'Présence dans l\'offre des technologies que vous recherchez, selon leur priorité.',
    Icons.memory_outlined,
  ),
  title(
    'title_weight',
    'Intitulé du poste',
    'Proximité entre le titre de l\'offre et vos postes recherchés.',
    Icons.badge_outlined,
  ),
  contract(
    'contract_weight',
    'Type de contrat',
    'L\'offre propose-t-elle un des contrats que vous recherchez ?',
    Icons.description_outlined,
  ),
  location(
    'location_weight',
    'Lieu et télétravail',
    'Ville ou pays souhaités et mode de travail (sur site, hybride, télétravail).',
    Icons.place_outlined,
  ),
  salary(
    'salary_weight',
    'Salaire',
    'Salaire proposé comparé à votre minimum (converti sur l\'année).',
    Icons.payments_outlined,
  ),
  language(
    'language_weight',
    'Langues',
    'Langues demandées par l\'offre que vous parlez.',
    Icons.translate_rounded,
  ),
  experienceLevel(
    'experience_level_weight',
    'Niveau d\'expérience',
    'Séniorité demandée (junior, senior…) et années d\'expérience exigées.',
    Icons.trending_up_rounded,
  );

  const MatchingCriterion(this.apiKey, this.label, this.description, this.icon);
  final String apiKey;
  final String label;
  final String description;
  final IconData icon;
}

/// Poids relatifs des critères (`MatchingSettingsRead`), de 0 à 100.
class MatchingSettings {
  const MatchingSettings(this.weights);

  final Map<MatchingCriterion, int> weights;

  int weightOf(MatchingCriterion criterion) => weights[criterion] ?? 0;

  int get total => weights.values.fold(0, (sum, w) => sum + w);

  /// Part réelle du critère dans le score final (0-100), les poids étant ramenés sur 100.
  double shareOf(MatchingCriterion criterion) {
    final sum = total;
    return sum == 0 ? 0 : weightOf(criterion) * 100 / sum;
  }

  MatchingSettings copyWith(MatchingCriterion criterion, int weight) =>
      MatchingSettings({...weights, criterion: weight});

  factory MatchingSettings.fromJson(Map<String, dynamic> json) => MatchingSettings({
    for (final criterion in MatchingCriterion.values)
      criterion: (parseInt(json[criterion.apiKey]) ?? 0).clamp(0, 100),
  });

  Map<String, dynamic> toJson() => {
    for (final criterion in MatchingCriterion.values) criterion.apiKey: weightOf(criterion),
  };

  @override
  bool operator ==(Object other) =>
      other is MatchingSettings &&
      MatchingCriterion.values.every((c) => other.weightOf(c) == weightOf(c));

  @override
  int get hashCode => Object.hashAll(MatchingCriterion.values.map(weightOf));
}

/// Réponse de `POST /matching/recalculate`.
class RecalculateResult {
  const RecalculateResult({required this.status, this.jobsMatched});

  /// `queued` (tâche de fond) ou `done`.
  final String status;
  final int? jobsMatched;

  bool get queued => status == 'queued';

  factory RecalculateResult.fromJson(Map<String, dynamic> json) => RecalculateResult(
    status: json['status']?.toString() ?? 'queued',
    jobsMatched: parseInt(json['jobs_matched']),
  );
}

String? _blankToNull(String? value) {
  final text = value?.trim();
  return (text == null || text.isEmpty) ? null : text;
}
