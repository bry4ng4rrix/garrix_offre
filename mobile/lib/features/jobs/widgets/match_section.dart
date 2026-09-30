import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/ui.dart';
import '../data/job_models.dart';
import '../job_labels.dart';
import '../jobs_providers.dart';

/// Carte « Matching » du détail d'une offre : score, détail par critère (poids et
/// sous-score), compétences correspondantes / manquantes et explications.
class MatchSection extends ConsumerStatefulWidget {
  const MatchSection({super.key, required this.job});

  final Job job;

  @override
  ConsumerState<MatchSection> createState() => _MatchSectionState();
}

class _MatchSectionState extends ConsumerState<MatchSection> {
  bool _recalculating = false;

  Future<void> _recalculate() async {
    setState(() => _recalculating = true);
    await runAction(
      () => ref.refresh(jobMatchProvider(widget.job.id).future),
      success: 'Score recalculé',
    );
    if (mounted) setState(() => _recalculating = false);
  }

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final theme = Theme.of(context).textTheme;
    final detail = ref.watch(jobMatchProvider(job.id));
    // Le détail recalcule le score : on le reporte sur l'offre affichée (et les listes).
    ref.listen(jobMatchProvider(job.id), (_, next) {
      final result = next.value;
      if (result != null && !next.isLoading) {
        ref.read(jobDetailProvider(job.id).notifier).applyMatch(result);
      }
    });

    final matching = job.matching;
    final score = matching?.score;
    final busy = _recalculating || (detail.isLoading && matching == null);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ScoreRing(score: score, size: 56, strokeWidth: 4.5),
              const Gap(16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      busy && score == null ? 'Calcul en cours…' : JobLabels.verdict(score),
                      style: theme.titleMedium?.copyWith(
                        color: score == null ? AppColors.textPrimary : AppColors.score(score),
                      ),
                    ),
                    const Gap(2),
                    Text(
                      matching?.computedAt == null
                          ? 'Compare l\'offre à votre profil'
                          : 'Calculé ${Fmt.relative(matching!.computedAt)}',
                      style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),
              const Gap(8),
              busy
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : TextButton.icon(
                      onPressed: _recalculate,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Recalculer'),
                    ),
            ],
          ),
          _Breakdown(
            value: detail,
            onRetry: () => ref.invalidate(jobMatchProvider(job.id)),
          ),
          if (matching != null && matching.matchedSkills.isNotEmpty) ...[
            const Gap(20),
            const _Label('Compétences correspondantes'),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final skill in matching.matchedSkills)
                  Pill(skill, color: AppColors.success, icon: Icons.check_rounded, dense: true),
              ],
            ),
          ],
          if (matching != null && matching.missingSkills.isNotEmpty) ...[
            const Gap(16),
            const _Label('Compétences manquantes'),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final skill in matching.missingSkills)
                  Pill(skill, color: AppColors.danger, icon: Icons.close_rounded, dense: true),
              ],
            ),
          ],
          if (matching != null && matching.reasons.isNotEmpty) ...[
            const Gap(20),
            const _Label('Pourquoi ce score'),
            for (final reason in matching.reasons)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 8, right: 10),
                      child: SizedBox.square(
                        dimension: 4,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppColors.textTertiary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        reason,
                        style: theme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.textTertiary),
    ),
  );
}

/// Sous-scores par critère (barres fines), triés par poids.
class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.value, required this.onRetry});

  final AsyncValue<MatchResult> value;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final result = value.value;
    if (result == null) {
      if (value.hasError) {
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Détail du score indisponible.',
                  style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
                ),
              ),
              TextButton(onPressed: onRetry, child: const Text('Réessayer')),
            ],
          ),
        );
      }
      return const Padding(
        padding: EdgeInsets.only(top: 20),
        child: ThinProgress(value: 0, height: 2),
      );
    }
    final totalWeight = result.criteria
        .where((c) => c.isEvaluated)
        .fold<int>(0, (sum, c) => sum + c.weight);
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        children: [
          for (final criterion in result.criteria)
            if (criterion.weight > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _CriterionRow(criterion: criterion, totalWeight: totalWeight),
              ),
        ],
      ),
    );
  }
}

class _CriterionRow extends StatelessWidget {
  const _CriterionRow({required this.criterion, required this.totalWeight});

  final MatchCriterion criterion;
  final int totalWeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final score = criterion.score;
    final percent = score == null ? null : (score * 100).round();
    final share = criterion.isEvaluated && totalWeight > 0
        ? (criterion.weight * 100 / totalWeight).round()
        : null;
    final (icon, iconColor) = switch (criterion.matched) {
      true => (Icons.check_circle_rounded, AppColors.success),
      false => (Icons.cancel_rounded, AppColors.danger),
      null => (Icons.circle_outlined, AppColors.textDisabled),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: iconColor),
            const Gap(8),
            Expanded(
              child: Text(
                JobLabels.criterion(criterion.key),
                style: theme.bodyMedium?.copyWith(
                  color: score == null ? AppColors.textTertiary : AppColors.textPrimary,
                ),
              ),
            ),
            if (share != null)
              Text(
                'poids $share %  ',
                style: theme.labelSmall?.copyWith(color: AppColors.textTertiary),
              ),
            Text(
              percent == null ? 'Non évalué' : '$percent %',
              style: theme.labelMedium?.copyWith(
                color: percent == null ? AppColors.textTertiary : AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const Gap(6),
        ThinProgress(
          value: score ?? 0,
          color: percent == null ? AppColors.textDisabled : AppColors.score(percent),
        ),
      ],
    );
  }
}
