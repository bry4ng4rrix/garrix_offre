import '../../../core/network/api_exception.dart';

/// Libellés français propres à l'administration et messages d'erreur complémentaires.

/// Action du journal d'audit → libellé lisible.
String auditActionLabel(String action) => switch (action) {
  'auth.login' => 'Connexion',
  'auth.login_failed' => 'Échec de connexion',
  'auth.logout' => 'Déconnexion',
  'auth.register' => 'Inscription',
  'user.created' => 'Compte créé',
  'application.submitted' => 'Candidature envoyée',
  'application.status_changed' => 'Statut de candidature modifié',
  'document.uploaded' => 'Document ajouté',
  'document.deleted' => 'Document supprimé',
  'matching.recalculated' => 'Matching recalculé',
  'scraping.run_finished' => 'Collecte terminée',
  'webhook.received' => 'Appel n8n reçu',
  _ => action,
};

/// Familles d'actions filtrables (le serveur filtre par préfixe).
const auditActionGroups = <String, String>{
  'auth.': 'Connexions',
  'user.': 'Comptes',
  'application.': 'Candidatures',
  'document.': 'Documents',
  'scraping.': 'Collectes',
  'matching.': 'Matching',
  'webhook.': 'n8n',
};

/// Types d'entités du journal d'audit.
const auditEntityTypes = <String, String>{
  'user': 'Utilisateur',
  'application': 'Candidature',
  'document': 'Document',
  'scraping_run': 'Collecte',
  'n8n_webhook': 'Webhook n8n',
};

String entityTypeLabel(String? type) =>
    type == null ? '—' : (auditEntityTypes[type] ?? type.replaceAll('_', ' '));

/// Nom lisible d'un service surveillé.
String serviceLabel(String key) => switch (key) {
  'api' => 'API',
  'postgres' => 'PostgreSQL',
  'redis' => 'Redis',
  'worker' => 'Worker',
  'n8n' => 'n8n',
  _ => key,
};

/// Libellé d'un champ d'entreprise (provenance des champs collectés).
String companyFieldLabel(String field) => switch (field) {
  'name' => 'Nom',
  'website' => 'Site web',
  'logo_url' => 'Logo',
  'description' => 'Description',
  'industry' => 'Secteur',
  'employee_count' => 'Effectif',
  'address' => 'Adresse',
  'postal_code' => 'Code postal',
  'city' => 'Ville',
  'country' => 'Pays',
  'email' => 'Email',
  'phone' => 'Téléphone',
  'linkedin_url' => 'LinkedIn',
  'facebook_url' => 'Facebook',
  'instagram_url' => 'Instagram',
  'source_url' => 'Page source',
  _ => field,
};

/// Fournisseur d'IA configuré.
String aiProviderLabel(String? provider) => switch (provider) {
  null || '' || 'none' => 'Désactivée',
  'anthropic' => 'Anthropic (Claude)',
  'openai' => 'OpenAI',
  'ollama' => 'Ollama',
  _ => provider,
};

/// Mode d'envoi des notifications.
String deliveryLabel(String? mode) => switch (mode) {
  'backend' => 'Serveur',
  'n8n' => 'n8n',
  null || '' => '—',
  _ => mode,
};

String environmentLabel(String? env) => switch (env) {
  'production' => 'Production',
  'development' => 'Développement',
  'staging' => 'Pré-production',
  'test' => 'Test',
  null || '' => '—',
  _ => env,
};

/// Messages des codes d'erreur propres aux écrans d'administration.
const _adminMessages = <String, String>{
  'USER_NOT_FOUND': 'Utilisateur introuvable.',
  'SOURCE_NOT_FOUND': 'Source introuvable.',
  'SOURCE_EXISTS': 'Une source porte déjà ce nom.',
  'UNKNOWN_ADAPTER': 'Adapter inconnu du serveur.',
  'ADAPTER_TYPE_MISMATCH': 'Cet adapter ne prend pas en charge ce type de source.',
  'SCRAPING_RUN_NOT_FOUND': 'Collecte introuvable.',
  'COMPANY_NOT_FOUND': 'Entreprise introuvable.',
  'COMPANY_EXISTS': 'Une entreprise porte déjà ce nom.',
  'RECRUITER_NOT_FOUND': 'Recruteur introuvable.',
  'CONTACT_PROVENANCE_REQUIRED':
      'Indiquez la provenance du contact (et l\'URL source pour un site ou un profil public).',
  'CONTRACT_TYPE_EXISTS': 'Ce type de contrat existe déjà.',
  'CONTRACT_TYPE_NOT_FOUND': 'Type de contrat introuvable.',
  'EXPERIENCE_LEVEL_EXISTS': 'Ce niveau d\'expérience existe déjà.',
  'EXPERIENCE_LEVEL_NOT_FOUND': 'Niveau d\'expérience introuvable.',
  'SKILL_CATEGORY_EXISTS': 'Cette catégorie existe déjà.',
  'SKILL_CATEGORY_NOT_FOUND': 'Catégorie introuvable.',
  'UNKNOWN_SKILL_CATEGORY': 'Catégorie de compétences inconnue.',
  'SKILL_NOT_FOUND': 'Compétence introuvable.',
};

/// Message lisible d'une erreur, avec les codes spécifiques à l'administration.
String adminErrorMessage(Object error) {
  if (error is ApiException) {
    final known = _adminMessages[error.code];
    if (known != null) return known;
    if (error.code == 'INVALID_SOURCE_CONFIGURATION') {
      final fields = error.fieldErrors;
      final lines = fields.entries.map((e) => e.key.isEmpty ? e.value : '${e.key} : ${e.value}');
      return ['Configuration invalide pour cet adapter.', ...lines].join('\n');
    }
    if (error.code == 'VALIDATION_ERROR') {
      final fields = error.fieldErrors;
      if (fields.values.any((m) => m.contains('contact_source') || m.contains('source_url'))) {
        return _adminMessages['CONTACT_PROVENANCE_REQUIRED']!;
      }
      if (fields.isNotEmpty) {
        return fields.entries
            .map((e) {
              final message = e.value.replaceFirst('Value error, ', '');
              return e.key.isEmpty ? message : '${e.key} : $message';
            })
            .join('\n');
      }
    }
    if (error.code == 'SOURCE_TEST_FAILED' && error.message.isNotEmpty) {
      return '${error.userMessage}\n${error.message.replaceFirst('Source test failed: ', '')}';
    }
  }
  return ApiException.describe(error);
}
