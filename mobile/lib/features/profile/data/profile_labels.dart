import 'package:intl/intl.dart';

import '../../../core/models/enums.dart';
import '../../../core/models/reference.dart';
import '../../../core/utils/formatters.dart';

/// Libellés et listes de valeurs propres aux écrans du profil.

/// Langues proposées (code ISO 639-1 → nom français), les plus courantes en premier.
const kLanguages = <String, String>{
  'fr': 'Français',
  'en': 'Anglais',
  'mg': 'Malgache',
  'es': 'Espagnol',
  'de': 'Allemand',
  'it': 'Italien',
  'pt': 'Portugais',
  'ar': 'Arabe',
  'zh': 'Chinois',
  'ja': 'Japonais',
  'ru': 'Russe',
  'nl': 'Néerlandais',
  'hi': 'Hindi',
  'ko': 'Coréen',
  'tr': 'Turc',
  'pl': 'Polonais',
  'sv': 'Suédois',
  'sw': 'Swahili',
  'vi': 'Vietnamien',
  'id': 'Indonésien',
  'el': 'Grec',
  'ro': 'Roumain',
  'uk': 'Ukrainien',
  'he': 'Hébreu',
};

/// Nombre de langues affichées d'emblée dans les préférences.
const kCommonLanguageCount = 8;

/// Nom d'une langue à partir de son code (le code en majuscules si inconnu).
String languageName(String code) => kLanguages[code.toLowerCase()] ?? code.toUpperCase();

/// Devises proposées.
const kCurrencies = ['EUR', 'USD', 'MGA', 'GBP', 'CHF', 'CAD', 'XOF', 'XAF', 'MUR', 'MAD', 'ZAR'];

/// « Par mois », « Par an »...
String salaryPeriodLabel(SalaryPeriod period) => 'Par ${period.label}';

/// Libellé d'une catégorie de compétence à partir de son code.
String categoryLabel(String? code, List<SkillCategory> categories) {
  if (code == null || code.isEmpty) return 'Autre';
  for (final category in categories) {
    if (category.code == code) return category.name;
  }
  final text = code.replaceAll('_', ' ');
  return text[0].toUpperCase() + text.substring(1);
}

/// Ordre d'affichage d'une catégorie (celui du référentiel, « Autre » en dernier).
int categoryOrder(String code, List<SkillCategory> categories) {
  if (code == 'other') return 1 << 20;
  final index = categories.indexWhere((c) => c.code == code);
  return index < 0 ? 1 << 19 : index;
}

/// Nom d'un niveau d'expérience à partir de son code.
String experienceLevelName(String? code, List<ExperienceLevel> levels) {
  if (code == null || code.isEmpty) return '—';
  for (final level in levels) {
    if (level.code == code) return level.name;
  }
  return code;
}

/// « 1 an », « 3 ans », « 1,5 an ».
String yearsLabel(num years) {
  final text = Fmt.number(years);
  return years >= 2 ? '$text ans' : '$text an';
}

/// Durée entre deux dates : « 2 ans 3 mois », « 8 mois ».
String durationLabel(DateTime start, DateTime? end) {
  final to = end ?? DateTime.now();
  var months = (to.year - start.year) * 12 + (to.month - start.month) + 1;
  if (months < 1) months = 1;
  final years = months ~/ 12;
  final rest = months % 12;
  final parts = [if (years > 0) years >= 2 ? '$years ans' : '1 an', if (rest > 0) '$rest mois'];
  return parts.join(' ');
}

/// Libellé court d'une priorité (« Priorité haute »).
String priorityLabel(Priority priority) => 'Priorité ${priority.label.toLowerCase()}';

final _monthYear = DateFormat('MMM yyyy', 'fr_FR');

/// « janv. 2022 ».
String monthYear(DateTime date) => _monthYear.format(date);

/// Période d'une expérience : « janv. 2022 – aujourd'hui », « mars 2019 – juin 2021 ».
String periodLabel(DateTime start, DateTime? end, {bool current = false}) {
  if (current) return '${monthYear(start)} – aujourd\'hui';
  if (end == null) return monthYear(start);
  return '${monthYear(start)} – ${monthYear(end)}';
}
