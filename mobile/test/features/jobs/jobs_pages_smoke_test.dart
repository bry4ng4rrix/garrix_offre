import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garrix_offre/core/auth/app_user.dart';
import 'package:garrix_offre/core/auth/auth_controller.dart';
import 'package:garrix_offre/core/models/reference.dart';
import 'package:garrix_offre/core/network/paginated.dart';
import 'package:garrix_offre/core/realtime/realtime_service.dart';
import 'package:garrix_offre/core/theme/app_theme.dart';
import 'package:garrix_offre/core/widgets/feedback.dart';
import 'package:garrix_offre/features/dashboard/dashboard_page.dart';
import 'package:garrix_offre/features/dashboard/data/dashboard_models.dart';
import 'package:garrix_offre/features/dashboard/data/dashboard_repository.dart';
import 'package:garrix_offre/features/jobs/data/job_filters.dart';
import 'package:garrix_offre/features/jobs/data/job_models.dart';
import 'package:garrix_offre/features/jobs/data/jobs_repository.dart';
import 'package:garrix_offre/features/jobs/job_detail_page.dart';
import 'package:garrix_offre/features/jobs/job_form_page.dart';
import 'package:garrix_offre/features/jobs/jobs_page.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Tests de fumée : les pages se construisent sans erreur de mise en page (téléphone et
/// grand écran), avec des dépôts factices.

Job _job(String id, String title, int score) => Job.fromJson({
  'id': id,
  'title': title,
  'excerpt': 'Une très belle offre ' * 30,
  'description': 'Description complète.\n' * 40,
  'source': {'name': 'Jobgether', 'category': 'jobs', 'url': 'https://example.com/$id'},
  'company': {
    'name': 'ACME',
    'website': 'https://acme.example',
    'address': {'city': 'Paris', 'country': 'France'},
  },
  'recruiter': {'name': 'Rina', 'email': 'rh@acme.example', 'contact_source': 'job_listing'},
  'location': {'city': 'Paris', 'country': 'France', 'remote': true},
  'contract': {'type': 'cdi', 'work_time': 'full_time'},
  'salary': {'min': 45000, 'max': 55000, 'currency': 'EUR', 'period': 'year'},
  'experience': {'level': 'mid', 'min_years': 3},
  'skills': [
    {'name': 'Python', 'requirement': 'required'},
    {'name': 'Docker', 'requirement': 'preferred'},
  ],
  'languages': ['fr', 'en'],
  'matching': {
    'score': score,
    'matched_skills': ['Python'],
    'missing_skills': ['Docker'],
    'reasons': ['Compétences correspondantes : 1/2'],
    'computed_at': DateTime.now().toUtc().toIso8601String(),
  },
  'application': {'url': 'https://example.com/apply', 'email': 'jobs@acme.example'},
  'status': {
    'state': 'active',
    'is_new': true,
    'is_saved': true,
    'application_status': 'preparing',
    'application_id': 'app-1',
  },
  'quality_issues': ['missing_company'],
  'created_at': DateTime.now().toUtc().toIso8601String(),
});

class _FakeJobsRepository implements JobsRepository {
  final jobs = [
    _job('j1', 'Développeur Full Stack Python / React avec un titre vraiment très long (H/F)', 92),
    _job('j2', 'Lead Python', 71),
  ];

  @override
  Future<Paginated<Job>> search(JobFilters filters, {int page = 1, int pageSize = 20}) async =>
      Paginated(items: jobs, total: jobs.length, page: 1, pageSize: pageSize, pages: 1);

  @override
  Future<Job> get(String id) async => jobs.firstWhere((job) => job.id == id);

  @override
  Future<MatchResult> match(String id) async => MatchResult.fromJson({
    'job_id': id,
    'score': 92,
    'breakdown': {
      'skills': {'score': 0.8, 'weight': 40},
      'language': {'score': null, 'weight': 5},
      'contract': {'score': 1, 'weight': 15},
    },
    'contract_match': true,
  });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDashboardRepository implements DashboardRepository {
  @override
  Future<DashboardOverview> overview() async => DashboardOverview.fromJson({
    'jobs_found_today': 305,
    'new_jobs_today': 296,
    'jobs_analyzed_today': 296,
    'matching_jobs_today': 2,
    'matching_jobs_total': 12,
    'matching_threshold': 70,
    'applications_total': 3,
    'applications_by_status': {'preparing': 1, 'submitted': 1, 'interview': 1},
    'responses_total': 1,
    'services': {'api': 'ok', 'postgres': 'ok', 'redis': 'error'},
  });

  @override
  Future<ApplicationStats> applicationStats() async => ApplicationStats.fromJson({
    'total': 3,
    'by_status': {'preparing': 1, 'submitted': 1, 'interview': 1},
    'submitted_total': 2,
    'response_rate': 0.5,
    'average_response_days': 4.5,
    'interviews': 1,
  });

  @override
  Future<String?> firstName() async => 'Jane';
}

class _FakeUnread extends UnreadCountNotifier {
  @override
  int build() => 3;
}

Future<void> _pump(WidgetTester tester, Widget page, {Size size = const Size(390, 844)}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(
          const AppUser(id: 'u1', email: 'demo@example.com', isActive: true, isSuperuser: true),
        ),
        jobsRepositoryProvider.overrideWithValue(_FakeJobsRepository()),
        dashboardRepositoryProvider.overrideWithValue(_FakeDashboardRepository()),
        unreadCountProvider.overrideWith(_FakeUnread.new),
        realtimeEventsProvider.overrideWith((ref) => const Stream<RealtimeEvent>.empty()),
        aiStatusProvider.overrideWith((ref) async => const AiStatus(enabled: true, provider: 'test')),
        contractTypesProvider.overrideWith(
          (ref) async => const [ContractType(id: 'c1', code: 'cdi', name: 'CDI')],
        ),
        experienceLevelsProvider.overrideWith(
          (ref) async => const [
            ExperienceLevel(id: 'l1', code: 'mid', name: 'Confirmé', rank: 2, minYears: 3),
          ],
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        scaffoldMessengerKey: rootMessengerKey,
        home: page,
      ),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Fait défiler la liste principale de la page jusqu'à [finder].
Future<void> _scrollTo(WidgetTester tester, Finder finder) => tester.scrollUntilVisible(
  finder,
  300,
  scrollable: find
      .descendant(of: find.byType(ListView).first, matching: find.byType(Scrollable))
      .first,
);

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  for (final size in const [Size(360, 740), Size(1280, 860)]) {
    final label = '${size.width.toInt()}px';

    testWidgets('DashboardPage ($label)', (tester) async {
      await _pump(tester, const DashboardPage(), size: size);
      expect(find.text('Bonjour, Jane').evaluate().isNotEmpty ||
          find.text('Bonsoir, Jane').evaluate().isNotEmpty, isTrue);
      expect(find.text('Offres compatibles'), findsOneWidget);
      await _scrollTo(tester, find.text('Taux de réponse'));
      expect(find.text('50 %'), findsOneWidget);
      await _scrollTo(tester, find.text('En erreur'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('JobsPage ($label)', (tester) async {
      await _pump(tester, const JobsPage(), size: size);
      expect(find.textContaining('Lead Python'), findsOneWidget);
      expect(find.text('2 offres'), findsOneWidget);
      await tester.tap(find.text('Filtres'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Afficher les offres'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('JobDetailPage ($label)', (tester) async {
      await _pump(tester, const JobDetailPage(jobId: 'j2'), size: size);
      expect(find.text('Lead Python'), findsOneWidget);
      expect(find.text('Ma candidature'), findsOneWidget);
      expect(find.text('Très compatible'), findsOneWidget);
      await _scrollTo(tester, find.text('Analyser avec l\'IA'));
      await _scrollTo(tester, find.text('Lire la suite'));
      await _scrollTo(tester, find.text('Entreprise non indiquée'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('JobFormPage ($label)', (tester) async {
      await _pump(tester, const JobFormPage(), size: size);
      await tester.tap(find.text('Enregistrer l\'offre'));
      await tester.pump();
      expect(find.text('Champ obligatoire'), findsOneWidget);
      // Libellé facultatif : « Expire le  facultatif ».
      await _scrollTo(tester, find.textContaining('Expire le'));
      expect(tester.takeException(), isNull);
    });
  }
}
