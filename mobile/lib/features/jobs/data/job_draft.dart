import '../../../core/models/enums.dart';

/// Compétence saisie dans le formulaire (`SkillPayload`).
class SkillDraft {
  const SkillDraft(this.name, {this.requirement = SkillRequirement.required});

  final String name;
  final SkillRequirement requirement;

  SkillDraft toggled() => SkillDraft(
    name,
    requirement: requirement == SkillRequirement.required
        ? SkillRequirement.preferred
        : SkillRequirement.required,
  );

  Map<String, dynamic> toJson() => {'name': name, 'requirement': requirement.apiValue};
}

/// Offre saisie manuellement : corps de `POST /jobs` (`JobCreate`).
///
/// Seul le titre est obligatoire. Le serveur exige aussi un identifiant (URL de l'annonce,
/// URL de candidature ou identifiant externe) : [toJson] en génère un si besoin.
class JobDraft {
  const JobDraft({
    required this.title,
    this.description,
    this.url,
    this.externalId,
    this.companyName,
    this.companyWebsite,
    this.city,
    this.country,
    this.remote = false,
    this.hybrid = false,
    this.contractType,
    this.workTime,
    this.salaryMin,
    this.salaryMax,
    this.salaryCurrency,
    this.salaryPeriod,
    this.experienceLevel,
    this.minYearsExperience,
    this.skills = const [],
    this.languages = const [],
    this.applicationUrl,
    this.applicationEmail,
    this.recruiterName,
    this.recruiterEmail,
    this.recruiterPhone,
    this.recruiterLinkedin,
    this.publishedAt,
    this.expiresAt,
  });

  final String title;
  final String? description;
  final String? url;
  final String? externalId;
  final String? companyName;
  final String? companyWebsite;
  final String? city;
  final String? country;
  final bool remote;
  final bool hybrid;
  final String? contractType;
  final String? workTime;
  final num? salaryMin;
  final num? salaryMax;
  final String? salaryCurrency;
  final SalaryPeriod? salaryPeriod;
  final String? experienceLevel;
  final int? minYearsExperience;
  final List<SkillDraft> skills;
  final List<String> languages;
  final String? applicationUrl;
  final String? applicationEmail;
  final String? recruiterName;
  final String? recruiterEmail;
  final String? recruiterPhone;
  final String? recruiterLinkedin;
  final DateTime? publishedAt;
  final DateTime? expiresAt;

  static String? _t(String? value) {
    final text = value?.trim();
    return (text == null || text.isEmpty) ? null : text;
  }

  /// Retire les entrées nulles d'un bloc ; renvoie null si le bloc est vide.
  static Map<String, dynamic>? _block(Map<String, dynamic> values) {
    final result = Map<String, dynamic>.of(values)..removeWhere((_, v) => v == null);
    return result.isEmpty ? null : result;
  }

  Map<String, dynamic> toJson({DateTime? now}) {
    final hasIdentifier = _t(url) != null || _t(applicationUrl) != null || _t(externalId) != null;
    final city = _t(this.city);
    final country = _t(this.country);
    final place = [city, country].whereType<String>().join(', ');
    final hasSalary = salaryMin != null || salaryMax != null;
    return {
      'title': title.trim(),
      'description': _t(description),
      'url': _t(url),
      'external_id':
          _t(externalId) ??
          (hasIdentifier ? null : 'manual-${(now ?? DateTime.now()).microsecondsSinceEpoch}'),
      'company': _block({'name': _t(companyName), 'website': _t(companyWebsite)}),
      'location': _block({
        'raw': place.isEmpty ? null : place,
        'city': city,
        'country': country,
        'remote': remote ? true : null,
        'hybrid': hybrid ? true : null,
      }),
      'contract': _block({'type': _t(contractType), 'work_time': _t(workTime)}),
      'salary': hasSalary
          ? _block({
              'min': salaryMin,
              'max': salaryMax,
              'currency': _t(salaryCurrency)?.toUpperCase(),
              'period': salaryPeriod?.apiValue,
            })
          : null,
      'experience_level': _t(experienceLevel),
      'min_years_experience': minYearsExperience,
      'skills': [for (final skill in skills) skill.toJson()],
      'languages': languages,
      'application': _block({'url': _t(applicationUrl), 'email': _t(applicationEmail)}),
      'recruiter': _block({
        'name': _t(recruiterName),
        'email': _t(recruiterEmail),
        'phone': _t(recruiterPhone),
        'linkedin_url': _t(recruiterLinkedin),
      })?..['contact_source'] = ContactSource.manual.apiValue,
      'published_at': publishedAt?.toUtc().toIso8601String(),
      'expires_at': expiresAt?.toUtc().toIso8601String(),
    }..removeWhere((_, value) => value == null);
  }
}
