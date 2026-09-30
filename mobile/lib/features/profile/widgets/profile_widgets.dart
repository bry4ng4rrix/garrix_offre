import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/enums.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/ui.dart';
import '../data/profile_models.dart';
import '../data/profile_providers.dart';
import '../data/profile_repository.dart';

/// Petits composants partagés par les écrans du profil.

/// Photo de profil (ou initiales), rechargée après chaque changement de photo.
class ProfileAvatar extends ConsumerWidget {
  const ProfileAvatar({super.key, required this.profile, this.size = 72, this.fallbackLabel});

  final Profile profile;
  final double size;

  /// Texte utilisé pour les initiales si le profil n'a pas de nom (ex. email du compte).
  final String? fallbackLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(apiClientProvider);
    final version = ref.watch(photoVersionProvider);
    final url = profile.hasPhoto
        ? api.url('/profile/photo?v=${profile.photoCacheKey}-$version')
        : null;
    return AppAvatar(
      label: profile.displayName ?? profile.email ?? fallbackLabel,
      imageUrl: url,
      headers: api.authHeaders,
      size: size,
    );
  }
}

/// Niveau de maîtrise en 4 barres croissantes (débutant → expert).
class LevelMeter extends StatelessWidget {
  const LevelMeter({super.key, required this.level, this.showLabel = true, this.dimmed = false});

  final SkillLevel level;
  final bool showLabel;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final active = dimmed ? AppColors.textTertiary : AppColors.textPrimary;
    return Semantics(
      label: 'Niveau ${level.label}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 1; i <= SkillLevel.values.length; i++) ...[
            if (i > 1) const Gap(2),
            Container(
              width: 4,
              height: 4.0 + i * 3,
              decoration: BoxDecoration(
                color: i <= level.rank ? active : AppColors.surfaceHighest,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
          if (showLabel) ...[
            const Gap(8),
            Text(
              level.label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: dimmed ? AppColors.textTertiary : AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Pastille de priorité (rien pour la priorité moyenne si [hideMedium]).
class PriorityPill extends StatelessWidget {
  const PriorityPill({super.key, required this.priority, this.hideMedium = true});

  final Priority priority;
  final bool hideMedium;

  @override
  Widget build(BuildContext context) => switch (priority) {
    Priority.high => const Pill(
      'Priorité haute',
      icon: Icons.keyboard_double_arrow_up_rounded,
      color: AppColors.warning,
      dense: true,
    ),
    Priority.low => const Pill(
      'Priorité basse',
      icon: Icons.keyboard_double_arrow_down_rounded,
      dense: true,
      filled: false,
    ),
    Priority.medium =>
      hideMedium ? const SizedBox.shrink() : const Pill('Priorité moyenne', dense: true),
  };
}

/// Choix de la priorité (Basse / Moyenne / Haute) sur toute la largeur.
class PrioritySelector extends StatelessWidget {
  const PrioritySelector({super.key, required this.value, required this.onChanged});

  final Priority value;
  final ValueChanged<Priority> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: SegmentedButton<Priority>(
      showSelectedIcon: false,
      segments: [
        for (final priority in Priority.values)
          ButtonSegment(value: priority, label: Text(priority.label)),
      ],
      selected: {value},
      onSelectionChanged: (selection) => onChanged(selection.first),
    ),
  );
}

/// Choix du niveau de maîtrise, avec la jauge sous chaque libellé.
class LevelSelector extends StatelessWidget {
  const LevelSelector({super.key, required this.value, required this.onChanged});

  final SkillLevel value;
  final ValueChanged<SkillLevel> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Row(
      children: [
        for (final level in SkillLevel.values) ...[
          if (level.index > 0) const Gap(8),
          Expanded(
            child: Material(
              color: level == value ? AppColors.surfaceHighest : AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: AppRadius.input,
                side: BorderSide(
                  color: level == value ? AppColors.textPrimary : AppColors.border,
                ),
              ),
              child: InkWell(
                borderRadius: AppRadius.input,
                onTap: () => onChanged(level),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                  child: Column(
                    children: [
                      LevelMeter(level: level, showLabel: false, dimmed: level != value),
                      const Gap(8),
                      Text(
                        level.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.labelSmall?.copyWith(
                          color: level == value ? AppColors.textPrimary : AppColors.textSecondary,
                          fontWeight: level == value ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Message d'erreur affiché dans une feuille ou un formulaire.
class InlineError extends StatelessWidget {
  const InlineError({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.tint(AppColors.danger, 0.08),
      borderRadius: AppRadius.input,
      border: Border.all(color: AppColors.tint(AppColors.danger, 0.3)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline_rounded, size: 18, color: AppColors.danger),
        const Gap(10),
        Expanded(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.danger),
          ),
        ),
      ],
    ),
  );
}

/// Texte d'aide discret en tête de page.
class IntroText extends StatelessWidget {
  const IntroText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.xs, bottom: AppSpacing.sm),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
    ),
  );
}

/// Structure d'une feuille de formulaire : titre, contenu défilant, actions en bas.
class FormSheet extends StatelessWidget {
  const FormSheet({
    super.key,
    required this.title,
    required this.children,
    required this.actions,
    this.trailing,
  });

  final String title;
  final List<Widget> children;
  final List<Widget> actions;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(title: title, trailing: trailing),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, AppSpacing.page, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.lg, AppSpacing.page, AppSpacing.lg),
          child: Row(
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const Gap(10),
                Expanded(child: actions[i]),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

/// Ligne d'une liste dans une carte : contenu + interrupteur, cliquable.
class ToggleListRow extends StatelessWidget {
  const ToggleListRow({
    super.key,
    required this.title,
    required this.enabled,
    required this.onToggle,
    required this.onTap,
    this.details = const [],
  });

  final String title;
  final bool enabled;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTap;

  /// Ligne de détails sous le titre (niveau, pastilles...).
  final List<Widget> details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 12, AppSpacing.sm, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: enabled ? AppColors.textPrimary : AppColors.textTertiary,
                    ),
                  ),
                  if (details.isNotEmpty) ...[
                    const Gap(6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: details,
                    ),
                  ],
                ],
              ),
            ),
            const Gap(8),
            Tooltip(
              message: enabled ? 'Désactiver' : 'Activer',
              child: Switch(value: enabled, onChanged: onToggle),
            ),
          ],
        ),
      ),
    );
  }
}

/// Texte secondaire court dans une ligne de détails.
class DetailText extends StatelessWidget {
  const DetailText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.textTertiary),
  );
}

/// Demande confirmation avant de quitter un formulaire modifié.
Future<bool> confirmDiscard(BuildContext context) => confirmDialog(
  context,
  title: 'Quitter sans enregistrer ?',
  message: 'Vos modifications seront perdues.',
  confirmLabel: 'Quitter',
  destructive: true,
);

/// Lance le recalcul de tous les scores (`POST /matching/recalculate`) et affiche le résultat.
/// Prend le dépôt (et non un `ref`) : utilisable depuis l'action d'un message, page fermée.
Future<void> recalculateScores(ProfileRepository repository) async {
  final result = await runAction(repository.recalculateScores);
  if (result == null) return;
  showToast(
    result.queued
        ? 'Recalcul lancé : vos scores seront à jour dans quelques instants.'
        : 'Scores recalculés (${result.jobsMatched ?? 0} offres).',
    kind: ToastKind.success,
  );
}

/// Message de succès proposant de recalculer les scores.
void showSavedWithRecalculate(String message, ProfileRepository repository) => showToast(
  message,
  kind: ToastKind.success,
  action: SnackBarAction(label: 'Recalculer', onPressed: () => recalculateScores(repository)),
);

/// Élément choisi (compétence ou technologie) avec un bouton « Changer » optionnel.
class ChosenItemCard extends StatelessWidget {
  const ChosenItemCard({super.key, required this.name, this.subtitle, this.onChange});

  final String name;
  final String? subtitle;
  final VoidCallback? onChange;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 12, AppSpacing.sm, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: theme.titleMedium),
                if (subtitle != null)
                  Text(subtitle!, style: theme.bodySmall?.copyWith(color: AppColors.textTertiary)),
              ],
            ),
          ),
          if (onChange != null) TextButton(onPressed: onChange, child: const Text('Changer')),
        ],
      ),
    );
  }
}
