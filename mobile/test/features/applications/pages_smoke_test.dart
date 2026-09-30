import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garrix_offre/core/models/enums.dart';
import 'package:garrix_offre/core/models/reference.dart';
import 'package:garrix_offre/core/network/paginated.dart';
import 'package:garrix_offre/core/realtime/realtime_service.dart';
import 'package:garrix_offre/core/theme/app_theme.dart';
import 'package:garrix_offre/core/widgets/feedback.dart';
import 'package:garrix_offre/features/applications/application_detail_page.dart';
import 'package:garrix_offre/features/applications/applications_page.dart';
import 'package:garrix_offre/features/applications/data/application_models.dart';
import 'package:garrix_offre/features/applications/data/applications_repository.dart';
import 'package:garrix_offre/features/applications/recruiter_responses_page.dart';
import 'package:garrix_offre/features/documents/data/document_models.dart';
import 'package:garrix_offre/features/documents/data/documents_repository.dart';
import 'package:garrix_offre/features/documents/documents_page.dart';
import 'package:intl/date_symbol_data_local.dart';

// Tests d'affichage (pas de serveur) : les pages se construisent sans erreur de mise en page,
// et l'envoi exige la case de confirmation.

Application _app(String status, {String id = 'a1'}) => Application.fromJson({
  'id': id,
  'job_id': 'j1',
  'job_title': 'Backend Developer FastAPI (Remote)',
  'company_name': 'Démo Tech',
  'status': status,
  'cv_document_id': 'd1',
  'cover_letter_text': 'Madame, Monsieur,\n\nJe vous propose ma candidature.',
  'email_subject': 'Candidature : Backend Developer',
  'email_body': 'Bonjour,\n\nVeuillez trouver mon CV.\n\nCordialement',
  'notes': 'Contact : Marie',
  'submitted_at': status == 'submitted' ? '2026-09-30T08:44:10Z' : null,
  'submission_method': status == 'submitted' ? 'website' : null,
  'follow_up_at': status == 'submitted' ? '2026-10-07T08:44:10Z' : null,
  'job': {
    'id': 'j1',
    'title': 'Backend Developer FastAPI (Remote)',
    'application_url': 'https://example.org/careers/backend',
    'application_email': 'jobs@example.org',
    'is_expired': false,
  },
  'created_at': '2026-09-30T08:43:47Z',
  'updated_at': '2026-09-30T08:43:54Z',
});

final _response = RecruiterResponse.fromJson(const {
  'id': 'r1',
  'application_id': 'a1',
  'sender_email': 'rh@acme.mg',
  'sender_name': 'RH Acme',
  'subject': 'Entretien',
  'body': 'Nous souhaitons vous rencontrer.',
  'received_at': '2026-09-30T08:44:11Z',
  'response_type': 'interview',
  'analysis': {'summary': 'Proposition d\'entretien', 'suggested_status': 'interview'},
  'is_read': false,
});

final _cv = UserDocument.fromJson(const {
  'id': 'd1',
  'document_type': 'cv',
  'title': 'CV développeur',
  'original_filename': 'cv.pdf',
  'extension': 'pdf',
  'size_bytes': 120000,
  'language': 'fr',
  'target_job_title': 'Développeur backend',
  'is_active': true,
  'is_primary': true,
  'created_at': '2026-09-30T08:43:41Z',
});

Paginated<T> _page<T>(List<T> items) =>
    Paginated(items: items, total: items.length, page: 1, pageSize: 20, pages: 1);

class _FakeApplications implements ApplicationsRepository {
  _FakeApplications(this.application);

  Application application;
  final submits = <SubmitRequest>[];

  @override
  Future<Paginated<Application>> list({
    int page = 1,
    int pageSize = 20,
    ApplicationStatus? status,
    String? jobId,
  }) async => _page([application, _app('submitted', id: 'a2')]);

  @override
  Future<Application> get(String id) async => application;

  @override
  Future<ApplicationStats> stats() async => ApplicationStats.fromJson(const {
    'total': 2,
    'by_status': {'ready': 1, 'submitted': 1},
    'submitted_total': 1,
    'response_rate': 0.5,
    'interviews': 1,
    'offers': 1,
    'average_response_days': 3.5,
  });

  @override
  Future<List<StatusHistoryEntry>> history(String id) async => [
    StatusHistoryEntry.fromJson(const {
      'id': 'h1',
      'to_status': 'preparing',
      'note': 'Création',
      'actor_type': 'user',
      'changed_at': '2026-09-30T08:43:47Z',
    }),
    StatusHistoryEntry.fromJson(const {
      'id': 'h2',
      'from_status': 'preparing',
      'to_status': 'ready',
      'note': 'Brouillons générés',
      'actor_type': 'n8n',
      'changed_at': '2026-09-30T08:43:54Z',
    }),
  ];

  @override
  Future<Paginated<RecruiterResponse>> responses({
    int page = 1,
    int pageSize = 20,
    String? applicationId,
  }) async => _page([_response]);

  @override
  Future<Application> submit(String id, SubmitRequest request) async {
    submits.add(request);
    return application = _app('submitted');
  }

  @override
  Future<RecruiterResponse> updateResponse(String id, RecruiterResponseUpdate data) async =>
      _response.copyWith(isRead: data.isRead);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

class _FakeDocuments implements DocumentsRepository {
  @override
  Future<Paginated<UserDocument>> list({
    int page = 1,
    int pageSize = 20,
    DocumentType? type,
    bool? isActive,
  }) async => _page([_cv]);

  @override
  Future<UserDocument> get(String id) async => _cv;

  @override
  Future<Uint8List> download(UserDocument document) async => Uint8List(0);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

Future<void> _pump(WidgetTester tester, Widget page, _FakeApplications repository) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        applicationsRepositoryProvider.overrideWithValue(repository),
        documentsRepositoryProvider.overrideWithValue(_FakeDocuments()),
        realtimeEventsProvider.overrideWith((ref) => const Stream<RealtimeEvent>.empty()),
        aiStatusProvider.overrideWith(
          (ref) async => const AiStatus(enabled: false, provider: 'none'),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        scaffoldMessengerKey: rootMessengerKey,
        locale: const Locale('fr', 'FR'),
        supportedLocales: const [Locale('fr', 'FR')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: page,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  testWidgets('liste des candidatures : chiffres clés, filtres, cartes', (tester) async {
    await _pump(tester, const ApplicationsPage(), _FakeApplications(_app('ready')));
    expect(find.text('Candidatures'), findsWidgets);
    expect(find.text('50 %'), findsOneWidget);
    expect(find.text('Backend Developer FastAPI (Remote)'), findsNWidgets(2));
    expect(find.text('Prête à valider'), findsOneWidget);
    expect(find.text('Nouvelle'), findsOneWidget);
  });

  testWidgets('envoi : impossible sans cocher la confirmation', (tester) async {
    final repository = _FakeApplications(_app('ready'));
    await _pump(tester, const ApplicationDetailPage(applicationId: 'a1'), repository);

    expect(find.text('Valider'), findsOneWidget); // étape du parcours
    // La carte du CV est sous l'offre : on fait défiler la page pour l'atteindre.
    await tester.scrollUntilVisible(
      find.text('CV développeur'),
      200,
      scrollable: find
          .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
          .first,
    );
    expect(find.text('CV développeur'), findsOneWidget);
    await tester.tap(find.text('Valider l\'envoi'));
    await tester.pumpAndSettle();

    final send = find.widgetWithText(FilledButton, 'Envoyer la candidature');
    expect(send, findsOneWidget);
    expect(tester.widget<FilledButton>(send).onPressed, isNull);

    // La feuille défile : la case de confirmation est sous le récapitulatif.
    Future<void> inSheet(Finder finder, {double delta = 200}) async {
      await tester.scrollUntilVisible(
        finder,
        delta,
        scrollable: find
            .descendant(of: find.byType(ListView).last, matching: find.byType(Scrollable))
            .first,
      );
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
    }
    final confirm = find.text('Je confirme l\'envoi de cette candidature');

    await inSheet(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(send).onPressed, isNotNull);

    // Changer de mode d'envoi exige une nouvelle confirmation.
    await inSheet(find.text('Envoyée sur le site'), delta: -200);
    await tester.tap(find.text('Envoyée sur le site'));
    await tester.pumpAndSettle();
    final mark = find.widgetWithText(FilledButton, 'Marquer comme envoyée');
    expect(tester.widget<FilledButton>(mark).onPressed, isNull);

    await inSheet(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    await tester.tap(mark);
    await tester.pumpAndSettle();

    expect(repository.submits, hasLength(1));
    expect(repository.submits.single.confirm, isTrue);
    expect(repository.submits.single.method, SubmissionMethod.website);
    expect(repository.submits.single.sendEmail, isFalse);
    expect(find.text('Changer le statut'), findsOneWidget); // statut « Envoyée » affiché
  });

  testWidgets('détail d\'une candidature envoyée : réponses et historique', (tester) async {
    await _pump(
      tester,
      const ApplicationDetailPage(applicationId: 'a1'),
      _FakeApplications(_app('submitted')),
    );
    await tester.scrollUntilVisible(find.text('Brouillons générés'), 300);
    expect(find.text('Entretien'), findsWidgets);
    expect(find.text('Brouillons générés'), findsOneWidget);
  });

  testWidgets('réponses des recruteurs : liste et détail', (tester) async {
    await _pump(tester, const RecruiterResponsesPage(), _FakeApplications(_app('submitted')));
    expect(find.text('RH Acme'), findsOneWidget);
    await tester.tap(find.text('RH Acme'));
    await tester.pumpAndSettle();
    expect(find.text('Réponse du recruteur'), findsOneWidget);
    expect(find.text('Statut suggéré : Entretien'), findsOneWidget);
  });

  testWidgets('documents : liste et actions', (tester) async {
    await _pump(tester, const DocumentsPage(), _FakeApplications(_app('ready')));
    expect(find.text('CV développeur'), findsOneWidget);
    expect(find.text('Principal'), findsOneWidget);
    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    expect(find.text('Désactiver'), findsOneWidget);
    expect(find.text('Supprimer'), findsOneWidget);
  });
}
