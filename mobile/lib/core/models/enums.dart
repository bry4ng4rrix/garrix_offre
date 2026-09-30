import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Énumérations de l'API avec leur libellé français (et couleur quand c'est utile).
///
/// `XxxEnum.fromApi('value')` renvoie null pour une valeur inconnue ; `.apiValue` redonne la valeur API.

enum ApplicationStatus {
  notApplied('not_applied', 'À postuler', AppColors.textSecondary, Icons.bookmark_border_rounded),
  preparing('preparing', 'En préparation', AppColors.info, Icons.edit_note_rounded),
  ready('ready', 'Prête', AppColors.violet, Icons.task_alt_rounded),
  submitted('submitted', 'Envoyée', AppColors.textPrimary, Icons.send_rounded),
  followUp('follow_up', 'Relance', AppColors.warning, Icons.schedule_send_rounded),
  interview('interview', 'Entretien', AppColors.success, Icons.groups_rounded),
  offer('offer', 'Offre reçue', AppColors.success, Icons.celebration_rounded),
  rejected('rejected', 'Refusée', AppColors.danger, Icons.close_rounded),
  withdrawn('withdrawn', 'Abandonnée', AppColors.textTertiary, Icons.undo_rounded);

  const ApplicationStatus(this.apiValue, this.label, this.color, this.icon);
  final String apiValue;
  final String label;
  final Color color;
  final IconData icon;

  static ApplicationStatus? fromApi(Object? value) => _find(values, value, (e) => e.apiValue);

  /// Transitions autorisées (identiques à `backend/app/modules/applications/rules.py`).
  /// `submitted` ne s'obtient que via `POST /applications/{id}/submit` (confirmation explicite).
  Set<ApplicationStatus> get allowedTransitions => switch (this) {
    notApplied => {preparing, withdrawn},
    preparing => {ready, withdrawn},
    ready => {preparing, submitted, withdrawn},
    submitted => {followUp, interview, rejected, withdrawn},
    followUp => {interview, rejected, withdrawn},
    interview => {offer, rejected, withdrawn},
    offer => {withdrawn},
    rejected || withdrawn => const {},
  };

  bool get isFinal => this == rejected || this == withdrawn;
  bool get isDraft => this == notApplied || this == preparing || this == ready;
}

enum JobStatus {
  newJob('new', 'Nouvelle', AppColors.info),
  active('active', 'Active', AppColors.success),
  expired('expired', 'Expirée', AppColors.warning),
  archived('archived', 'Archivée', AppColors.textTertiary);

  const JobStatus(this.apiValue, this.label, this.color);
  final String apiValue;
  final String label;
  final Color color;

  static JobStatus? fromApi(Object? value) => _find(values, value, (e) => e.apiValue);
}

/// Filtre de statut de la recherche d'offres (`GET /jobs?status=`).
enum JobStatusFilter {
  all('all', 'Toutes'),
  active('active', 'Actives'),
  newJob('new', 'Nouvelles'),
  unseen('unseen', 'Non vues'),
  saved('saved', 'Sauvegardées'),
  applied('applied', 'Postulées'),
  ignored('ignored', 'Ignorées'),
  expired('expired', 'Expirées'),
  archived('archived', 'Archivées');

  const JobStatusFilter(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static JobStatusFilter? fromApi(Object? value) => _find(values, value, (e) => e.apiValue);
}

enum JobSortField {
  score('score', 'Score'),
  publishedAt('published_at', 'Date de publication'),
  createdAt('created_at', 'Date d\'ajout'),
  title('title', 'Titre');

  const JobSortField(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static JobSortField? fromApi(Object? value) => _find(values, value, (e) => e.apiValue);
}

enum SourceCategory {
  jobs('jobs', 'Emplois', Icons.work_outline_rounded),
  clients('clients', 'Missions freelance', Icons.handshake_outlined),
  services('services', 'Services / API', Icons.hub_outlined);

  const SourceCategory(this.apiValue, this.label, this.icon);
  final String apiValue;
  final String label;
  final IconData icon;

  static SourceCategory? fromApi(Object? value) => _find(values, value, (e) => e.apiValue);
}

enum SourceType {
  api('api', 'API'),
  rss('rss', 'Flux RSS'),
  html('html', 'Page HTML'),
  manual('manual', 'Manuelle'),
  webhook('webhook', 'Webhook / email');

  const SourceType(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static SourceType? fromApi(Object? value) => _find(values, value, (e) => e.apiValue);
}

enum FetchMode {
  backend('backend', 'Serveur'),
  n8n('n8n', 'n8n');

  const FetchMode(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static FetchMode? fromApi(Object? value) => _find(values, value, (e) => e.apiValue);
}

enum ScrapingRunStatus {
  pending('pending', 'En attente', AppColors.textSecondary),
  running('running', 'En cours', AppColors.info),
  success('success', 'Réussie', AppColors.success),
  partialSuccess('partial_success', 'Partielle', AppColors.warning),
  failed('failed', 'Échec', AppColors.danger),
  cancelled('cancelled', 'Annulée', AppColors.textTertiary);

  const ScrapingRunStatus(this.apiValue, this.label, this.color);
  final String apiValue;
  final String label;
  final Color color;

  static ScrapingRunStatus? fromApi(Object? value) => _find(values, value, (e) => e.apiValue);
  bool get isActive => this == pending || this == running;
}

enum ScrapingTrigger {
  manual('manual', 'Manuel'),
  n8n('n8n', 'n8n'),
  api('api', 'API');

  const ScrapingTrigger(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static ScrapingTrigger? fromApi(Object? value) => _find(values, value, (e) => e.apiValue);
}

enum NotificationType {
  newJob('new_job', 'Nouvelle offre', Icons.work_outline_rounded, AppColors.info),
  highMatch('high_match', 'Offre très compatible', Icons.bolt_rounded, AppColors.success),
  applicationStatus('application_status', 'Candidature', Icons.send_rounded, AppColors.violet),
  recruiterResponse(
    'recruiter_response',
    'Réponse recruteur',
    Icons.mark_email_unread_outlined,
    AppColors.warning,
  ),
  scrapingError(
    'scraping_error',
    'Erreur de collecte',
    Icons.error_outline_rounded,
    AppColors.danger,
  ),
  system('system', 'Système', Icons.info_outline_rounded, AppColors.textSecondary),
  monitoring('monitoring', 'Monitoring', Icons.monitor_heart_outlined, AppColors.textSecondary);

  const NotificationType(this.apiValue, this.label, this.icon, this.color);
  final String apiValue;
  final String label;
  final IconData icon;
  final Color color;

  static NotificationType? fromApi(Object? value) => _find(values, value, (e) => e.apiValue);
}

enum DocumentType {
  cv('cv', 'CV', Icons.description_outlined),
  coverLetter('cover_letter', 'Lettre de motivation', Icons.article_outlined),
  photo('photo', 'Photo', Icons.image_outlined),
  other('other', 'Autre', Icons.insert_drive_file_outlined);

  const DocumentType(this.apiValue, this.label, this.icon);
  final String apiValue;
  final String label;
  final IconData icon;

  static DocumentType? fromApi(Object? value) => _find(values, value, (e) => e.apiValue);
}

enum SkillLevel {
  beginner('beginner', 'Débutant', 1),
  intermediate('intermediate', 'Intermédiaire', 2),
  advanced('advanced', 'Avancé', 3),
  expert('expert', 'Expert', 4);

  const SkillLevel(this.apiValue, this.label, this.rank);
  final String apiValue;
  final String label;
  final int rank;

  static SkillLevel? fromApi(Object? value) => _find(values, value, (e) => e.apiValue);
}

enum SkillRequirement {
  required('required', 'Obligatoire'),
  preferred('preferred', 'Souhaitée');

  const SkillRequirement(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static SkillRequirement? fromApi(Object? value) => _find(values, value, (e) => e.apiValue);
}

enum Priority {
  low('low', 'Basse'),
  medium('medium', 'Moyenne'),
  high('high', 'Haute');

  const Priority(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static Priority? fromApi(Object? value) => _find(values, value, (e) => e.apiValue);
}

enum LanguageLevel {
  basic('basic', 'Notions'),
  intermediate('intermediate', 'Intermédiaire'),
  fluent('fluent', 'Courant'),
  native('native', 'Langue maternelle');

  const LanguageLevel(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static LanguageLevel? fromApi(Object? value) => _find(values, value, (e) => e.apiValue);
}

enum Availability {
  immediate('immediate', 'Immédiate'),
  oneWeek('one_week', 'Sous 1 semaine'),
  twoWeeks('two_weeks', 'Sous 2 semaines'),
  oneMonth('one_month', 'Sous 1 mois'),
  twoMonths('two_months', 'Sous 2 mois'),
  threeMonths('three_months', 'Sous 3 mois'),
  notAvailable('not_available', 'Non disponible');

  const Availability(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static Availability? fromApi(Object? value) => _find(values, value, (e) => e.apiValue);
}

enum Mobility {
  none('none', 'Aucune'),
  local('local', 'Locale'),
  regional('regional', 'Régionale'),
  national('national', 'Nationale'),
  international('international', 'Internationale');

  const Mobility(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static Mobility? fromApi(Object? value) => _find(values, value, (e) => e.apiValue);
}

enum SalaryPeriod {
  year('year', 'an'),
  month('month', 'mois'),
  day('day', 'jour'),
  hour('hour', 'heure');

  const SalaryPeriod(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static SalaryPeriod? fromApi(Object? value) => _find(values, value, (e) => e.apiValue);
}

enum SubmissionMethod {
  email('email', 'Email'),
  website('website', 'Site web'),
  other('other', 'Autre');

  const SubmissionMethod(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static SubmissionMethod? fromApi(Object? value) => _find(values, value, (e) => e.apiValue);
}

enum GenerationKind {
  coverLetter('cover_letter', 'Lettre de motivation'),
  applicationEmail('application_email', 'Email de candidature'),
  jobSummary('job_summary', 'Résumé de l\'offre'),
  recruiterReply('recruiter_reply', 'Réponse au recruteur');

  const GenerationKind(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static GenerationKind? fromApi(Object? value) => _find(values, value, (e) => e.apiValue);
}

enum GeneratedBy {
  ai('ai', 'IA'),
  rules('rules', 'Modèle');

  const GeneratedBy(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static GeneratedBy? fromApi(Object? value) => _find(values, value, (e) => e.apiValue);
}

enum RecruiterResponseType {
  interview('interview', 'Entretien', AppColors.success),
  rejection('rejection', 'Refus', AppColors.danger),
  offer('offer', 'Offre', AppColors.success),
  informationRequest('information_request', 'Demande d\'information', AppColors.warning),
  acknowledgement('acknowledgement', 'Accusé de réception', AppColors.textSecondary),
  other('other', 'Autre', AppColors.textSecondary);

  const RecruiterResponseType(this.apiValue, this.label, this.color);
  final String apiValue;
  final String label;
  final Color color;

  static RecruiterResponseType? fromApi(Object? value) => _find(values, value, (e) => e.apiValue);
}

enum ContactSource {
  jobListing('job_listing', 'Annonce'),
  companyWebsite('company_website', 'Site de l\'entreprise'),
  publicProfile('public_profile', 'Profil public'),
  api('api', 'API'),
  manual('manual', 'Saisie manuelle'),
  other('other', 'Autre');

  const ContactSource(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static ContactSource? fromApi(Object? value) => _find(values, value, (e) => e.apiValue);
}

enum DataOrigin {
  manual('manual', 'Manuelle'),
  scraping('scraping', 'Collecte'),
  api('api', 'API'),
  n8n('n8n', 'n8n');

  const DataOrigin(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static DataOrigin? fromApi(Object? value) => _find(values, value, (e) => e.apiValue);
}

enum ActorType {
  user('user', 'Utilisateur'),
  n8n('n8n', 'n8n'),
  system('system', 'Système');

  const ActorType(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static ActorType? fromApi(Object? value) => _find(values, value, (e) => e.apiValue);
}

T? _find<T>(List<T> values, Object? value, String Function(T) api) {
  if (value == null) return null;
  final text = value.toString();
  for (final item in values) {
    if (api(item) == text) return item;
  }
  return null;
}
