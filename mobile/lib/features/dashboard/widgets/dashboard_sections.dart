import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/models/enums.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/realtime/realtime_service.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/ui.dart';
import '../../jobs/widgets/job_card.dart';
import '../data/dashboard_models.dart';
import '../data/dashboard_repository.dart';

/// Date du jour en toutes lettres : `Mercredi 30 septembre`.
String todayLabel([DateTime? now]) {
  final text = DateFormat('EEEE d MMMM', 'fr_FR').format(now ?? DateTime.now());
  return text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);
}

/// `Bonjour, Jane` + date du jour + avatar (vers le profil).
class DashboardGreeting extends ConsumerWidget {
  const DashboardGreeting({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context).textTheme;
    final email = ref.watch(currentUserProvider.select((user) => user?.email));
    final name = ref.watch(greetingNameProvider).value;
    final now = DateTime.now();
    final hello = now.hour >= 18 ? 'Bonsoir' : 'Bonjour';
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                todayLabel(now),
                style: theme.labelLarge?.copyWith(color: AppColors.textTertiary),
              ),
              const Gap(6),
              Text(
                name == null ? hello : '$hello, $name',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.displaySmall,
              ),
            ],
          ),
        ),
        const Gap(12),
        Semantics(
          button: true,
          label: 'Mon profil',
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => context.go(Routes.profile),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: AppAvatar(label: name ?? email, size: 44),
            ),
          ),
        ),
      ],
    );
  }
}

/// Grille d'indicateurs : 2 colonnes sur téléphone, 3 sur grand écran.
class StatsGrid extends ConsumerWidget {
  const StatsGrid({super.key, required this.onBestMatches, required this.onNewJobs});

  final VoidCallback onBestMatches;
  final VoidCallback onNewJobs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(dashboardOverviewProvider);
    final unread = ref.watch(unreadCountProvider);
    if (!overview.hasValue && overview.hasError) {
      return _InlineError(
        error: overview.error!,
        onRetry: () => ref.invalidate(dashboardOverviewProvider),
      );
    }
    final o = overview.value;
    String n(int? value) => o == null ? '—' : Fmt.number(value);

    final tiles = [
      StatTile(
        label: 'Offres compatibles',
        value: n(o?.matchingJobsTotal),
        icon: Icons.bolt_rounded,
        color: (o?.matchingJobsTotal ?? 0) > 0 ? AppColors.success : null,
        caption: 'Score ≥ ${o?.matchingThreshold ?? 70}',
        onTap: onBestMatches,
      ),
      StatTile(
        label: 'Nouvelles offres',
        value: n(o?.newJobsToday),
        icon: Icons.fiber_new_outlined,
        caption: o == null ? 'Aujourd\'hui' : 'Aujourd\'hui · ${Fmt.number(o.jobsFoundToday)} vues',
        onTap: onNewJobs,
      ),
      StatTile(
        label: 'Compatibles du jour',
        value: n(o?.matchingJobsToday),
        icon: Icons.trending_up_rounded,
        caption: o == null ? 'Aujourd\'hui' : '${Fmt.number(o.jobsAnalyzedToday)} analysées',
        onTap: onBestMatches,
      ),
      StatTile(
        label: 'Candidatures',
        value: n(o?.applicationsTotal),
        icon: Icons.send_outlined,
        caption: o == null ? null : _inProgressCaption(o),
        onTap: () => context.go(Routes.applications),
      ),
      StatTile(
        label: 'Réponses',
        value: n(o?.responsesTotal),
        icon: Icons.mark_email_read_outlined,
        caption: o == null ? null : '+${Fmt.number(o.responsesLast7Days)} en 7 jours',
        onTap: () => context.push(Routes.recruiterResponses),
      ),
      StatTile(
        label: 'Alertes non lues',
        value: o == null && unread == 0 ? '—' : Fmt.number(unread),
        icon: Icons.notifications_none_rounded,
        color: unread > 0 ? AppColors.warning : null,
        caption: 'Notifications',
        onTap: () => context.go(Routes.notifications),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 560 ? 3 : 2;
        final rows = <Widget>[];
        for (var i = 0; i < tiles.length; i += columns) {
          if (i > 0) rows.add(const Gap(12));
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var j = i; j < i + columns; j++) ...[
                    if (j > i) const Gap(12),
                    Expanded(child: j < tiles.length ? tiles[j] : const SizedBox.shrink()),
                  ],
                ],
              ),
            ),
          );
        }
        return Column(children: rows);
      },
    );
  }

  static String? _inProgressCaption(DashboardOverview o) {
    final active = o.applicationsByStatus.entries
        .where((e) => !e.key.isFinal && e.key != ApplicationStatus.offer)
        .fold<int>(0, (sum, e) => sum + e.value);
    if (o.applicationsTotal == 0) return 'Aucune pour l\'instant';
    return '$active en cours';
  }
}

/// Les 5 meilleures offres (score ≥ seuil).
class TopMatchesCard extends ConsumerWidget {
  const TopMatchesCard({super.key, required this.threshold});

  final int threshold;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final top = ref.watch(topMatchesProvider);
    final page = top.value;
    if (page == null) {
      if (top.hasError) {
        return _InlineError(error: top.error!, onRetry: () => ref.invalidate(topMatchesProvider));
      }
      return const AppCard(child: LoadingView(padding: EdgeInsets.symmetric(vertical: 36)));
    }
    if (page.items.isEmpty) {
      return AppCard(
        child: Column(
          children: [
            const Icon(Icons.travel_explore_rounded, color: AppColors.textSecondary, size: 28),
            const Gap(12),
            Text(
              'Aucune offre au-dessus de $threshold %',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const Gap(4),
            Text(
              'Complétez votre profil et vos préférences pour améliorer le matching.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Gap(12),
            TextButton(
              onPressed: () => context.go(Routes.profile),
              child: const Text('Compléter mon profil'),
            ),
          ],
        ),
      );
    }
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < page.items.length; i++) ...[
            if (i > 0) const Divider(indent: 72),
            JobCompactTile(
              job: page.items[i],
              onTap: () => context.push(Routes.job(page.items[i].id)),
            ),
          ],
        ],
      ),
    );
  }
}

/// Suivi des candidatures : taux de réponse, entretiens, offres et répartition par statut.
class PipelineCard extends ConsumerWidget {
  const PipelineCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context).textTheme;
    final stats = ref.watch(applicationStatsProvider);
    final s = stats.value;
    if (s == null) {
      if (stats.hasError) {
        return _InlineError(
          error: stats.error!,
          onRetry: () => ref.invalidate(applicationStatsProvider),
        );
      }
      return const AppCard(child: LoadingView(padding: EdgeInsets.symmetric(vertical: 36)));
    }
    final ordered = [
      for (final status in ApplicationStatus.values)
        if ((s.byStatus[status] ?? 0) > 0) MapEntry(status, s.byStatus[status]!),
    ];
    final average = s.averageResponseDays;

    return AppCard(
      onTap: () => context.go(Routes.applications),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _Metric(
                  value: s.submittedTotal == 0 ? '—' : '${(s.responseRate * 100).round()} %',
                  label: 'Taux de réponse',
                ),
              ),
              Expanded(
                child: _Metric(value: Fmt.number(s.interviews), label: 'Entretiens'),
              ),
              Expanded(
                child: _Metric(
                  value: Fmt.number(s.offers),
                  label: 'Offres reçues',
                  color: s.offers > 0 ? AppColors.success : null,
                ),
              ),
            ],
          ),
          const Gap(18),
          if (ordered.isEmpty)
            Text(
              'Aucune candidature pour l\'instant. Depuis une offre, touchez '
              '« Préparer ma candidature ».',
              style: theme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            )
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 8,
                child: Row(
                  children: [
                    for (var i = 0; i < ordered.length; i++) ...[
                      if (i > 0) const SizedBox(width: 2),
                      Expanded(
                        flex: ordered[i].value,
                        child: ColoredBox(color: ordered[i].key.color),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const Gap(14),
            Wrap(
              spacing: 14,
              runSpacing: 8,
              children: [
                for (final entry in ordered)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: entry.key.color, shape: BoxShape.circle),
                      ),
                      const Gap(6),
                      Text(
                        '${entry.key.label} ${entry.value}',
                        style: theme.labelMedium?.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
              ],
            ),
          ],
          if (average != null) ...[
            const Gap(14),
            Text(
              'Réponse en ${Fmt.number(average)} j en moyenne · '
              '${Fmt.number(s.submittedTotal)} envoyée${s.submittedTotal > 1 ? 's' : ''}',
              style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label, this.color});

  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: theme.headlineSmall?.copyWith(color: color ?? AppColors.textPrimary)),
        const Gap(2),
        Text(label, style: theme.labelSmall?.copyWith(color: AppColors.textTertiary)),
      ],
    );
  }
}

/// Tuile d'action rapide (icône + libellé).
class QuickActionTile extends StatelessWidget {
  const QuickActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.loading = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) => AppCard(
    onTap: loading ? null : onTap,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: loading
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(icon, size: 19, color: AppColors.textPrimary),
        ),
        const Gap(14),
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ],
    ),
  );
}

/// État des services (admin) : API, base de données, Redis, erreurs de collecte.
class ServicesCard extends ConsumerWidget {
  const ServicesCard({super.key});

  static String _serviceName(String key) => switch (key) {
    'api' => 'API',
    'postgres' => 'Base de données',
    'redis' => 'Redis (cache et tâches)',
    'worker' => 'Tâches de fond',
    'n8n' => 'n8n',
    _ => key,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context).textTheme;
    final overview = ref.watch(dashboardOverviewProvider);
    final o = overview.value;
    if (o == null) {
      if (overview.hasError) {
        return _InlineError(
          error: overview.error!,
          onRetry: () => ref.invalidate(dashboardOverviewProvider),
        );
      }
      return const AppCard(child: LoadingView(padding: EdgeInsets.symmetric(vertical: 24)));
    }
    Widget row(Color color, String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const Gap(12),
          Expanded(child: Text(label, style: theme.bodyMedium)),
          Text(value, style: theme.labelMedium?.copyWith(color: AppColors.textSecondary)),
        ],
      ),
    );
    return AppCard(
      onTap: () => context.push(Routes.adminSystem),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 10),
      child: Column(
        children: [
          for (final entry in o.services.entries)
            row(
              entry.value == 'ok' ? AppColors.success : AppColors.danger,
              _serviceName(entry.key),
              entry.value == 'ok' ? 'Opérationnel' : 'En erreur',
            ),
          row(
            o.scrapingErrors24h > 0 ? AppColors.warning : AppColors.success,
            'Erreurs de collecte (24 h)',
            Fmt.number(o.scrapingErrors24h),
          ),
        ],
      ),
    );
  }
}

/// Erreur compacte dans une section (le reste du tableau de bord reste utilisable).
class _InlineError extends StatelessWidget {
  const _InlineError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 6, 6, 6),
    child: Row(
      children: [
        const Icon(Icons.error_outline_rounded, size: 18, color: AppColors.danger),
        const Gap(10),
        Expanded(
          child: Text(ApiException.describe(error), style: Theme.of(context).textTheme.bodySmall),
        ),
        TextButton(onPressed: onRetry, child: const Text('Réessayer')),
      ],
    ),
  );
}
