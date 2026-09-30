import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/ui.dart';
import '../data/admin_labels.dart';

/// Petits composants partagés par les écrans d'administration.

/// Affiche une erreur (avec les messages propres à l'administration).
void showAdminError(Object error) => showToast(adminErrorMessage(error), kind: ToastKind.error);

/// Exécute une action et affiche le résultat. Renvoie null en cas d'erreur.
Future<T?> runAdmin<T>(Future<T> Function() action, {String? success}) async {
  try {
    final result = await action();
    if (success != null) showToast(success, kind: ToastKind.success);
    return result;
  } catch (error) {
    showAdminError(error);
    return null;
  }
}

/// Ouvre un lien externe (site, email, téléphone).
Future<void> openLink(String url) async {
  var uri = Uri.tryParse(url.trim());
  if (uri == null) return;
  if (!uri.hasScheme) uri = Uri.tryParse('https://${url.trim()}');
  if (uri == null) return;
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) showToast('Impossible d\'ouvrir le lien.', kind: ToastKind.error);
  } catch (_) {
    showToast('Impossible d\'ouvrir le lien.', kind: ToastKind.error);
  }
}

/// Copie un texte dans le presse-papiers.
Future<void> copyText(String text, {String message = 'Copié'}) async {
  await Clipboard.setData(ClipboardData(text: text));
  showToast(message, kind: ToastKind.success);
}

/// Pastille de couleur (état d'un service, d'une source).
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.color, this.size = 8});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      boxShadow: const [],
    ),
  );
}

/// JSON lisible (police à chasse fixe), en lecture seule, avec bouton « Copier ».
class JsonBlock extends StatelessWidget {
  const JsonBlock({super.key, required this.value, this.maxHeight = 360, this.emptyLabel});

  final Object? value;
  final double maxHeight;
  final String? emptyLabel;

  static String format(Object? value) {
    try {
      return const JsonEncoder.withIndent('  ').convert(value);
    } catch (_) {
      return value.toString();
    }
  }

  bool get _isEmpty =>
      value == null || (value is Map && (value as Map).isEmpty) || (value is List && (value as List).isEmpty);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    if (_isEmpty) {
      return Text(
        emptyLabel ?? 'Aucune donnée',
        style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
      );
    }
    final text = format(value);
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: AppRadius.input,
        border: Border.all(color: AppColors.border),
      ),
      child: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 12, 44, 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText(
                text,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.45,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: IconButton(
              tooltip: 'Copier',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.copy_rounded, size: 16, color: AppColors.textTertiary),
              onPressed: () => copyText(text, message: 'JSON copié'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Rangée de pastilles de filtre à choix unique, défilant horizontalement, avec « Tous ».
class ChipBar<T> extends StatelessWidget {
  const ChipBar({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
    this.allLabel = 'Tous',
    this.iconOf,
  });

  final List<T> values;
  final T? selected;
  final String Function(T value) labelOf;
  final ValueChanged<T?> onSelected;
  final String? allLabel;
  final IconData? Function(T value)? iconOf;

  @override
  Widget build(BuildContext context) {
    Widget chip({required String label, required bool active, required VoidCallback onTap, IconData? icon}) =>
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(label),
            avatar: icon == null
                ? null
                : Icon(icon, size: 16, color: active ? AppColors.onAccent : AppColors.textSecondary),
            showCheckmark: false,
            selected: active,
            labelStyle: TextStyle(
              color: active ? AppColors.onAccent : AppColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
            onSelected: (_) => onTap(),
          ),
        );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          if (allLabel != null)
            chip(label: allLabel!, active: selected == null, onTap: () => onSelected(null)),
          for (final value in values)
            chip(
              label: labelOf(value),
              icon: iconOf?.call(value),
              active: value == selected,
              onTap: () => onSelected(value == selected && allLabel != null ? null : value),
            ),
        ],
      ),
    );
  }
}

/// Champ de recherche avec délai de frappe (déclenche [onChanged] après une pause).
class SearchField extends StatefulWidget {
  const SearchField({
    super.key,
    required this.onChanged,
    this.hint = 'Rechercher',
    this.initialValue = '',
    this.delay = const Duration(milliseconds: 400),
  });

  final ValueChanged<String> onChanged;
  final String hint;
  final String initialValue;
  final Duration delay;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialValue);
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _changed(String value) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(widget.delay, () => widget.onChanged(value.trim()));
  }

  void _clear() {
    _controller.clear();
    _debounce?.cancel();
    setState(() {});
    widget.onChanged('');
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    onChanged: _changed,
    onSubmitted: (value) {
      _debounce?.cancel();
      widget.onChanged(value.trim());
    },
    textInputAction: TextInputAction.search,
    decoration: InputDecoration(
      hintText: widget.hint,
      prefixIcon: const Icon(Icons.search_rounded, size: 20),
      suffixIcon: _controller.text.isEmpty
          ? null
          : IconButton(
              tooltip: 'Effacer',
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: _clear,
            ),
    ),
  );
}

/// Bouton « Filtres » de la barre d'application, avec un point quand un filtre est actif.
class FilterAction extends StatelessWidget {
  const FilterAction({super.key, required this.active, required this.onPressed});

  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Filtres',
    onPressed: onPressed,
    icon: Badge(
      isLabelVisible: active,
      smallSize: 8,
      backgroundColor: AppColors.textPrimary,
      child: const Icon(Icons.tune_rounded),
    ),
  );
}

/// Grille qui s'adapte à la largeur (2 colonnes sur téléphone, plus sur ordinateur).
class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({
    super.key,
    required this.children,
    this.minItemWidth = 150,
    this.spacing = 10,
    this.maxColumns = 4,
  });

  final List<Widget> children;
  final double minItemWidth;
  final double spacing;
  final int maxColumns;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final columns = ((width + spacing) / (minItemWidth + spacing)).floor().clamp(1, maxColumns);
      final itemWidth = (width - spacing * (columns - 1)) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [for (final child in children) SizedBox(width: itemWidth, child: child)],
      );
    },
  );
}

/// Encadré d'information (aide, avertissement, erreur).
class NoteBox extends StatelessWidget {
  const NoteBox({super.key, required this.message, this.color, this.icon, this.title});

  final String message;
  final String? title;

  /// null = neutre.
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final fg = color ?? AppColors.textSecondary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color == null ? AppColors.surfaceHigh : AppColors.tint(fg, 0.08),
        borderRadius: AppRadius.input,
        border: Border.all(color: color == null ? AppColors.border : AppColors.tint(fg, 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? Icons.info_outline_rounded, size: 18, color: fg),
          const Gap(10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(title!, style: theme.labelLarge?.copyWith(color: fg, fontWeight: FontWeight.w600)),
                  const Gap(2),
                ],
                Text(
                  message,
                  style: theme.bodySmall?.copyWith(
                    color: color == null ? AppColors.textSecondary : fg,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Chiffre + libellé compact (`34 créées`).
class MetricText extends StatelessWidget {
  const MetricText({super.key, required this.value, required this.label, this.color});

  final int value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$value',
            style: theme.labelLarge?.copyWith(
              color: color ?? AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(
            text: ' $label',
            style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// Compteur affiché en tête de liste (`42 sources`).
class ListCount extends StatelessWidget {
  const ListCount({super.key, required this.count, required this.singular, required this.plural});

  final int? count;
  final String singular;
  final String plural;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 10),
    child: Text(
      count == null ? ' ' : '$count ${count! > 1 ? plural : singular}',
      style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.textTertiary),
    ),
  );
}

/// Feuille « formulaire » : titre, champs défilants, bouton d'enregistrement en bas.
///
/// À ouvrir avec `showAppSheet(context, expand: true, builder: ...)` pour les longs formulaires.
class FormSheet extends StatelessWidget {
  const FormSheet({
    super.key,
    required this.title,
    required this.formKey,
    required this.children,
    required this.onSubmit,
    this.submitLabel = 'Enregistrer',
    this.saving = false,
    this.expand = true,
    this.onDelete,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final GlobalKey<FormState> formKey;
  final List<Widget> children;
  final VoidCallback onSubmit;
  final String submitLabel;
  final bool saving;

  /// true : dans une feuille extensible (`showAppSheet(expand: true)`).
  final bool expand;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final body = Form(
      key: formKey,
      child: SingleChildScrollView(
        primary: expand,
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, AppSpacing.page, AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (subtitle != null) ...[
              Text(subtitle!, style: theme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
              const Gap(18),
            ],
            ...children,
          ],
        ),
      ),
    );
    return Column(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(
          title: title,
          trailing: IconButton(
            tooltip: 'Fermer',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        if (expand) Expanded(child: body) else Flexible(child: body),
        DecoratedBox(
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.page, 12, AppSpacing.page, 12),
              child: Row(
                children: [
                  if (onDelete != null) ...[
                    IconButton.outlined(
                      tooltip: 'Supprimer',
                      onPressed: saving ? null : onDelete,
                      style: IconButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        side: const BorderSide(color: AppColors.borderStrong),
                        minimumSize: const Size(48, 48),
                      ),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                    const Gap(10),
                  ],
                  Expanded(
                    child: PrimaryButton(label: submitLabel, loading: saving, onPressed: onSubmit),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Feuille « détail » : en-tête, contenu défilant, actions en bas (facultatives).
class DetailSheet extends StatelessWidget {
  const DetailSheet({
    super.key,
    required this.title,
    required this.children,
    this.actions = const [],
    this.headerTrailing,
  });

  final String title;
  final List<Widget> children;
  final List<Widget> actions;
  final Widget? headerTrailing;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SheetHeader(
        title: title,
        trailing:
            headerTrailing ??
            IconButton(
              tooltip: 'Fermer',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
      ),
      Expanded(
        child: ListView(
          primary: true,
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, AppSpacing.page, AppSpacing.xl),
          children: children,
        ),
      ),
      if (actions.isNotEmpty)
        DecoratedBox(
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.page, 12, AppSpacing.page, 12),
              child: Row(
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const Gap(10),
                    Expanded(child: actions[i]),
                  ],
                ],
              ),
            ),
          ),
        ),
    ],
  );
}

/// Titre de bloc dans une feuille (plus discret que [SectionHeader]).
class SheetSection extends StatelessWidget {
  const SheetSection(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 6),
    child: Text(
      title.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: AppColors.textTertiary,
        letterSpacing: 1.1,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// Carte d'erreur compacte (garde le reste de la page utilisable).
class InlineError extends StatelessWidget {
  const InlineError({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Row(
      children: [
        const Icon(Icons.error_outline_rounded, size: 20, color: AppColors.danger),
        const Gap(12),
        Expanded(
          child: Text(
            adminErrorMessage(error),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
        ),
        if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Réessayer')),
      ],
    ),
  );
}

/// Découpe une saisie « a, b, c » en liste.
List<String> splitList(String text) =>
    text.split(RegExp(r'[,\n]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

/// Validateur d'email facultatif.
String? optionalEmail(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim()) ? null : 'Email invalide';
}

/// Validateur de téléphone facultatif (même règle que le serveur).
String? optionalPhone(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  return RegExp(r'^\+?[0-9 ().-]{6,30}$').hasMatch(value.trim()) ? null : 'Numéro invalide';
}
