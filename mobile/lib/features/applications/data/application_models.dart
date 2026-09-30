import '../../../core/models/enums.dart';
import '../../../core/utils/json.dart';

/// Modèles du module Candidatures (lecture tolérante, écriture explicite).

/// Résumé de l'offre liée à une candidature (`ApplicationJobInfo`).
class ApplicationJob {
  const ApplicationJob({
    required this.id,
    required this.title,
    this.applicationUrl,
    this.applicationEmail,
    this.isExpired = false,
  });

  final String id;
  final String title;
  final String? applicationUrl;
  final String? applicationEmail;
  final bool isExpired;

  factory ApplicationJob.fromJson(Map<String, dynamic> json) => ApplicationJob(
    id: json['id'].toString(),
    title: json['title']?.toString() ?? '',
    applicationUrl: _text(json['application_url']),
    applicationEmail: _text(json['application_email']),
    isExpired: json['is_expired'] as bool? ?? false,
  );
}

/// Candidature (`ApplicationRead`).
class Application {
  const Application({
    required this.id,
    required this.jobTitle,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.jobId,
    this.companyName,
    this.cvDocumentId,
    this.coverLetterDocumentId,
    this.coverLetterText,
    this.emailSubject,
    this.emailBody,
    this.notes,
    this.submittedAt,
    this.submissionMethod,
    this.submissionReference,
    this.followUpAt,
    this.lastContactAt,
    this.responseReceivedAt,
    this.job,
  });

  final String id;
  final String? jobId;
  final String jobTitle;
  final String? companyName;
  final ApplicationStatus status;
  final String? cvDocumentId;
  final String? coverLetterDocumentId;
  final String? coverLetterText;
  final String? emailSubject;
  final String? emailBody;
  final String? notes;
  final DateTime? submittedAt;
  final SubmissionMethod? submissionMethod;
  final String? submissionReference;
  final DateTime? followUpAt;
  final DateTime? lastContactAt;
  final DateTime? responseReceivedAt;
  final ApplicationJob? job;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Application.fromJson(Map<String, dynamic> json) {
    final created = parseDate(json['created_at']) ?? DateTime.now();
    final job = json['job'];
    return Application(
      id: json['id'].toString(),
      jobId: _text(json['job_id']),
      jobTitle: json['job_title']?.toString() ?? '',
      companyName: _text(json['company_name']),
      status: ApplicationStatus.fromApi(json['status']) ?? ApplicationStatus.notApplied,
      cvDocumentId: _text(json['cv_document_id']),
      coverLetterDocumentId: _text(json['cover_letter_document_id']),
      coverLetterText: _text(json['cover_letter_text']),
      emailSubject: _text(json['email_subject']),
      emailBody: _text(json['email_body']),
      notes: _text(json['notes']),
      submittedAt: parseDate(json['submitted_at']),
      submissionMethod: SubmissionMethod.fromApi(json['submission_method']),
      submissionReference: _text(json['submission_reference']),
      followUpAt: parseDate(json['follow_up_at']),
      lastContactAt: parseDate(json['last_contact_at']),
      responseReceivedAt: parseDate(json['response_received_at']),
      job: job is Map ? ApplicationJob.fromJson(job.cast<String, dynamic>()) : null,
      createdAt: created,
      updatedAt: parseDate(json['updated_at']) ?? created,
    );
  }

  /// Titre à afficher (jamais vide).
  String get displayTitle => jobTitle.trim().isEmpty ? 'Candidature sans titre' : jobTitle;

  /// Adresse de candidature connue (offre liée).
  String? get applicationEmail => job?.applicationEmail;

  bool get hasEmailDraft => (emailSubject ?? '').isNotEmpty && (emailBody ?? '').isNotEmpty;

  /// Une relance est attendue (envoyée, date de relance dépassée ou aujourd'hui).
  bool isFollowUpDue([DateTime? now]) {
    final date = followUpAt;
    if (date == null) return false;
    if (status != ApplicationStatus.submitted && status != ApplicationStatus.followUp) return false;
    return !date.isAfter(now ?? DateTime.now());
  }

  /// Transitions proposées dans « Changer le statut » (jamais `submitted` : envoi confirmé uniquement).
  List<ApplicationStatus> get manualTransitions => ApplicationStatus.values
      .where((s) => s != ApplicationStatus.submitted && status.allowedTransitions.contains(s))
      .toList();
}

/// Étapes principales du parcours « Préparer → Valider → Suivre ».
enum ApplicationPhase {
  prepare('Préparer'),
  validate('Valider'),
  follow('Suivre');

  const ApplicationPhase(this.label);
  final String label;

  /// Étape courante d'un statut (null pour un statut final : refusée / abandonnée).
  static ApplicationPhase? of(ApplicationStatus status) => switch (status) {
    ApplicationStatus.notApplied || ApplicationStatus.preparing => prepare,
    ApplicationStatus.ready => validate,
    ApplicationStatus.submitted ||
    ApplicationStatus.followUp ||
    ApplicationStatus.interview ||
    ApplicationStatus.offer => follow,
    ApplicationStatus.rejected || ApplicationStatus.withdrawn => null,
  };
}

/// Prochaine étape, en quelques mots (cartes de la liste).
String? shortNextStep(ApplicationStatus status) => switch (status) {
  ApplicationStatus.notApplied => 'À préparer',
  ApplicationStatus.preparing => 'Brouillons en cours',
  ApplicationStatus.ready => 'Prête à valider',
  ApplicationStatus.submitted => 'En attente de réponse',
  ApplicationStatus.followUp => 'À relancer',
  ApplicationStatus.interview => 'Entretien en cours',
  ApplicationStatus.offer => 'Offre à étudier',
  ApplicationStatus.rejected || ApplicationStatus.withdrawn => null,
};

/// Statistiques de `GET /monitoring/applications`.
class ApplicationStats {
  const ApplicationStats({
    this.total = 0,
    this.byStatus = const {},
    this.submittedTotal = 0,
    this.withResponse = 0,
    this.responseRate = 0,
    this.averageResponseDays,
    this.interviews = 0,
    this.offers = 0,
    this.submittedPerWeek = const {},
    this.responsesReceived = 0,
  });

  final int total;
  final Map<ApplicationStatus, int> byStatus;
  final int submittedTotal;
  final int withResponse;

  /// Taux de réponse entre 0 et 1.
  final double responseRate;
  final double? averageResponseDays;
  final int interviews;
  final int offers;
  final Map<String, int> submittedPerWeek;
  final int responsesReceived;

  int count(ApplicationStatus status) => byStatus[status] ?? 0;

  factory ApplicationStats.fromJson(Map<String, dynamic> json) {
    final byStatus = <ApplicationStatus, int>{};
    parseMap(json['by_status']).forEach((key, value) {
      final status = ApplicationStatus.fromApi(key);
      if (status != null) byStatus[status] = parseInt(value) ?? 0;
    });
    return ApplicationStats(
      total: parseInt(json['total']) ?? 0,
      byStatus: byStatus,
      submittedTotal: parseInt(json['submitted_total']) ?? 0,
      withResponse: parseInt(json['with_response']) ?? 0,
      responseRate: parseDouble(json['response_rate']) ?? 0,
      averageResponseDays: parseDouble(json['average_response_days']),
      interviews: parseInt(json['interviews']) ?? 0,
      offers: parseInt(json['offers']) ?? 0,
      submittedPerWeek: parseMap(
        json['submitted_per_week'],
      ).map((key, value) => MapEntry(key, parseInt(value) ?? 0)),
      responsesReceived: parseInt(json['responses_received']) ?? 0,
    );
  }
}

/// Entrée de l'historique des statuts (`StatusHistoryRead`).
class StatusHistoryEntry {
  const StatusHistoryEntry({
    required this.id,
    required this.toStatus,
    required this.changedAt,
    this.fromStatus,
    this.note,
    this.actorType,
  });

  final String id;
  final ApplicationStatus? fromStatus;
  final ApplicationStatus toStatus;
  final String? note;
  final ActorType? actorType;
  final DateTime changedAt;

  factory StatusHistoryEntry.fromJson(Map<String, dynamic> json) => StatusHistoryEntry(
    id: json['id'].toString(),
    fromStatus: ApplicationStatus.fromApi(json['from_status']),
    toStatus: ApplicationStatus.fromApi(json['to_status']) ?? ApplicationStatus.notApplied,
    note: _text(json['note']),
    actorType: ActorType.fromApi(json['actor_type']),
    changedAt: parseDate(json['changed_at']) ?? DateTime.now(),
  );
}

/// Analyse d'une réponse de recruteur (champ `analysis`).
class ResponseAnalysis {
  const ResponseAnalysis({
    this.summary,
    this.suggestedStatus,
    this.nextSteps = const [],
    this.generatedBy,
  });

  final String? summary;
  final ApplicationStatus? suggestedStatus;
  final List<String> nextSteps;
  final GeneratedBy? generatedBy;

  factory ResponseAnalysis.fromJson(Map<String, dynamic> json) => ResponseAnalysis(
    summary: _text(json['summary']),
    suggestedStatus: ApplicationStatus.fromApi(json['suggested_status']),
    nextSteps: parseStringList(json['next_steps']).where((s) => s.trim().isNotEmpty).toList(),
    generatedBy: GeneratedBy.fromApi(json['generated_by']),
  );
}

/// Réponse d'un recruteur (`RecruiterResponseRead`).
class RecruiterResponse {
  const RecruiterResponse({
    required this.id,
    required this.senderEmail,
    required this.receivedAt,
    required this.responseType,
    required this.isRead,
    this.applicationId,
    this.senderName,
    this.subject,
    this.body,
    this.correlationMethod,
    this.analysis = const ResponseAnalysis(),
    this.createdAt,
  });

  final String id;
  final String? applicationId;
  final String senderEmail;
  final String? senderName;
  final String? subject;
  final String? body;
  final DateTime receivedAt;
  final RecruiterResponseType responseType;
  final String? correlationMethod;
  final ResponseAnalysis analysis;
  final bool isRead;
  final DateTime? createdAt;

  factory RecruiterResponse.fromJson(Map<String, dynamic> json) => RecruiterResponse(
    id: json['id'].toString(),
    applicationId: _text(json['application_id']),
    senderEmail: json['sender_email']?.toString() ?? '',
    senderName: _text(json['sender_name']),
    subject: _text(json['subject']),
    body: _text(json['body']),
    receivedAt: parseDate(json['received_at']) ?? DateTime.now(),
    responseType:
        RecruiterResponseType.fromApi(json['response_type']) ?? RecruiterResponseType.other,
    correlationMethod: _text(json['correlation_method']),
    analysis: ResponseAnalysis.fromJson(parseMap(json['analysis'])),
    isRead: json['is_read'] as bool? ?? false,
    createdAt: parseDate(json['created_at']),
  );

  /// Expéditeur à afficher : nom, sinon adresse.
  String get senderLabel => senderName ?? senderEmail;

  /// Titre à afficher : objet, sinon type.
  String get displaySubject => subject ?? responseType.label;

  /// Aperçu court : résumé de l'analyse, sinon début du message.
  String? get preview {
    final text = analysis.summary ?? body;
    if (text == null) return null;
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  RecruiterResponse copyWith({
    bool? isRead,
    String? applicationId,
    RecruiterResponseType? responseType,
  }) => RecruiterResponse(
    id: id,
    applicationId: applicationId ?? this.applicationId,
    senderEmail: senderEmail,
    senderName: senderName,
    subject: subject,
    body: body,
    receivedAt: receivedAt,
    responseType: responseType ?? this.responseType,
    correlationMethod: correlationMethod,
    analysis: analysis,
    isRead: isRead ?? this.isRead,
    createdAt: createdAt,
  );
}

/// Texte généré (`GeneratedText`).
class GeneratedText {
  const GeneratedText({
    required this.kind,
    required this.content,
    required this.generatedBy,
    this.subject,
  });

  final GenerationKind kind;
  final String? subject;
  final String content;
  final GeneratedBy generatedBy;

  factory GeneratedText.fromJson(Map<String, dynamic> json) => GeneratedText(
    kind: GenerationKind.fromApi(json['kind']) ?? GenerationKind.coverLetter,
    subject: _text(json['subject']),
    content: json['content']?.toString() ?? '',
    generatedBy: GeneratedBy.fromApi(json['generated_by']) ?? GeneratedBy.rules,
  );

  /// Texte complet (objet compris) pour le presse-papiers.
  String get clipboardText => subject == null ? content : 'Objet : $subject\n\n$content';
}

// ---------------------------------------------------------------------------
// Requêtes (écriture)
// ---------------------------------------------------------------------------

/// `POST /applications` — candidature manuelle (sans offre) ou depuis une offre.
class ApplicationCreate {
  const ApplicationCreate({
    this.jobId,
    this.jobTitle,
    this.companyName,
    this.status = ApplicationStatus.notApplied,
    this.cvDocumentId,
    this.notes,
    this.followUpAt,
  }) : assert(jobId != null || jobTitle != null, 'job_title obligatoire sans job_id');

  final String? jobId;
  final String? jobTitle;
  final String? companyName;

  /// `not_applied` ou `preparing` uniquement.
  final ApplicationStatus status;
  final String? cvDocumentId;
  final String? notes;
  final DateTime? followUpAt;

  Map<String, dynamic> toJson() => {
    'job_id': ?jobId,
    'job_title': ?_blankToNull(jobTitle),
    'company_name': ?_blankToNull(companyName),
    'status': status.apiValue,
    'cv_document_id': ?cvDocumentId,
    'notes': ?_blankToNull(notes),
    if (followUpAt != null) 'follow_up_at': followUpAt!.toUtc().toIso8601String(),
  };
}

/// `PUT /applications/{id}` — mise à jour partielle : seules les clés présentes sont envoyées
/// (une valeur nulle efface le champ côté serveur).
class ApplicationUpdate {
  const ApplicationUpdate(this.fields);

  final Map<String, Object?> fields;

  /// Intitulé et entreprise (candidature sans offre).
  factory ApplicationUpdate.details({required String jobTitle, required String? companyName}) =>
      ApplicationUpdate({'job_title': jobTitle.trim(), 'company_name': _blankToNull(companyName)});

  factory ApplicationUpdate.cv(String? documentId) =>
      ApplicationUpdate({'cv_document_id': documentId});

  factory ApplicationUpdate.coverLetter(String? text) =>
      ApplicationUpdate({'cover_letter_text': _blankToNull(text)});

  factory ApplicationUpdate.email({required String? subject, required String? body}) =>
      ApplicationUpdate({'email_subject': _blankToNull(subject), 'email_body': _blankToNull(body)});

  factory ApplicationUpdate.notes({required String? notes, required DateTime? followUpAt}) =>
      ApplicationUpdate({'notes': _blankToNull(notes), 'follow_up_at': followUpAt});

  /// Reprend un texte généré dans le brouillon correspondant (null si le type ne s'y prête pas).
  static ApplicationUpdate? fromGenerated(GeneratedText text) => switch (text.kind) {
    GenerationKind.coverLetter => ApplicationUpdate.coverLetter(text.content),
    GenerationKind.applicationEmail => ApplicationUpdate.email(
      subject: text.subject,
      body: text.content,
    ),
    GenerationKind.jobSummary || GenerationKind.recruiterReply => null,
  };

  Map<String, dynamic> toJson() => fields.map(
    (key, value) => MapEntry(key, value is DateTime ? value.toUtc().toIso8601String() : value),
  );
}

/// `PATCH /applications/{id}/status`.
class StatusChange {
  const StatusChange(this.status, {this.note})
    : assert(status != ApplicationStatus.submitted, 'submitted : uniquement via /submit');

  final ApplicationStatus status;
  final String? note;

  Map<String, dynamic> toJson() => {'status': status.apiValue, 'note': ?_blankToNull(note)};
}

/// `POST /applications/{id}/prepare`.
class PrepareRequest {
  const PrepareRequest({this.language, this.generateCoverLetter = true, this.generateEmail = true});

  /// Langue du CV à choisir automatiquement (`fr`, `en`...).
  final String? language;
  final bool generateCoverLetter;
  final bool generateEmail;

  Map<String, dynamic> toJson() => {
    'language': ?language,
    'generate_cover_letter': generateCoverLetter,
    'generate_email': generateEmail,
  };
}

/// `POST /applications/{id}/generate`.
class GenerateRequest {
  const GenerateRequest(this.kind, {this.responseId, this.save = false});

  final GenerationKind kind;

  /// Obligatoire pour `recruiter_reply`.
  final String? responseId;

  /// false : aperçu seulement, l'utilisateur choisit ensuite de reprendre le texte.
  final bool save;

  Map<String, dynamic> toJson() => {
    'kind': kind.apiValue,
    'response_id': ?responseId,
    'save': save,
  };
}

/// `POST /applications/{id}/submit` — validation explicite de l'envoi.
class SubmitRequest {
  const SubmitRequest({
    required this.confirm,
    this.sendEmail = false,
    this.toEmail,
    this.method,
    this.reference,
  });

  /// Doit valoir true : case « Je confirme l'envoi » cochée par l'utilisateur.
  final bool confirm;
  final bool sendEmail;
  final String? toEmail;

  /// Envoi fait ailleurs (site web, autre) : la candidature est seulement enregistrée comme envoyée.
  final SubmissionMethod? method;
  final String? reference;

  Map<String, dynamic> toJson() => {
    'confirm': confirm,
    'send_email': sendEmail,
    if (sendEmail) 'to_email': ?_blankToNull(toEmail),
    if (!sendEmail && method != null) 'method': method!.apiValue,
    if (!sendEmail) 'reference': ?_blankToNull(reference),
  };
}

/// `POST /applications/responses` — saisie manuelle d'une réponse reçue.
class RecruiterResponseCreate {
  const RecruiterResponseCreate({
    required this.senderEmail,
    this.applicationId,
    this.senderName,
    this.subject,
    this.body,
    this.receivedAt,
  });

  final String senderEmail;
  final String? applicationId;
  final String? senderName;
  final String? subject;
  final String? body;
  final DateTime? receivedAt;

  Map<String, dynamic> toJson() => {
    'sender_email': senderEmail.trim(),
    'application_id': ?applicationId,
    'sender_name': ?_blankToNull(senderName),
    'subject': ?_blankToNull(subject),
    'body': ?_blankToNull(body),
    if (receivedAt != null) 'received_at': receivedAt!.toUtc().toIso8601String(),
  };
}

/// `PATCH /applications/responses/{id}`.
class RecruiterResponseUpdate {
  const RecruiterResponseUpdate({this.applicationId, this.isRead, this.responseType});

  final String? applicationId;
  final bool? isRead;
  final RecruiterResponseType? responseType;

  Map<String, dynamic> toJson() => {
    'application_id': ?applicationId,
    'is_read': ?isRead,
    if (responseType != null) 'response_type': responseType!.apiValue,
  };
}

String? _text(Object? value) {
  if (value == null) return null;
  final text = value.toString();
  return text.trim().isEmpty ? null : text;
}

String? _blankToNull(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
