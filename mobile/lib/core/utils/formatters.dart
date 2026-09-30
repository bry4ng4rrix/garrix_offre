import 'package:intl/intl.dart';

/// Mise en forme (français) des dates, montants et tailles.
abstract final class Fmt {
  static final _date = DateFormat('d MMM yyyy', 'fr_FR');
  static final _shortDate = DateFormat('d MMM', 'fr_FR');
  static final _dateTime = DateFormat("d MMM yyyy 'à' HH:mm", 'fr_FR');
  static final _time = DateFormat('HH:mm', 'fr_FR');
  static final _number = NumberFormat.decimalPattern('fr_FR');

  /// `30 sept. 2026`
  static String date(DateTime? value) => value == null ? '—' : _date.format(value);

  /// `30 sept. 2026 à 14:05`
  static String dateTime(DateTime? value) => value == null ? '—' : _dateTime.format(value);

  /// `14:05`
  static String time(DateTime? value) => value == null ? '—' : _time.format(value);

  /// `il y a 3 h`, `hier`, `12 sept.`
  static String relative(DateTime? value, {DateTime? now}) {
    if (value == null) return '—';
    final reference = now ?? DateTime.now();
    final diff = reference.difference(value);
    if (diff.isNegative) {
      final ahead = value.difference(reference);
      if (ahead.inDays >= 1) return 'dans ${ahead.inDays} j';
      if (ahead.inHours >= 1) return 'dans ${ahead.inHours} h';
      return 'bientôt';
    }
    if (diff.inMinutes < 1) return 'à l\'instant';
    if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'il y a ${diff.inHours} h';
    if (diff.inDays == 1) return 'hier';
    if (diff.inDays < 7) return 'il y a ${diff.inDays} j';
    if (value.year == reference.year) return _shortDate.format(value);
    return _date.format(value);
  }

  /// `12 500`
  static String number(num? value) => value == null ? '—' : _number.format(value);

  /// Salaire : `45 k – 55 k EUR / an`, `600 EUR / jour`.
  static String salary({num? min, num? max, String? currency, String? period, String? raw}) {
    if (min == null && max == null) return raw?.trim().isNotEmpty == true ? raw!.trim() : '—';
    String amount(num v) => v >= 10000 ? '${_number.format((v / 1000).round())} k' : _number.format(v);
    final range = min != null && max != null && min != max
        ? '${amount(min)} – ${amount(max)}'
        : amount((min ?? max)!);
    final unit = switch (period) {
      'year' => ' / an',
      'month' => ' / mois',
      'day' => ' / jour',
      'hour' => ' / h',
      _ => '',
    };
    return '$range ${currency ?? ''}$unit'.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// `1,2 Mo`
  static String fileSize(num? bytes) {
    if (bytes == null) return '—';
    const units = ['o', 'Ko', 'Mo', 'Go'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final digits = unit == 0 || value >= 10 ? 0 : 1;
    return '${value.toStringAsFixed(digits).replaceAll('.', ',')} ${units[unit]}';
  }

  /// `87 %` (score 0-100).
  static String score(num? value) => value == null ? '—' : '${value.round()} %';

  /// `3 j 4 h` (durée en secondes).
  static String duration(num? seconds) {
    if (seconds == null) return '—';
    final d = Duration(seconds: seconds.round());
    if (d.inDays > 0) return '${d.inDays} j ${d.inHours % 24} h';
    if (d.inHours > 0) return '${d.inHours} h ${d.inMinutes % 60} min';
    if (d.inMinutes > 0) return '${d.inMinutes} min';
    return '${d.inSeconds} s';
  }

  /// Initiales pour un avatar : `jean.dupont@x.com` -> `JD`.
  static String initials(String? value) {
    final text = (value ?? '').split('@').first.trim();
    if (text.isEmpty) return '?';
    final parts = text.split(RegExp(r'[\s._-]+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
    return text.substring(0, text.length >= 2 ? 2 : 1).toUpperCase();
  }
}
