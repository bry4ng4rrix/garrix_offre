import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/widgets/feedback.dart';

/// Ouvre un lien web dans le navigateur (ajoute `https://` si besoin).
Future<void> openExternalUrl(String url) async {
  var text = url.trim();
  if (!RegExp(r'^[a-z][a-z0-9+.-]*:', caseSensitive: false).hasMatch(text)) {
    text = 'https://$text';
  }
  final uri = Uri.tryParse(text);
  if (uri == null) {
    showToast('Lien invalide.', kind: ToastKind.error);
    return;
  }
  await _launchOrCopy(uri, fallback: text);
}

/// Ouvre l'application de messagerie.
Future<void> openEmail(String email) => _launchOrCopy(
  Uri(scheme: 'mailto', path: email.trim()),
  fallback: email.trim(),
);

/// Lance un appel (ou copie le numéro si l'appareil ne sait pas appeler).
Future<void> openPhone(String phone) => _launchOrCopy(
  Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^\d+]'), '')),
  fallback: phone.trim(),
);

/// Copie un texte dans le presse-papiers.
Future<void> copyText(String text, {String message = 'Copié dans le presse-papiers'}) async {
  await Clipboard.setData(ClipboardData(text: text));
  showToast(message, kind: ToastKind.success);
}

Future<void> _launchOrCopy(Uri uri, {required String fallback}) async {
  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    opened = false;
  }
  if (!opened) {
    await copyText(
      fallback,
      message: 'Impossible d\'ouvrir le lien : copié dans le presse-papiers',
    );
  }
}
