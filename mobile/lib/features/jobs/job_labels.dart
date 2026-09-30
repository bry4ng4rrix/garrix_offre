import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/reference.dart';

/// Libellés français des codes renvoyés par l'API des offres.
///
/// Les types de contrat et niveaux viennent des données de référence (modifiables par
/// l'admin) ; quelques codes courants ont un libellé français par défaut.
class JobLabels {
  const JobLabels({this.contracts = const {}, this.levels = const {}});

  /// code -> nom (données de référence).
  final Map<String, String> contracts;
  final Map<String, String> levels;

  static const _frenchContracts = {
    'cdi': 'CDI',
    'cdd': 'CDD',
    'freelance': 'Freelance',
    'stage': 'Stage',
    'internship': 'Stage',
    'alternance': 'Alternance',
    'contract': 'Contrat',
    'full_time': 'Temps plein',
    'part_time': 'Temps partiel',
  };

  static const _frenchLevels = {
    'internship': 'Stage / Alternance',
    'junior': 'Junior',
    'mid': 'Confirmé',
    'senior': 'Senior',
    'lead': 'Lead / Expert',
  };

  String? contract(String? code) {
    if (code == null || code.isEmpty) return null;
    return _frenchContracts[code] ?? contracts[code] ?? _humanize(code);
  }

  String? level(String? code) {
    if (code == null || code.isEmpty) return null;
    return levels[code] ?? _frenchLevels[code] ?? _humanize(code);
  }

  static String? workTime(String? code) => switch (code) {
    null || '' => null,
    'full_time' => 'Temps plein',
    'part_time' => 'Temps partiel',
    _ => _humanize(code),
  };

  static String _humanize(String code) {
    final text = code.replaceAll('_', ' ').trim();
    return text.isEmpty ? code : text[0].toUpperCase() + text.substring(1);
  }

  static const _languages = {
    'fr': 'Français',
    'en': 'Anglais',
    'es': 'Espagnol',
    'de': 'Allemand',
    'it': 'Italien',
    'pt': 'Portugais',
    'nl': 'Néerlandais',
    'ar': 'Arabe',
    'zh': 'Chinois',
    'ja': 'Japonais',
    'ru': 'Russe',
    'mg': 'Malgache',
  };

  /// Langues proposées dans le formulaire d'ajout.
  static const formLanguages = ['fr', 'en', 'mg', 'es', 'de', 'it', 'pt'];

  static String language(String code) =>
      _languages[code.toLowerCase()] ?? (code.length <= 3 ? code.toUpperCase() : code);

  static String qualityIssue(String code) => switch (code) {
    'missing_description' => 'Description absente ou très courte',
    'missing_company' => 'Entreprise non indiquée',
    'missing_location' => 'Lieu non indiqué',
    'expires_before_published' => 'Date d\'expiration antérieure à la publication',
    _ => _humanize(code),
  };

  /// Erreurs de validation du pipeline d'ajout (`INVALID_JOB`).
  static String ingestionError(String code) => switch (code) {
    'invalid_title' => 'Titre trop court (3 caractères minimum).',
    'missing_identifier' => 'Indiquez le lien de l\'annonce ou un lien de candidature.',
    'published_in_future' => 'La date de publication est dans le futur.',
    'already_expired' => 'La date d\'expiration est déjà passée.',
    _ => _humanize(code),
  };

  static String criterion(String key) => switch (key) {
    'skills' => 'Compétences',
    'experience' => 'Années d\'expérience',
    'title' => 'Intitulé du poste',
    'contract' => 'Type de contrat',
    'location' => 'Lieu',
    'salary' => 'Salaire',
    'language' => 'Langues',
    'experience_level' => 'Niveau',
    _ => _humanize(key),
  };

  static String? remotePolicy(String? value) => switch (value) {
    'remote' => 'Télétravail',
    'hybrid' => 'Hybride',
    'onsite' => 'Sur site',
    _ => null,
  };

  /// Appréciation d'un score de matching.
  static String verdict(num? score) {
    if (score == null) return 'Pas encore évaluée';
    if (score >= 75) return 'Très compatible';
    if (score >= 50) return 'Compatible';
    if (score >= 30) return 'Peu compatible';
    return 'Faible compatibilité';
  }
}

/// Libellés prêts à l'emploi (vides tant que les données de référence ne sont pas chargées).
final jobLabelsProvider = Provider<JobLabels>((ref) {
  final contracts = ref.watch(contractTypesProvider).value ?? const [];
  final levels = ref.watch(experienceLevelsProvider).value ?? const [];
  return JobLabels(
    contracts: {for (final type in contracts) type.code: type.name},
    levels: {for (final level in levels) level.code: level.name},
  );
});
