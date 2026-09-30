import 'package:flutter_test/flutter_test.dart';
import 'package:garrix_offre/core/models/enums.dart';
import 'package:garrix_offre/features/applications/data/application_models.dart';

// Réponses réelles de l'API locale (`/api/v1/applications...`).
const _readyJson = <String, dynamic>{
  'id': '17af2549-b0d1-412b-a2b9-49e4248b7b72',
  'job_id': '58a5fede-66b6-414d-b491-a35e5608e17c',
  'job_title': 'Backend Developer FastAPI (Remote)',
  'company_name': 'Démo Tech',
  'status': 'ready',
  'cv_document_id': '393ece78-2f9b-4deb-8362-8e6782d220a7',
  'cover_letter_document_id': null,
  'cover_letter_text': 'Madame, Monsieur,\n\nJe vous propose ma candidature...',
  'email_subject': 'Candidature : Backend Developer FastAPI (Remote)',
  'email_body': 'Bonjour,\n\nJe vous adresse ma candidature...',
  'notes': null,
  'submitted_at': null,
  'submission_method': null,
  'submission_reference': null,
  'follow_up_at': null,
  'last_contact_at': null,
  'response_received_at': null,
  'job': {
    'id': '58a5fede-66b6-414d-b491-a35e5608e17c',
    'title': 'Backend Developer FastAPI (Remote)',
    'application_url': 'https://example.org/careers/backend-fastapi',
    'application_email': null,
    'is_expired': false,
  },
  'created_at': '2026-09-30T08:43:47.933382Z',
  'updated_at': '2026-09-30T08:43:54.085424Z',
};

const _submittedJson = <String, dynamic>{
  'id': '8abeeca2-be60-4158-9eac-98894a4b6eb8',
  'job_id': null,
  'job_title': 'Développeur Flutter',
  'company_name': 'Acme Mada',
  'status': 'submitted',
  'cv_document_id': '393ece78-2f9b-4deb-8362-8e6782d220a7',
  'email_subject': 'Candidature : Développeur Flutter',
  'email_body': 'Bonjour,',
  'notes': 'Candidature spontanée',
  'submitted_at': '2026-09-30T08:44:10.962290Z',
  'submission_method': 'website',
  'submission_reference': 'REF-42',
  'follow_up_at': '2026-10-07T08:44:10.962290Z',
  'job': null,
  'created_at': '2026-09-30T08:44:10.561824Z',
  'updated_at': '2026-09-30T08:44:10.956307Z',
};

void main() {
  group('Application', () {
    test('lit une candidature prête liée à une offre', () {
      final app = Application.fromJson(_readyJson);
      expect(app.status, ApplicationStatus.ready);
      expect(app.jobId, '58a5fede-66b6-414d-b491-a35e5608e17c');
      expect(app.companyName, 'Démo Tech');
      expect(app.cvDocumentId, isNotNull);
      expect(app.coverLetterDocumentId, isNull);
      expect(app.hasEmailDraft, isTrue);
      expect(app.job?.applicationUrl, 'https://example.org/careers/backend-fastapi');
      expect(app.applicationEmail, isNull);
      expect(app.job?.isExpired, isFalse);
      expect(app.createdAt.isUtc, isFalse); // converti en heure locale
      expect(app.submittedAt, isNull);
    });

    test('lit une candidature envoyée sans offre', () {
      final app = Application.fromJson(_submittedJson);
      expect(app.status, ApplicationStatus.submitted);
      expect(app.job, isNull);
      expect(app.submissionMethod, SubmissionMethod.website);
      expect(app.submissionReference, 'REF-42');
      expect(app.followUpAt, isNotNull);
      expect(app.isFollowUpDue(DateTime.utc(2026, 10, 1)), isFalse);
      expect(app.isFollowUpDue(DateTime.utc(2026, 10, 8)), isTrue);
    });

    test('tolère les valeurs absentes ou inconnues', () {
      final app = Application.fromJson(const {
        'id': 'x',
        'job_title': '',
        'status': 'nouveau_statut',
        'cover_letter_text': '   ',
      });
      expect(app.status, ApplicationStatus.notApplied);
      expect(app.displayTitle, 'Candidature sans titre');
      expect(app.coverLetterText, isNull);
      expect(app.hasEmailDraft, isFalse);
    });

    test('« Envoyée » n\'est jamais proposé en changement manuel', () {
      final ready = Application.fromJson(_readyJson);
      expect(ready.status.allowedTransitions, contains(ApplicationStatus.submitted));
      expect(ready.manualTransitions, isNot(contains(ApplicationStatus.submitted)));
      expect(
        ready.manualTransitions,
        containsAll([ApplicationStatus.preparing, ApplicationStatus.withdrawn]),
      );
      final submitted = Application.fromJson(_submittedJson);
      expect(
        submitted.manualTransitions,
        [
          ApplicationStatus.followUp,
          ApplicationStatus.interview,
          ApplicationStatus.rejected,
          ApplicationStatus.withdrawn,
        ],
      );
    });

    test('étapes du parcours', () {
      expect(ApplicationPhase.of(ApplicationStatus.notApplied), ApplicationPhase.prepare);
      expect(ApplicationPhase.of(ApplicationStatus.ready), ApplicationPhase.validate);
      expect(ApplicationPhase.of(ApplicationStatus.offer), ApplicationPhase.follow);
      expect(ApplicationPhase.of(ApplicationStatus.rejected), isNull);
      expect(shortNextStep(ApplicationStatus.withdrawn), isNull);
    });
  });

  group('ApplicationStats', () {
    test('lit les statistiques de monitoring', () {
      final stats = ApplicationStats.fromJson(const {
        'total': 2,
        'by_status': {'ready': 1, 'submitted': 1, 'inconnu': 4},
        'submitted_total': 1,
        'with_response': 1,
        'response_rate': 1.0,
        'average_response_days': 0.0,
        'interviews': 0,
        'offers': 0,
        'submitted_per_week': {'2026-W40': 1},
        'responses_received': 1,
      });
      expect(stats.total, 2);
      expect(stats.count(ApplicationStatus.ready), 1);
      expect(stats.count(ApplicationStatus.offer), 0);
      expect(stats.byStatus.length, 2);
      expect(stats.responseRate, 1.0);
      expect(stats.averageResponseDays, 0.0);
      expect(stats.submittedPerWeek['2026-W40'], 1);
    });

    test('valeurs par défaut sans données', () {
      final stats = ApplicationStats.fromJson(const {'average_response_days': null});
      expect(stats.total, 0);
      expect(stats.averageResponseDays, isNull);
      expect(stats.byStatus, isEmpty);
    });
  });

  group('Historique, réponses, textes générés', () {
    test('lit une entrée d\'historique', () {
      final entry = StatusHistoryEntry.fromJson(const {
        'id': 'h1',
        'from_status': null,
        'to_status': 'preparing',
        'note': 'Création',
        'actor_type': 'user',
        'changed_at': '2026-09-30T08:43:47.933382Z',
      });
      expect(entry.fromStatus, isNull);
      expect(entry.toStatus, ApplicationStatus.preparing);
      expect(entry.actorType, ActorType.user);
      expect(entry.note, 'Création');
    });

    test('lit une réponse de recruteur avec son analyse', () {
      final response = RecruiterResponse.fromJson(const {
        'id': '52f52c0d-5576-4260-8300-5af5ce750c99',
        'application_id': '8abeeca2-be60-4158-9eac-98894a4b6eb8',
        'sender_email': 'rh@acme.mg',
        'sender_name': 'RH Acme',
        'subject': 'Entretien',
        'body': 'Bonjour, nous souhaitons vous rencontrer pour un entretien.',
        'received_at': '2026-09-30T08:44:11.166583Z',
        'response_type': 'interview',
        'correlation_method': 'application_id',
        'analysis': {
          'response_type': 'interview',
          'summary': 'Bonjour, nous souhaitons vous rencontrer pour un entretien.',
          'suggested_status': 'interview',
          'next_steps': ['Proposer des créneaux', ''],
          'generated_by': 'rules',
        },
        'is_read': false,
        'created_at': '2026-09-30T08:44:11.141343Z',
      });
      expect(response.responseType, RecruiterResponseType.interview);
      expect(response.isRead, isFalse);
      expect(response.senderLabel, 'RH Acme');
      expect(response.analysis.suggestedStatus, ApplicationStatus.interview);
      expect(response.analysis.nextSteps, ['Proposer des créneaux']);
      expect(response.analysis.generatedBy, GeneratedBy.rules);

      final read = response.copyWith(isRead: true, responseType: RecruiterResponseType.offer);
      expect(read.isRead, isTrue);
      expect(read.responseType, RecruiterResponseType.offer);
      expect(read.applicationId, response.applicationId);
    });

    test('réponse minimale : type inconnu, sans analyse', () {
      final response = RecruiterResponse.fromJson(const {
        'id': 'r2',
        'sender_email': 'x@y.z',
        'response_type': 'bizarre',
        'received_at': '2026-09-30T08:44:11Z',
      });
      expect(response.responseType, RecruiterResponseType.other);
      expect(response.displaySubject, RecruiterResponseType.other.label);
      expect(response.analysis.suggestedStatus, isNull);
      expect(response.preview, isNull);
    });

    test('lit un texte généré', () {
      final text = GeneratedText.fromJson(const {
        'kind': 'application_email',
        'subject': 'Candidature : Développeur Flutter',
        'content': 'Bonjour,',
        'generated_by': 'ai',
      });
      expect(text.kind, GenerationKind.applicationEmail);
      expect(text.generatedBy, GeneratedBy.ai);
      expect(text.clipboardText, 'Objet : Candidature : Développeur Flutter\n\nBonjour,');
    });
  });

  group('Requêtes', () {
    test('création manuelle sans offre', () {
      final json = ApplicationCreate(
        jobTitle: 'Développeur Flutter',
        companyName: '  ',
        status: ApplicationStatus.preparing,
        followUpAt: DateTime.utc(2026, 10, 7, 9),
      ).toJson();
      expect(json, {
        'job_title': 'Développeur Flutter',
        'status': 'preparing',
        'follow_up_at': '2026-10-07T09:00:00.000Z',
      });
    });

    test('mise à jour partielle : les valeurs nulles effacent le champ', () {
      expect(ApplicationUpdate.cv(null).toJson(), {'cv_document_id': null});
      expect(
        ApplicationUpdate.email(subject: ' Objet ', body: '').toJson(),
        {'email_subject': 'Objet', 'email_body': null},
      );
      expect(
        ApplicationUpdate.notes(notes: 'Note', followUpAt: DateTime.utc(2026, 10, 7)).toJson(),
        {'notes': 'Note', 'follow_up_at': '2026-10-07T00:00:00.000Z'},
      );
    });

    test('reprise d\'un texte généré dans le bon brouillon', () {
      const email = GeneratedText(
        kind: GenerationKind.applicationEmail,
        subject: 'Objet',
        content: 'Corps',
        generatedBy: GeneratedBy.rules,
      );
      expect(ApplicationUpdate.fromGenerated(email)?.toJson(), {
        'email_subject': 'Objet',
        'email_body': 'Corps',
      });
      const summary = GeneratedText(
        kind: GenerationKind.jobSummary,
        content: 'Résumé',
        generatedBy: GeneratedBy.rules,
      );
      expect(ApplicationUpdate.fromGenerated(summary), isNull);
    });

    test('envoi : confirmation explicite transmise telle quelle', () {
      expect(
        const SubmitRequest(confirm: true, sendEmail: true, toEmail: 'rh@acme.mg').toJson(),
        {'confirm': true, 'send_email': true, 'to_email': 'rh@acme.mg'},
      );
      expect(
        const SubmitRequest(
          confirm: true,
          method: SubmissionMethod.website,
          reference: 'REF-42',
          toEmail: 'ignore@x.y',
        ).toJson(),
        {'confirm': true, 'send_email': false, 'method': 'website', 'reference': 'REF-42'},
      );
      expect(const SubmitRequest(confirm: false).toJson()['confirm'], isFalse);
    });

    test('préparation, génération, statut, réponses', () {
      expect(const PrepareRequest(language: 'fr', generateEmail: false).toJson(), {
        'language': 'fr',
        'generate_cover_letter': true,
        'generate_email': false,
      });
      expect(
        const GenerateRequest(GenerationKind.recruiterReply, responseId: 'r1').toJson(),
        {'kind': 'recruiter_reply', 'response_id': 'r1', 'save': false},
      );
      expect(const StatusChange(ApplicationStatus.interview, note: ' ').toJson(), {
        'status': 'interview',
      });
      expect(
        const RecruiterResponseUpdate(isRead: true, responseType: RecruiterResponseType.offer)
            .toJson(),
        {'is_read': true, 'response_type': 'offer'},
      );
      expect(
        RecruiterResponseCreate(
          senderEmail: ' rh@acme.mg ',
          subject: 'Entretien',
          body: '',
          receivedAt: DateTime.utc(2026, 9, 30, 10),
        ).toJson(),
        {
          'sender_email': 'rh@acme.mg',
          'subject': 'Entretien',
          'received_at': '2026-09-30T10:00:00.000Z',
        },
      );
    });
  });
}
