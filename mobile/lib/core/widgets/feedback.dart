import 'package:flutter/material.dart';

import '../network/api_exception.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

/// Messager global : permet d'afficher un message depuis n'importe où (même sans context).
final rootMessengerKey = GlobalKey<ScaffoldMessengerState>();

enum ToastKind { info, success, error }

/// Affiche un message bref en bas de l'écran.
void showToast(String message, {ToastKind kind = ToastKind.info, SnackBarAction? action}) {
  final messenger = rootMessengerKey.currentState;
  if (messenger == null) return;
  final icon = switch (kind) {
    ToastKind.info => Icons.info_outline_rounded,
    ToastKind.success => Icons.check_circle_outline_rounded,
    ToastKind.error => Icons.error_outline_rounded,
  };
  final color = switch (kind) {
    ToastKind.info => AppColors.textSecondary,
    ToastKind.success => AppColors.success,
    ToastKind.error => AppColors.danger,
  };
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        action: action,
        duration: Duration(seconds: kind == ToastKind.error ? 5 : 3),
        content: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const Gap(10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
}

/// Affiche une erreur (ApiException ou autre) sous forme de message.
void showError(Object error) => showToast(ApiException.describe(error), kind: ToastKind.error);

/// Exécute une action asynchrone et affiche le résultat (succès ou erreur).
/// Renvoie le résultat, ou null en cas d'erreur.
Future<T?> runAction<T>(Future<T> Function() action, {String? success}) async {
  try {
    final result = await action();
    if (success != null) showToast(success, kind: ToastKind.success);
    return result;
  } catch (error) {
    showError(error);
    return null;
  }
}

/// Boîte de confirmation. Renvoie true si l'utilisateur confirme.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'Confirmer',
  String cancelLabel = 'Annuler',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel, style: const TextStyle(color: AppColors.textSecondary)),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: AppColors.onAccent,
                  minimumSize: const Size(64, 42),
                )
              : FilledButton.styleFrom(minimumSize: const Size(64, 42)),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Saisie d'un texte dans une boîte de dialogue. Renvoie null si annulé.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  String? label,
  String? initialValue,
  String confirmLabel = 'Valider',
  int maxLines = 1,
  TextInputType? keyboardType,
}) async {
  final controller = TextEditingController(text: initialValue);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLines: maxLines,
        keyboardType: keyboardType,
        decoration: InputDecoration(hintText: label),
        onSubmitted: maxLines == 1 ? (value) => Navigator.of(context).pop(value) : null,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler', style: TextStyle(color: AppColors.textSecondary)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(64, 42)),
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

/// Feuille modale du bas (filtres, formulaires courts, détails).
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required Widget Function(BuildContext context) builder,
  bool expand = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (context) {
      final content = Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: builder(context),
      );
      if (!expand) return content;
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, controller) => PrimaryScrollController(
          controller: controller,
          child: content,
        ),
      );
    },
  );
}

/// En-tête d'une feuille modale : titre + action optionnelle.
class SheetHeader extends StatelessWidget {
  const SheetHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.md, AppSpacing.sm),
    child: Row(
      children: [
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
        ?trailing,
      ],
    ),
  );
}
