import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/ui.dart';
import '../data/job_models.dart';
import '../job_labels.dart';

/// `Entreprise · Lieu` (ou ce qui est connu).
String jobSubtitle(Job job) {
  final parts = <String>[
    ?job.company.name,
    ?job.location.label,
  ];
  if (parts.isEmpty) return job.location.workModeLabel ?? 'Entreprise non indiquée';
  return parts.join(' · ');
}

/// Carte d'une offre dans la liste : titre, entreprise, lieu, contrat, salaire, score,
/// date, source et indicateurs (non vue, sauvegardée, candidature).
class JobCard extends ConsumerWidget {
  const JobCard({super.key, required this.job, this.onTap, this.onToggleSave, this.onMore});

  final Job job;
  final VoidCallback? onTap;
  final VoidCallback? onToggleSave;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context).textTheme;
    final labels = ref.watch(jobLabelsProvider);
    final status = job.status;
    final contract = labels.contract(job.contract.type);
    final workMode = job.location.workModeLabel;
    final pills = <Widget>[
      if (status.hasApplication || status.applicationStatus != ApplicationStatus.notApplied)
        Pill(
          status.applicationStatus.label,
          color: status.applicationStatus.color,
          icon: status.applicationStatus.icon,
          dense: true,
        ),
      if (status.isIgnored) const Pill('Ignorée', icon: Icons.visibility_off_outlined, dense: true),
      if (status.isExpired) const Pill('Expirée', color: AppColors.warning, dense: true),
      if (contract != null) Pill(contract, dense: true),
      if (workMode != null) Pill(workMode, icon: Icons.home_work_outlined, dense: true),
      if (job.salary.isKnown)
        Pill(
          Fmt.salary(
            min: job.salary.min,
            max: job.salary.max,
            currency: job.salary.currency,
            period: job.salary.period,
            raw: job.salary.raw,
          ),
          icon: Icons.payments_outlined,
          dense: true,
        ),
    ];
    final meta = [Fmt.relative(job.displayDate), ?job.source.name].join(' · ');

    return AppCard(
      onTap: onTap,
      onLongPress: onMore,
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.xs, AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            if (status.isNew)
                              const WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: Padding(
                                  padding: EdgeInsets.only(right: 8),
                                  child: _UnseenDot(),
                                ),
                              ),
                            TextSpan(text: job.title),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.titleMedium,
                      ),
                      const Gap(4),
                      Text(
                        jobSubtitle(job),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                const Gap(12),
                ScoreRing(score: job.score, size: 46),
              ],
            ),
          ),
          if (pills.isNotEmpty) ...[
            const Gap(12),
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: Wrap(spacing: 6, runSpacing: 6, children: pills),
            ),
          ],
          const Gap(4),
          Row(
            children: [
              Icon(
                job.source.category?.icon ?? Icons.public_rounded,
                size: 15,
                color: AppColors.textTertiary,
              ),
              const Gap(6),
              Expanded(
                child: Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
                ),
              ),
              if (onToggleSave != null)
                _SmallIconButton(
                  tooltip: status.isSaved ? 'Retirer des sauvegardes' : 'Sauvegarder',
                  icon: status.isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                  color: status.isSaved ? AppColors.textPrimary : AppColors.textTertiary,
                  onPressed: onToggleSave!,
                ),
              if (onMore != null)
                _SmallIconButton(
                  tooltip: 'Plus d\'actions',
                  icon: Icons.more_horiz_rounded,
                  color: AppColors.textTertiary,
                  onPressed: onMore!,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UnseenDot extends StatelessWidget {
  const _UnseenDot();

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Non vue',
    child: Container(
      width: 7,
      height: 7,
      decoration: const BoxDecoration(color: AppColors.info, shape: BoxShape.circle),
    ),
  );
}

class _SmallIconButton extends StatelessWidget {
  const _SmallIconButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(icon, size: 20, color: color),
    style: IconButton.styleFrom(
      minimumSize: const Size(44, 44),
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
  );
}

/// Ligne compacte d'une offre (tableau de bord) : score, titre, entreprise.
class JobCompactTile extends StatelessWidget {
  const JobCompactTile({super.key, required this.job, this.onTap});

  final Job job;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 14),
        child: Row(
          children: [
            ScoreRing(score: job.score, size: 42),
            const Gap(14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    job.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.titleSmall,
                  ),
                  const Gap(2),
                  Text(
                    [jobSubtitle(job), if (job.displayDate != null) Fmt.relative(job.displayDate)]
                        .join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
                  ),
                ],
              ),
            ),
            const Gap(8),
            if (job.status.isSaved) ...[
              const Icon(Icons.bookmark_rounded, size: 16, color: AppColors.textSecondary),
              const Gap(4),
            ],
            const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// Actions rapides proposées sur une offre (appui long ou menu « … »).
enum JobQuickAction { open, toggleSave, toggleIgnore, toggleSeen, openListing }

/// Feuille d'actions rapides d'une offre. Renvoie l'action choisie.
Future<JobQuickAction?> showJobActionsSheet(BuildContext context, Job job) {
  final status = job.status;
  return showAppSheet<JobQuickAction>(
    context,
    builder: (context) {
      Widget tile(JobQuickAction action, IconData icon, String label, {bool destructive = false}) =>
          ListTile(
            leading: Icon(icon, color: destructive ? AppColors.danger : AppColors.textSecondary),
            title: Text(
              label,
              style: destructive ? const TextStyle(color: AppColors.danger) : null,
            ),
            minTileHeight: 52,
            onTap: () => Navigator.of(context).pop(action),
          );
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    job.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Gap(2),
                  Text(
                    jobSubtitle(job),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Divider(),
            const Gap(4),
            tile(JobQuickAction.open, Icons.open_in_full_rounded, 'Ouvrir l\'offre'),
            tile(
              JobQuickAction.toggleSave,
              status.isSaved ? Icons.bookmark_remove_outlined : Icons.bookmark_add_outlined,
              status.isSaved ? 'Retirer des sauvegardes' : 'Sauvegarder',
            ),
            tile(
              JobQuickAction.toggleSeen,
              status.isNew ? Icons.visibility_outlined : Icons.mark_email_unread_outlined,
              status.isNew ? 'Marquer comme vue' : 'Marquer comme non vue',
            ),
            if (job.listingUrl != null)
              tile(JobQuickAction.openListing, Icons.open_in_new_rounded, 'Voir l\'annonce'),
            tile(
              JobQuickAction.toggleIgnore,
              status.isIgnored ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              status.isIgnored ? 'Ne plus ignorer' : 'Ignorer cette offre',
              destructive: !status.isIgnored,
            ),
            const Gap(8),
          ],
        ),
      );
    },
  );
}
