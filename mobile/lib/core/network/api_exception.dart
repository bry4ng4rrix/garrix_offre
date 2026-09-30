import 'package:dio/dio.dart';

/// Erreur renvoyée par l'API (format `{"success": false, "error": {code, message, details}}`)
/// ou erreur réseau. [userMessage] est le texte à afficher (en français).
class ApiException implements Exception {
  const ApiException({required this.code, required this.message, this.statusCode, this.details});

  final int? statusCode;
  final String code;
  final String message;
  final Object? details;

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isNetwork => code == 'NETWORK_ERROR' || code == 'TIMEOUT';

  /// Message lisible pour l'utilisateur.
  String get userMessage {
    final known = _messages[code];
    if (known != null) return known;
    if (code == 'VALIDATION_ERROR') {
      final fields = fieldErrors;
      if (fields.isNotEmpty) {
        return fields.entries
            .map((e) => e.key.isEmpty ? e.value : '${e.key} : ${e.value}')
            .join('\n');
      }
      return 'Données invalides.';
    }
    if (statusCode != null && statusCode! >= 500) return 'Erreur du serveur. Réessayez plus tard.';
    return message.isNotEmpty ? message : 'Une erreur est survenue.';
  }

  /// Erreurs de validation par champ (`details: [{field, message}]`).
  Map<String, String> get fieldErrors {
    final result = <String, String>{};
    final raw = details;
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          final field = item['field']?.toString() ?? '';
          result[field] = item['message']?.toString() ?? 'Valeur invalide';
        }
      }
    }
    return result;
  }

  factory ApiException.fromDio(DioException error) {
    final response = error.response;
    final data = response?.data;
    if (data is Map && data['error'] is Map) {
      final body = data['error'] as Map;
      return ApiException(
        statusCode: response?.statusCode,
        code: body['code']?.toString() ?? 'ERROR',
        message: body['message']?.toString() ?? '',
        details: body['details'],
      );
    }
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const ApiException(
          code: 'TIMEOUT',
          message: 'Le serveur met trop de temps à répondre.',
        );
      case DioExceptionType.connectionError:
        return const ApiException(
          code: 'NETWORK_ERROR',
          message: 'Impossible de joindre le serveur.',
        );
      case DioExceptionType.cancel:
        return const ApiException(code: 'CANCELLED', message: 'Requête annulée.');
      case DioExceptionType.badCertificate:
        return const ApiException(
          code: 'BAD_CERTIFICATE',
          message: 'Certificat du serveur invalide.',
        );
      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
        return ApiException(
          statusCode: response?.statusCode,
          code: response == null ? 'NETWORK_ERROR' : 'HTTP_${response.statusCode}',
          message: response == null
              ? 'Impossible de joindre le serveur.'
              : 'Erreur HTTP ${response.statusCode}.',
        );
    }
  }

  /// Convertit n'importe quelle erreur en message lisible.
  static String describe(Object error) {
    if (error is ApiException) return error.userMessage;
    if (error is DioException) return ApiException.fromDio(error).userMessage;
    return 'Une erreur inattendue est survenue.';
  }

  @override
  String toString() => 'ApiException($statusCode, $code, $message)';

  static const _messages = <String, String>{
    'NETWORK_ERROR':
        'Impossible de joindre le serveur. Vérifiez votre connexion et l\'adresse du serveur.',
    'TIMEOUT': 'Le serveur met trop de temps à répondre.',
    'INVALID_CREDENTIALS': 'Email ou mot de passe incorrect.',
    'ACCOUNT_DISABLED': 'Ce compte est désactivé.',
    'REGISTRATION_DISABLED':
        'Les inscriptions sont fermées. Demandez un compte à l\'administrateur.',
    'EMAIL_ALREADY_USED': 'Un compte existe déjà avec cet email.',
    'TOKEN_EXPIRED': 'Session expirée. Reconnectez-vous.',
    'TOKEN_REVOKED': 'Session expirée. Reconnectez-vous.',
    'INVALID_TOKEN': 'Session invalide. Reconnectez-vous.',
    'INVALID_REFRESH_TOKEN': 'Session expirée. Reconnectez-vous.',
    'NOT_AUTHENTICATED': 'Vous devez être connecté.',
    'PERMISSION_DENIED': 'Action réservée aux administrateurs.',
    'ADMIN_REQUIRED': 'Action réservée aux administrateurs.',
    'RATE_LIMITED': 'Trop de requêtes. Patientez quelques secondes.',
    'INVALID_PASSWORD': 'Mot de passe actuel incorrect.',
    'CANNOT_MODIFY_SELF': 'Vous ne pouvez pas désactiver ou rétrograder votre propre compte.',
    'FILE_TOO_LARGE': 'Fichier trop volumineux.',
    'PAYLOAD_TOO_LARGE': 'Fichier trop volumineux.',
    'EMPTY_FILE': 'Le fichier est vide.',
    'INVALID_FILE_EXTENSION': 'Type de fichier non autorisé.',
    'INVALID_MIME_TYPE': 'Type de fichier non autorisé.',
    'INVALID_FILE_CONTENT': 'Le contenu du fichier ne correspond pas à son extension.',
    'APPLICATION_ALREADY_EXISTS': 'Une candidature existe déjà pour cette offre.',
    'APPLICATION_ALREADY_SUBMITTED': 'Cette candidature a déjà été envoyée.',
    'APPLICATION_NOT_READY': 'La candidature doit être prête (statut « Prête ») avant l\'envoi.',
    'APPLICATION_NOT_DRAFT': 'Seule une candidature non envoyée peut être supprimée.',
    'CONFIRMATION_REQUIRED': 'Confirmation explicite requise.',
    'INVALID_STATUS_TRANSITION': 'Ce changement de statut n\'est pas autorisé.',
    'NO_APPLICATION_EMAIL': 'Aucune adresse de candidature connue pour cette offre.',
    'EMAIL_DRAFT_MISSING': 'Préparez d\'abord l\'objet et le texte de l\'email.',
    'EMAIL_NOT_CONFIGURED': 'L\'envoi d\'emails n\'est pas configuré sur le serveur.',
    'EMAIL_ERROR': 'L\'envoi de l\'email a échoué.',
    'TELEGRAM_NOT_CONFIGURED': 'Telegram n\'est pas configuré sur le serveur.',
    'TELEGRAM_ERROR': 'L\'envoi Telegram a échoué.',
    'SKILL_ALREADY_ADDED': 'Cette compétence est déjà dans votre profil.',
    'JOB_TITLE_EXISTS': 'Ce poste est déjà dans votre liste.',
    'EXPERIENCE_PREFERENCE_EXISTS': 'Cette technologie est déjà dans votre liste.',
    'SOURCE_DISABLED': 'Cette source est désactivée.',
    'SOURCE_NOT_COLLECTABLE': 'Cette source ne peut pas être collectée par le serveur.',
    'SOURCE_TERMS_NOT_REVIEWED':
        'Les conditions d\'utilisation de la source doivent être vérifiées avant la collecte.',
    'SOURCE_TEST_FAILED': 'Le test de la source a échoué.',
    'WORKER_UNAVAILABLE': 'Le service de tâches de fond est indisponible.',
    'SCRAPING_RUN_FINISHED': 'Cette collecte est déjà terminée.',
    'AI_UNREACHABLE': 'Le service d\'IA est injoignable.',
    'AI_RATE_LIMITED': 'Le service d\'IA est saturé. Réessayez plus tard.',
    'AI_REFUSED': 'L\'IA a refusé de traiter cette demande.',
    'AI_EMPTY_RESPONSE': 'L\'IA n\'a rien renvoyé.',
    'AI_TRUNCATED': 'La réponse de l\'IA est incomplète.',
    'AI_INVALID_RESPONSE': 'Réponse de l\'IA invalide.',
  };
}
