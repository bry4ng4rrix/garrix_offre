import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/models/enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/ui.dart';

/// Pastille de statut d'une candidature.
class ApplicationStatusPill extends StatelessWidget {
  const ApplicationStatusPill(this.status, {super.key, this.dense = false});

  final ApplicationStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) =>
      Pill(status.label, color: status.color, icon: status.icon, dense: dense);
}

/// Encadré d'information ou d'erreur, avec action optionnelle.
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({
    super.key,
    required this.message,
    this.title,
    this.color = AppColors.textSecondary,
    this.icon = Icons.info_outline_rounded,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? title;
  final Color color;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final neutral = color == AppColors.textSecondary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: neutral ? AppColors.surfaceRaised : AppColors.tint(color, 0.08),
        borderRadius: AppRadius.input,
        border: Border.all(color: neutral ? AppColors.border : AppColors.tint(color, 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const Gap(10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(
                    title!,
                    style: theme.labelLarge?.copyWith(
                      color: neutral ? AppColors.textPrimary : color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Gap(4),
                ],
                Text(
                  message,
                  style: theme.bodyMedium?.copyWith(
                    color: neutral ? AppColors.textSecondary : color,
                  ),
                ),
                if (actionLabel != null && onAction != null) ...[
                  const Gap(8),
                  GestureDetector(
                    onTap: onAction,
                    child: Text(
                      actionLabel!,
                      style: theme.labelLarge?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                        decorationColor: AppColors.textTertiary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Mise en page standard d'une feuille modale : titre, contenu défilant, pied (boutons).
///
/// [expand] : à utiliser avec `showAppSheet(expand: true)` (contenu long, défilement lié à la feuille).
class SheetLayout extends StatelessWidget {
  const SheetLayout({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.footer,
    this.trailing,
    this.expand = false,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final Widget? footer;
  final Widget? trailing;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      primary: expand,
      shrinkWrap: !expand,
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, AppSpacing.page, AppSpacing.lg),
      children: children,
    );
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(title: title, trailing: trailing),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.sm),
              child: Text(
                subtitle!,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
              ),
            ),
          if (expand) Expanded(child: list) else Flexible(child: list),
          if (footer != null)
            DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page,
                  AppSpacing.md,
                  AppSpacing.page,
                  AppSpacing.md,
                ),
                child: footer,
              ),
            ),
        ],
      ),
    );
  }
}

/// Petite étiquette grise au-dessus d'une valeur.
class FieldCaption extends StatelessWidget {
  const FieldCaption(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.textTertiary),
  );
}

/// Bouton-lien discret (texte secondaire + icône).
class InlineAction extends StatelessWidget {
  const InlineAction({super.key, required this.label, required this.onPressed, this.icon});

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      foregroundColor: AppColors.textSecondary,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      minimumSize: const Size(44, 40),
      tapTargetSize: MaterialTapTargetSize.padded,
    ),
    icon: Icon(icon ?? Icons.edit_outlined, size: 16),
    label: Text(label),
  );
}

/// « il y a 3 h », « hier », sinon « le 12 sept. 2026 ».
String relativeDate(DateTime? value) {
  if (value == null) return '—';
  final diff = DateTime.now().difference(value);
  if (!diff.isNegative && diff.inDays < 7) return Fmt.relative(value);
  return 'le ${Fmt.date(value)}';
}

/// Exécute [task] derrière un indicateur bloquant (génération de texte, préparation...).
/// Renvoie null en cas d'erreur (le message est déjà affiché).
Future<T?> runWithProgress<T>(
  BuildContext context,
  Future<T> Function() task, {
  String message = 'Rédaction en cours...',
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const Gap(16),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      ),
    ),
  );
  try {
    return await task();
  } catch (error) {
    showError(error);
    return null;
  } finally {
    navigator.pop();
  }
}

/// Copie un texte dans le presse-papiers et le confirme.
Future<void> copyText(String text, {String message = 'Copié dans le presse-papiers'}) async {
  await Clipboard.setData(ClipboardData(text: text));
  showToast(message, kind: ToastKind.success);
}

/// Ouvre un lien (site de candidature, messagerie...) dans l'application externe.
Future<void> openExternal(Uri uri) async {
  try {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) showToast('Impossible d\'ouvrir ce lien.', kind: ToastKind.error);
  } catch (_) {
    showToast('Impossible d\'ouvrir ce lien.', kind: ToastKind.error);
  }
}

/// Lien `mailto:` avec objet et message (encodage compatible avec les clients de messagerie).
Uri mailtoUri(String to, {String? subject, String? body}) {
  final query = [
    if (subject != null && subject.isNotEmpty) 'subject=${Uri.encodeComponent(subject)}',
    if (body != null && body.isNotEmpty) 'body=${Uri.encodeComponent(body)}',
  ].join('&');
  return Uri.parse('mailto:$to${query.isEmpty ? '' : '?$query'}');
}

/// Option sélectionnable (bouton radio en forme de carte).
class SelectableOption extends StatelessWidget {
  const SelectableOption({
    super.key,
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.badge,
    this.iconColor,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Color? iconColor;
  final bool selected;
  final String? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Material(
      color: selected ? AppColors.surfaceHigh : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.input,
        side: BorderSide(color: selected ? AppColors.textPrimary : AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: iconColor ?? AppColors.textSecondary),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
                          ),
                        ),
                        if (badge != null) ...[
                          const Gap(8),
                          Pill(badge!, color: AppColors.success, dense: true),
                        ],
                      ],
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
                      ),
                  ],
                ),
              ),
              const Gap(8),
              Icon(
                selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                size: 20,
                color: selected ? AppColors.textPrimary : AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
