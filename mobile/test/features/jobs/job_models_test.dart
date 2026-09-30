import 'package:flutter_test/flutter_test.dart';
import 'package:garrix_offre/core/models/enums.dart';
import 'package:garrix_offre/features/jobs/data/job_draft.dart';
import 'package:garrix_offre/features/jobs/data/job_filters.dart';
import 'package:garrix_offre/features/jobs/data/job_models.dart';
import 'package:garrix_offre/features/jobs/job_labels.dart';

/// Offre réelle renvoyée par l'API locale (`GET /jobs`), légèrement raccourcie.
const _jobJson = <String, dynamic>{
  'id': '0707986c-5bf8-434c-a30f-ddf5e2de01a6',
  'title': 'Développeur Full Stack Python / React (H/F)',
  'excerpt': 'Exemple SAS recherche un développeur Full Stack.',
  'description': null,
  'source': {
    'id': '280579ed-106c-4f69-b9d1-c93db1b56655',
    'name': 'Saisie manuelle',
    'category': 'jobs',
    'url': 'https://example.com/jobs/demo-1',
    'external_id': 'demo-1',
  },
  'other_sources': [
    {'id': null, 'name': 'Jobgether', 'category': 'clients', 'url': null, 'external_id': 'x1'},
  ],
  'company': {
    'id': 'e893a97c-4545-4510-9ce9-c53a80a4330f',
    'name': 'Exemple SAS',
    'website': 'https://example.com/',
    'logo_url': null,
    'address': {'street': null, 'postal_code': '75001', 'city': 'Paris', 'country': 'France'},
    'contact': {'email': null, 'phone': null},
  },
  'recruiter': {
    'id': 'e263296d-731e-4edb-8add-761808289a1c',
    'name': 'Recrutement Exemple',
    'job_title': null,
    'email': 'jobs@example.com',
    'phone': null,
    'linkedin': null,
    'website': null,
    'contact_source': 'job_listing',
  },
  'location': {
    'raw': 'Paris, France',
    'city': 'Paris',
    'country': 'France',
    'remote': false,
    'hybrid': true,
  },
  'contract': {'type': 'cdi', 'work_time': null},
  'salary': {'min': 45000, 'max': 55000, 'currency': 'EUR', 'period': 'year', 'raw': null},
  'experience': {'level': 'mid', 'min_years': 3},
  'skills': [
    {'name': 'Python', 'category': 'backend', 'requirement': 'required'},
    {'name': 'Docker', 'category': 'devops', 'requirement': 'preferred'},
    {'name': 'full stack', 'category': null, 'requirement': 'required'},
  ],
  'languages': ['fr'],
  'matching': {
    'score': 90,
    'matched_skills': ['Python', 'Docker'],
    'missing_skills': ['full stack'],
    'reasons': ['Compétences correspondantes : 6/7'],
    'computed_at': '2026-09-30T08:40:09.191672Z',
  },
  'application': {'url': 'https://example.com/jobs/demo-1', 'email': null},
  'status': {
    'state': 'active',
    'is_new': true,
    'is_expired': false,
    'is_saved': false,
    'is_ignored': false,
    'application_status': 'not_applied',
    'application_id': null,
  },
  'quality_issues': ['missing_description'],
  'published_at': null,
  'expires_at': null,
  'scraped_at': '2026-09-30T08:40:05.870107Z',
  'last_checked_at': '2026-09-30T08:40:05.870112Z',
  'created_at': '2026-09-30T08:40:05.617739Z',
};

void main() {
  group('Job.fromJson', () {
    test('lit tous les blocs de JobRead', () {
      final job = Job.fromJson(_jobJson);
      expect(job.id, '0707986c-5bf8-434c-a30f-ddf5e2de01a6');
      expect(job.description, isNull);
      expect(job.bestDescription, startsWith('Exemple SAS'));
      expect(job.source.category, SourceCategory.jobs);
      expect(job.otherSources.single.category, SourceCategory.clients);
      expect(job.company.address, '75001 Paris, France');
      expect(job.recruiter.contactSource, ContactSource.jobListing);
      expect(job.recruiter.isEmpty, isFalse);
      expect(job.location.label, 'Paris, France');
      expect(job.location.workModeLabel, 'Hybride');
      expect(job.contract.type, 'cdi');
      expect(job.salary.isKnown, isTrue);
      expect(job.salary.min, 45000);
      expect(job.experience.minYears, 3);
      expect(job.requiredSkills.map((s) => s.name), ['Python', 'full stack']);
      expect(job.preferredSkills.single.name, 'Docker');
      expect(job.score, 90);
      expect(job.matching!.missingSkills, ['full stack']);
      expect(job.matching!.computedAt, isNotNull);
      expect(job.status.isNew, isTrue);
      expect(job.status.jobStatus, JobStatus.active);
      expect(job.status.applicationStatus, ApplicationStatus.notApplied);
      expect(job.status.hasApplication, isFalse);
      expect(job.listingUrl, 'https://example.com/jobs/demo-1');
      expect(job.qualityIssues, ['missing_description']);
      expect(job.displayDate, job.createdAt);
    });

    test('tolère les blocs absents et le matching nul', () {
      final job = Job.fromJson({'id': 'abc', 'title': 'Poste', 'matching': null, 'status': {}});
      expect(job.matching, isNull);
      expect(job.score, isNull);
      expect(job.location.label, isNull);
      expect(job.salary.isKnown, isFalse);
      expect(job.recruiter.isEmpty, isTrue);
      expect(job.status.jobStatus, JobStatus.active);
      expect(job.listingUrl, isNull);
    });

    test('mergeDetails garde la description déjà chargée', () {
      final detailed = Job.fromJson({..._jobJson, 'description': 'Texte complet'});
      final light = Job.fromJson(_jobJson);
      expect(light.mergeDetails(detailed).description, 'Texte complet');
      expect(detailed.mergeDetails(light).description, 'Texte complet');
    });
  });

  test('JobStateUpdate n\'envoie que les champs fournis', () {
    expect(const JobStateUpdate(isSaved: true).toJson(), {'is_saved': true});
    expect(const JobStateUpdate(isIgnored: false, seen: true).toJson(), {
      'is_ignored': false,
      'seen': true,
    });
  });

  test('MatchResult trie les critères par poids et lit les indicateurs', () {
    final result = MatchResult.fromJson({
      'job_id': 'j1',
      'score': 90,
      'matched_skills': ['Python'],
      'missing_skills': [],
      'experience_match': true,
      'language_match': null,
      'contract_match': false,
      'reasons': ['Contrat recherché (cdi)'],
      'breakdown': {
        'title': {'score': 1.0, 'weight': 10},
        'skills': {'score': 0.769, 'weight': 40},
        'language': {'score': null, 'weight': 5},
        'contract': {'score': 0, 'weight': 15},
        'experience': {'score': 1.0, 'weight': 20},
      },
      'computed_at': '2026-09-30T08:43:58.359907Z',
    });
    expect(result.criteria.map((c) => c.key), [
      'skills',
      'experience',
      'contract',
      'title',
      'language',
    ]);
    expect(result.criteria.first.score, closeTo(0.769, 1e-9));
    expect(result.criteria.firstWhere((c) => c.key == 'experience').matched, isTrue);
    expect(result.criteria.firstWhere((c) => c.key == 'contract').matched, isFalse);
    final language = result.criteria.firstWhere((c) => c.key == 'language');
    expect(language.isEvaluated, isFalse);
    expect(result.toMatching().score, 90);
  });

  test('JobAnalysis lit les exigences et la méthode', () {
    final analysis = JobAnalysis.fromJson({
      'summary': 'Résumé',
      'responsibilities': [],
      'required_skills': ['Python'],
      'preferred_skills': ['Docker'],
      'experience_level': 'mid',
      'min_years_experience': 3,
      'languages': ['en'],
      'remote_policy': 'remote',
      'highlights': [],
      'red_flags': ['Salaire absent'],
      'requirements': {'education': 'Bac+5', 'must_have': []},
      'generated_by': 'rules',
    });
    expect(analysis.generatedBy, GeneratedBy.rules);
    expect(analysis.education, 'Bac+5');
    expect(analysis.minYearsExperience, 3);
    expect(JobLabels.remotePolicy(analysis.remotePolicy), 'Télétravail');
  });

  test('RecalculateResult distingue la tâche de fond du calcul direct', () {
    expect(RecalculateResult.fromJson({'status': 'queued', 'jobs_matched': null}).isQueued, isTrue);
    final done = RecalculateResult.fromJson({'status': 'done', 'jobs_matched': 296});
    expect(done.isQueued, isFalse);
    expect(done.jobsMatched, 296);
  });

  group('JobFilters', () {
    test('par défaut : tri par date, aucun filtre actif', () {
      const filters = JobFilters();
      expect(filters.activeCount, 0);
      expect(filters.toQuery()['sort_by'], 'published_at');
      expect(filters.toQuery()['sort_order'], 'desc');
      expect(filters.toQuery()['status'], isNull);
    });

    test('toQuery utilise les valeurs de l\'API', () {
      final query = const JobFilters(
        minScore: 70,
        status: JobStatusFilter.newJob,
        scope: JobScope.missions,
        countries: ['France', kNoCountry],
        remote: true,
        sortBy: JobSortField.score,
        sortDesc: false,
      ).toQuery();
      expect(query['min_score'], 70);
      expect(query['status'], 'new');
      expect(query['source_category'], ['clients']);
      expect(query['country'], ['France', kNoCountry]);
      expect(query['remote'], true);
      expect(query['sort_by'], 'score');
      expect(query['sort_order'], 'asc');
    });

    test('copyWith efface avec null et normalise les textes vides', () {
      const base = JobFilters(minScore: 50, location: 'Paris');
      final cleared = base.copyWith(minScore: null, search: '   ', skill: ' Python ');
      expect(cleared.minScore, isNull);
      expect(cleared.search, isNull);
      expect(cleared.skill, 'Python');
      expect(cleared.location, 'Paris');
      expect(cleared.activeCount, 2);
    });

    test('offres d\'emploi = catégories jobs + services', () {
      expect(const JobFilters().toQuery()['source_category'], ['jobs', 'services']);
      expect(JobScope.of(SourceCategory.clients), JobScope.missions);
      expect(JobScope.of(SourceCategory.services), JobScope.offers);
    });

    test('pays : triés, sans doublon, comptés comme un filtre actif', () {
      final filters = const JobFilters().copyWith(countries: ['France', 'Espagne', 'France']);
      expect(filters.countries, ['Espagne', 'France']);
      expect(filters.activeCount, 1);
      expect(filters, const JobFilters().copyWith(countries: ['France', 'Espagne']));
      expect(filters.copyWith(countries: []).activeCount, 0);
      expect(countryLabel(kNoCountry), 'Sans pays (monde)');
    });

    test('CountryCount : pays absent = sans pays', () {
      final none = CountryCount.fromJson({'country': null, 'count': 12});
      expect(none.filterValue, kNoCountry);
      expect(CountryCount.fromJson({'country': 'France', 'count': 3}).filterValue, 'France');
    });

    test('égalité par valeur (clé de la liste)', () {
      expect(const JobFilters(search: 'dev'), const JobFilters(search: 'dev'));
      expect(const JobFilters(search: 'dev').hashCode, const JobFilters(search: 'dev').hashCode);
      expect(const JobFilters(search: 'dev') == const JobFilters(search: 'ops'), isFalse);
    });
  });

  group('JobDraft.toJson', () {
    test('génère un identifiant quand aucun lien n\'est fourni', () {
      final json = JobDraft(title: '  Développeur Flutter ').toJson(now: DateTime(2026, 9, 30));
      expect(json['title'], 'Développeur Flutter');
      expect(json['external_id'], startsWith('manual-'));
      expect(json.containsKey('company'), isFalse);
      expect(json.containsKey('salary'), isFalse);
      expect(json['skills'], isEmpty);
    });

    test('construit les blocs imbriqués de JobCreate', () {
      final json = JobDraft(
        title: 'Lead Python',
        url: 'https://example.com/job/1',
        companyName: 'ACME',
        city: 'Antananarivo',
        country: 'Madagascar',
        remote: true,
        contractType: 'freelance',
        salaryMin: 450,
        salaryCurrency: 'eur',
        salaryPeriod: SalaryPeriod.day,
        skills: const [
          SkillDraft('Python'),
          SkillDraft('Docker', requirement: SkillRequirement.preferred),
        ],
        languages: const ['fr', 'en'],
        applicationEmail: 'rh@acme.mg',
        recruiterName: 'Rina',
        expiresAt: DateTime.utc(2026, 12, 31),
      ).toJson();
      expect(json.containsKey('external_id'), isFalse);
      expect(json['company'], {'name': 'ACME'});
      expect(json['location'], {
        'raw': 'Antananarivo, Madagascar',
        'city': 'Antananarivo',
        'country': 'Madagascar',
        'remote': true,
      });
      expect(json['contract'], {'type': 'freelance'});
      expect(json['salary'], {'min': 450, 'currency': 'EUR', 'period': 'day'});
      expect(json['skills'], [
        {'name': 'Python', 'requirement': 'required'},
        {'name': 'Docker', 'requirement': 'preferred'},
      ]);
      expect(json['application'], {'email': 'rh@acme.mg'});
      expect(json['recruiter'], {'name': 'Rina', 'contact_source': 'manual'});
      expect(json['expires_at'], '2026-12-31T00:00:00.000Z');
    });

    test('SkillDraft.toggled alterne obligatoire / souhaitée', () {
      const skill = SkillDraft('Go');
      expect(skill.toggled().requirement, SkillRequirement.preferred);
      expect(skill.toggled().toggled().requirement, SkillRequirement.required);
    });
  });

  group('JobLabels', () {
    const labels = JobLabels(
      contracts: {'cdi': 'CDI', 'custom': 'Mission'},
      levels: {'mid': 'Confirmé'},
    );

    test('contrats et niveaux', () {
      expect(labels.contract('full_time'), 'Temps plein');
      expect(labels.contract('custom'), 'Mission');
      expect(labels.contract('some_code'), 'Some code');
      expect(labels.contract(null), isNull);
      expect(labels.level('mid'), 'Confirmé');
      expect(labels.level('senior'), 'Senior');
    });

    test('langues, qualité, critères, verdict', () {
      expect(JobLabels.language('en'), 'Anglais');
      expect(JobLabels.language('xx'), 'XX');
      expect(JobLabels.qualityIssue('missing_company'), 'Entreprise non indiquée');
      expect(JobLabels.ingestionError('missing_identifier'), contains('lien'));
      expect(JobLabels.criterion('experience_level'), 'Niveau');
      expect(JobLabels.verdict(90), 'Très compatible');
      expect(JobLabels.verdict(null), 'Pas encore évaluée');
    });
  });
}
