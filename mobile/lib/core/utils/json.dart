/// Petites fonctions de lecture JSON tolérantes (valeurs absentes ou nulles).
library;

DateTime? parseDate(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toLocal();
}

int? parseInt(Object? value) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

double? parseDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

String? parseString(Object? value) => value?.toString();

List<String> parseStringList(Object? value) =>
    value is List ? value.map((e) => e.toString()).toList() : const [];

Map<String, dynamic> parseMap(Object? value) =>
    value is Map ? value.cast<String, dynamic>() : const {};

List<Map<String, dynamic>> parseMapList(Object? value) =>
    value is List ? value.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() : const [];

/// Date seule au format API (`2026-09-30`).
String formatApiDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
