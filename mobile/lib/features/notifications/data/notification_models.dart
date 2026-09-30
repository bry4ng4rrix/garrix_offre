import '../../../core/models/enums.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/json.dart';

/// Notification de l'utilisateur (`NotificationRead`).
///
/// Nommée `AppNotification` pour ne pas masquer la classe `Notification` de Flutter.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.typeValue,
    required this.title,
    required this.message,
    required this.data,
    required this.isRead,
    required this.deliveredChannels,
    this.readAt,
    this.createdAt,
  });

  final String id;

  /// Null si le serveur renvoie un type inconnu de l'application.
  final NotificationType? type;
  final String typeValue;
  final String title;
  final String message;
  final Map<String, dynamic> data;
  final bool isRead;
  final DateTime? readAt;
  final List<String> deliveredChannels;
  final DateTime? createdAt;

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
    id: json['id']?.toString() ?? '',
    type: NotificationType.fromApi(json['type']),
    typeValue: json['type']?.toString() ?? '',
    title: json['title']?.toString() ?? '',
    message: json['message']?.toString() ?? '',
    data: parseMap(json['data']),
    isRead: json['is_read'] as bool? ?? false,
    readAt: parseDate(json['read_at']),
    deliveredChannels: parseStringList(json['delivered_channels']),
    createdAt: parseDate(json['created_at']),
  );

  AppNotification markedRead() => AppNotification(
    id: id,
    type: type,
    typeValue: typeValue,
    title: title,
    message: message,
    data: data,
    isRead: true,
    readAt: readAt ?? DateTime.now(),
    deliveredChannels: deliveredChannels,
    createdAt: createdAt,
  );

  /// Score de matching éventuel (`high_match`).
  num? get score {
    final value = data['score'];
    return value is num ? value : num.tryParse(value?.toString() ?? '');
  }

  /// Canaux externes utilisés, en français (`Telegram, Email`).
  String get deliveredLabel => deliveredChannels
      .map(
        (channel) => switch (channel) {
          'telegram' => 'Telegram',
          'email' => 'Email',
          'n8n' => 'n8n',
          _ => channel,
        },
      )
      .join(', ');
}

/// Destination d'une notification dans l'application.
class NotificationLink {
  const NotificationLink(this.location, {this.switchTab = false, required this.label});

  final String location;

  /// true : c'est un onglet principal (`context.go`) ; false : page de détail (`context.push`).
  final bool switchTab;

  /// Libellé du bouton « Ouvrir ... ».
  final String label;
}

/// Calcule la page à ouvrir à partir des données de la notification (null si aucune).
///
/// Données envoyées par le serveur :
/// - `high_match` : job_id, job_title, company_name, score... ;
/// - `new_job` : count, job_ids ;
/// - `application_status` : application_id, job_id, status... ;
/// - `recruiter_response` : response_id, application_id (peut être null)... ;
/// - `scraping_error` : run_id, source_id... (administrateurs) ;
/// - `monitoring` : level (administrateurs).
NotificationLink? notificationLink(AppNotification notification, {bool isAdmin = false}) {
  String? id(String key) {
    final value = notification.data[key];
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  final applicationId = id('application_id');
  final jobId = id('job_id');

  switch (notification.type) {
    case NotificationType.newJob:
      final ids = parseStringList(notification.data['job_ids']);
      if (ids.length == 1) return NotificationLink(Routes.job(ids.first), label: 'Voir l\'offre');
      if (jobId != null) return NotificationLink(Routes.job(jobId), label: 'Voir l\'offre');
      return const NotificationLink(Routes.jobs, switchTab: true, label: 'Voir les offres');
    case NotificationType.highMatch:
      if (jobId != null) return NotificationLink(Routes.job(jobId), label: 'Voir l\'offre');
      return const NotificationLink(Routes.jobs, switchTab: true, label: 'Voir les offres');
    case NotificationType.applicationStatus:
      if (applicationId != null) {
        return NotificationLink(Routes.application(applicationId), label: 'Voir la candidature');
      }
      if (jobId != null) return NotificationLink(Routes.job(jobId), label: 'Voir l\'offre');
      return null;
    case NotificationType.recruiterResponse:
      if (applicationId != null) {
        return NotificationLink(Routes.application(applicationId), label: 'Voir la candidature');
      }
      return const NotificationLink(Routes.recruiterResponses, label: 'Voir les réponses');
    case NotificationType.scrapingError:
      if (!isAdmin) return null;
      final sourceId = id('source_id');
      if (sourceId != null) {
        return NotificationLink(Routes.adminSource(sourceId), label: 'Voir la source');
      }
      return const NotificationLink(Routes.adminRuns, label: 'Voir les collectes');
    case NotificationType.monitoring:
      return isAdmin
          ? const NotificationLink(Routes.adminSystem, label: 'Voir l\'état du système')
          : null;
    case NotificationType.system:
    case null:
      if (applicationId != null) {
        return NotificationLink(Routes.application(applicationId), label: 'Voir la candidature');
      }
      if (jobId != null) return NotificationLink(Routes.job(jobId), label: 'Voir l\'offre');
      return null;
  }
}

/// Préférences de notification (`NotificationSettingsRead`).
class NotificationSettings {
  const NotificationSettings({
    required this.telegramEnabled,
    required this.emailEnabled,
    required this.externalTypes,
    this.telegramChatId,
    this.emailTo,
    this.telegramConfigured = false,
    this.emailConfigured = false,
  });

  final bool telegramEnabled;
  final String? telegramChatId;
  final bool emailEnabled;
  final String? emailTo;

  /// Types envoyés sur Telegram / Email (tous restent visibles dans l'application).
  final Set<NotificationType> externalTypes;

  /// Le bot Telegram est configuré côté serveur.
  final bool telegramConfigured;

  /// Le serveur SMTP est configuré côté serveur.
  final bool emailConfigured;

  factory NotificationSettings.fromJson(Map<String, dynamic> json) => NotificationSettings(
    telegramEnabled: json['telegram_enabled'] as bool? ?? false,
    telegramChatId: _blankToNull(json['telegram_chat_id']),
    emailEnabled: json['email_enabled'] as bool? ?? false,
    emailTo: _blankToNull(json['email_to']),
    externalTypes: parseStringList(
      json['external_types'],
    ).map(NotificationType.fromApi).whereType<NotificationType>().toSet(),
    telegramConfigured: json['telegram_configured'] as bool? ?? false,
    emailConfigured: json['email_configured'] as bool? ?? false,
  );

  /// Corps de `PUT /notifications/settings` (`NotificationSettingsUpdate`).
  /// Un champ texte vide est envoyé à null pour effacer la valeur enregistrée.
  Map<String, dynamic> toUpdateJson() => {
    'telegram_enabled': telegramEnabled,
    'telegram_chat_id': _blankToNull(telegramChatId),
    'email_enabled': emailEnabled,
    'email_to': _blankToNull(emailTo),
    'external_types': [
      for (final type in NotificationType.values)
        if (externalTypes.contains(type)) type.apiValue,
    ],
  };
}

/// Même règle que le serveur : identifiant numérique (`123456`, `-100123...`) ou `@canal`.
final telegramChatIdPattern = RegExp(r'^-?\d+$|^@\w+$');

String? _blankToNull(Object? value) {
  final text = value?.toString().trim();
  return (text == null || text.isEmpty) ? null : text;
}
