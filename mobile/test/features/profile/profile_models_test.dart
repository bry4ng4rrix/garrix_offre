import 'package:flutter_test/flutter_test.dart';
import 'package:garrix_offre/core/models/enums.dart';
import 'package:garrix_offre/core/models/reference.dart';
import 'package:garrix_offre/features/profile/data/profile_labels.dart';
import 'package:garrix_offre/features/profile/data/profile_models.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  group('Profile', () {
    // Réponse réelle de GET /profile (API locale, compte de démonstration).
    final json = {
      'id': 'e9cbc2f2-3531-44b7-929e-6179f74b50d4',
      'first_name': 'Jane',
      'last_name': 'Doe',
      'full_name': 'Jane Doe',
      'professional_title': 'Développeuse Full Stack Python / React',
      'email': 'demo@example.com',
      'phone': null,
      'country': 'France',
      'city': 'Paris',
      'professional_address': null,
      'bio': null,
      'availability': 'one_month',
      'available_from': '2026-11-01',
      'years_of_experience': 4,
      'experience_level': 'mid',
      'mobility': 'national',
      'languages': [
        {'code': 'fr', 'level': 'native'},
        {'code': 'EN', 'level': 'fluent'},
      ],
      'linkedin_url': null,
      'github_url': 'https://github.com/jane',
      'portfolio_url': null,
      'minimum_salary': 40000,
      'currency': 'EUR',
      'salary_period': 'year',
      'remote': true,
      'photo_url': null,
      'completion_percent': 69,
      'updated_at': '2026-09-30T08:40:05.431987Z',
    };

    test('lit tous les champs', () {
      final profile = Profile.fromJson(json);
      expect(profile.displayName, 'Jane Doe');
      expect(profile.location, 'Paris, France');
      expect(profile.availability, Availability.oneMonth);
      expect(profile.availableFrom, DateTime(2026, 11, 1));
      expect(profile.mobility, Mobility.national);
      expect(profile.yearsOfExperience, 4);
      expect(profile.languages.map((l) => l.code), ['fr', 'en']);
      expect(profile.languages.last.level, LanguageLevel.fluent);
      expect(profile.salaryPeriod, SalaryPeriod.year);
      expect(profile.minimumSalary, 40000);
      expect(profile.hasPhoto, isFalse);
      expect(profile.completionPercent, 69);
      expect(profile.updatedAt, isNotNull);
    });

    test('liste les champs manquants (comme le calcul de complétude du serveur)', () {
      final missing = Profile.fromJson(json).missingFields;
      expect(missing, containsAll(['téléphone', 'présentation', 'photo']));
      expect(missing, isNot(contains('prénom')));
    });

    test('tolère un profil vide et des valeurs inconnues', () {
      final profile = Profile.fromJson({
        'id': 'x',
        'availability': 'someday',
        'salary_period': 'week',
        'languages': null,
      });
      expect(profile.displayName, isNull);
      expect(profile.availability, isNull);
      expect(profile.salaryPeriod, SalaryPeriod.month);
      expect(profile.languages, isEmpty);
      expect(profile.currency, 'EUR');
    });

    test('la clé de cache de la photo change avec la date de mise à jour', () {
      final a = Profile.fromJson(json);
      final b = Profile.fromJson({...json, 'updated_at': '2026-09-30T09:00:00Z'});
      expect(a.photoCacheKey, isNot(b.photoCacheKey));
    });
  });

  test('ProfileSkill.fromJson', () {
    final skill = ProfileSkill.fromJson({
      'id': '877cd757',
      'skill_id': '5e28e5bd',
      'name': 'Django',
      'category': 'backend',
      'level': 'advanced',
      'years_experience': 2.5,
      'priority': 'high',
      'enabled': false,
    });
    expect(skill.name, 'Django');
    expect(skill.level, SkillLevel.advanced);
    expect(skill.yearsExperience, 2.5);
    expect(skill.priority, Priority.high);
    expect(skill.enabled, isFalse);
  });

  group('Experience', () {
    test('fromJson', () {
      final experience = Experience.fromJson({
        'id': '1',
        'company_name': 'Exemple SAS',
        'job_title': 'Développeur',
        'location': null,
        'start_date': '2022-01-01',
        'end_date': null,
        'is_current': true,
        'description': null,
        'technologies': ['Python', 'Django'],
        'duration_years': 2.7,
      });
      expect(experience.startDate, DateTime(2022, 1, 1));
      expect(experience.isCurrent, isTrue);
      expect(experience.technologies, ['Python', 'Django']);
      expect(experience.durationYears, 2.7);
    });

    test('ExperienceInput.toJson : dates au format API, pas de fin pour un poste actuel', () {
      final body = ExperienceInput(
        companyName: '  Exemple  ',
        jobTitle: 'Dev',
        location: '   ',
        startDate: DateTime(2021, 3, 5),
        endDate: DateTime(2023, 6, 30),
        isCurrent: true,
        technologies: const ['Go'],
      ).toJson();
      expect(body['company_name'], 'Exemple');
      expect(body['location'], isNull);
      expect(body['start_date'], '2021-03-05');
      expect(body['end_date'], isNull);
      expect(body['is_current'], isTrue);
      expect(body['technologies'], ['Go']);
    });
  });

  test('TechnologyPreference.groupedFromJson', () {
    final grouped = TechnologyPreference.groupedFromJson({
      'backend': [
        {
          'id': 'a',
          'skill_id': 's',
          'technology': 'Python',
          'category': 'backend',
          'level': 'intermediate',
          'priority': 'medium',
          'min_years': 2,
          'is_required': true,
          'enabled': true,
        },
      ],
      'other': <Object>[],
    });
    expect(grouped.keys, ['backend', 'other']);
    final python = grouped['backend']!.single;
    expect(python.technology, 'Python');
    expect(python.minYears, 2);
    expect(python.isRequired, isTrue);
    expect(grouped['other'], isEmpty);
  });

  test('JobTitle.fromJson', () {
    final title = JobTitle.fromJson({
      'id': 'cb0d',
      'title': 'Backend Developer',
      'priority': 'low',
      'enabled': true,
    });
    expect(title.title, 'Backend Developer');
    expect(title.priority, Priority.low);
  });

  group('SearchPreferences', () {
    final json = {
      'job_titles': ['Backend Developer'],
      'contract_types': ['cdi', 'freelance'],
      'skills': ['Python', 'React'],
      'experience_levels': ['mid', 'senior'],
      'locations': [
        {'city': 'Paris', 'country': 'France'},
        {'city': null, 'country': 'Madagascar'},
      ],
      'remote': true,
      'hybrid': false,
      'onsite': true,
      'minimum_salary': 40000,
      'currency': 'EUR',
      'salary_period': 'year',
      'languages': ['en', 'fr'],
      'matching_threshold': 70,
    };

    test('fromJson', () {
      final prefs = SearchPreferences.fromJson(json);
      expect(prefs.contractTypes, ['cdi', 'freelance']);
      expect(prefs.locations.map((l) => l.label), ['Paris, France', 'Madagascar']);
      expect(prefs.hybrid, isFalse);
      expect(prefs.salaryPeriod, SalaryPeriod.year);
      expect(prefs.matchingThreshold, 70);
    });

    test('toUpdateJson n\'envoie ni postes ni technologies (gérés ailleurs)', () {
      final body = SearchPreferences.fromJson(json).toUpdateJson();
      expect(body.containsKey('job_titles'), isFalse);
      expect(body.containsKey('skills'), isFalse);
      expect(body['salary_period'], 'year');
      expect(body['locations'], [
        {'city': 'Paris', 'country': 'France'},
        {'city': null, 'country': 'Madagascar'},
      ]);
    });

    test('LocationPreference : égalité insensible à la casse', () {
      expect(
        const LocationPreference(city: 'paris', country: 'FRANCE'),
        const LocationPreference(city: 'Paris', country: 'France'),
      );
    });
  });

  group('MatchingSettings', () {
    final json = {
      'skills_weight': 40,
      'experience_weight': 20,
      'contract_weight': 15,
      'location_weight': 10,
      'salary_weight': 10,
      'language_weight': 5,
      'title_weight': 10,
      'experience_level_weight': 10,
    };

    test('fromJson, total et part normalisée', () {
      final settings = MatchingSettings.fromJson(json);
      expect(settings.total, 120);
      expect(settings.weightOf(MatchingCriterion.skills), 40);
      expect(settings.shareOf(MatchingCriterion.skills), closeTo(33.33, 0.01));
      expect(settings.toJson(), json);
    });

    test('copyWith et égalité', () {
      final settings = MatchingSettings.fromJson(json);
      final changed = settings.copyWith(MatchingCriterion.salary, 0);
      expect(changed == settings, isFalse);
      expect(changed.weightOf(MatchingCriterion.salary), 0);
      expect(changed.copyWith(MatchingCriterion.salary, 10), settings);
    });

    test('poids tous nuls : part à 0 sans division par zéro', () {
      final settings = MatchingSettings.fromJson({});
      expect(settings.total, 0);
      expect(settings.shareOf(MatchingCriterion.title), 0);
    });
  });

  test('RecalculateResult.fromJson', () {
    final queued = RecalculateResult.fromJson({'status': 'queued', 'jobs_matched': null});
    final done = RecalculateResult.fromJson({'status': 'done', 'jobs_matched': 42});
    expect(queued.queued, isTrue);
    expect(done.queued, isFalse);
    expect(done.jobsMatched, 42);
  });

  group('Libellés', () {
    test('durée d\'une expérience', () {
      expect(durationLabel(DateTime(2022, 1, 1), DateTime(2024, 3, 31)), '2 ans 3 mois');
      expect(durationLabel(DateTime(2024, 1, 1), DateTime(2024, 8, 1)), '8 mois');
      expect(durationLabel(DateTime(2023, 1, 1), DateTime(2023, 12, 1)), '1 an');
    });

    test('années', () {
      expect(yearsLabel(1), '1 an');
      expect(yearsLabel(3), '3 ans');
      expect(yearsLabel(1.5), '1,5 an');
    });

    test('période', () {
      expect(periodLabel(DateTime(2022, 1, 1), null, current: true), startsWith('janv. 2022 – '));
      expect(periodLabel(DateTime(2019, 3, 1), DateTime(2021, 6, 1)), 'mars 2019 – juin 2021');
    });

    test('catégories', () {
      const categories = [
        SkillCategory(id: '1', code: 'backend', name: 'Backend'),
        SkillCategory(id: '2', code: 'other', name: 'Autre'),
      ];
      expect(categoryLabel('backend', categories), 'Backend');
      expect(categoryLabel(null, categories), 'Autre');
      expect(categoryLabel('soft_skills', categories), 'Soft skills');
      expect(categoryOrder('other', categories), greaterThan(categoryOrder('backend', categories)));
    });
  });
}
