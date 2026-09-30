import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/enums.dart';
import '../../core/realtime/realtime_service.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/ui.dart';
import 'data/admin_providers.dart';
import 'data/admin_repository.dart';
import 'data/monitoring_models.dart';
import 'widgets/admin_ui.dart';
import 'widgets/run_widgets.dart';
import 'widgets/system_widgets.dart';

/// État détaillé du système, statistiques des collectes et tâches de maintenance.
class SystemPage extends ConsumerStatefulWidget {
  const SystemPage({super.key});

  @override
  ConsumerState<SystemPage> createState() => _SystemPageState();
}

class _SystemPageState extends ConsumerState<SystemPage> {
  bool _expiring = false;
  bool _recalculating = false;
  bool _waitingMatching = false;

  Future<void> _refresh() async {
    ref.invalidate(systemStatusProvider);
    ref.invalidate(scrapingOverviewProvider);
    await Future.wait([
      ref.read(systemStatusProvider.future).then((_) {}, onError: (_) {}),
      ref.read(scrapingOverviewProvider.future).then((_) {}, onError: (_) {}),
    ]);
  }

  Future<void> _expire() async {
    final ok = await confirmDialog(
      context,
      title: 'Expirer les anciennes offres ?',
      message:
          'Les offres échues ou non revues depuis longtemps passent en « Expirée » ; celles '
          'expirées depuis longtemps sont archivées. Les collectes bloquées sont marquées en échec.',
      confirmLabel: 'Lancer',
    );
    if (!ok || !mounted) return;
    setState(() => _expiring = true);
    final result = await runAdmin(() => ref.read(adminRepositoryProvider).expireJobs());
    if (!mounted) return;
    setState(() => _expiring = false);
    if (result == null) return;
    ref.invalidate(systemStatusProvider);
    final parts = [
      '${result.expired} offre${result.expired > 1 ? 's' : ''} expirée${result.expired > 1 ? 's' : ''}',
      '${result.archived} archivée${result.archived > 1 ? 's' : ''}',
      if (result.staleRunsFailed > 0)
        '${result.staleRunsFailed} collecte${result.staleRunsFailed > 1 ? 's' : ''} bloquée${result.staleRunsFailed > 1 ? 's' : ''} clôturée${result.staleRunsFailed > 1 ? 's' : ''}',
    ];
    showToast('Maintenance terminée : ${parts.join(', ')}.', kind: ToastKind.success);
  }

  Future<void> _recalculate() async {
    setState(() => _recalculating = true);
    final result = await runAdmin(() => ref.read(adminRepositoryProvider).recalculateMatching());
    if (!mounted) return;
    setState(() {
      _recalculating = false;
      _waitingMatching = result?.isQueued ?? false;
    });
    if (result == null) return;
    if (result.isQueued) {
      showToast('Recalcul lancé en arrière-plan.', kind: ToastKind.success);
    } else {
      final n = result.jobsMatched ?? 0;
      showToast('Scores recalculés pour $n offre${n > 1 ? 's' : ''}.', kind: ToastKind.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(realtimeEventsProvider, (_, next) {
      final event = next.value;
      if (event == null) return;
      switch (event.type) {
        case 'monitoring':
          ref.invalidate(systemStatusProvider);
        case 'scraping_run' || 'scraping_error':
          ref.invalidate(scrapingOverviewProvider);
        case 'matching_recalculated' when _waitingMatching:
          setState(() => _waitingMatching = false);
          showToast('Recalcul du matching terminé.', kind: ToastKind.success);
      }
    });

    final system = ref.watch(systemStatusProvider);
    final scraping = ref.watch(scrapingOverviewProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Système & maintenance'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refresh,
          ),
          const Gap(8),
        ],
      ),
      body: PageListView(
        onRefresh: _refresh,
        children: [
          const SectionHeader('Services'),
          if (system.hasValue)
            _SystemDetails(status: system.value!)
          else if (system.hasError)
            InlineError(error: system.error!, onRetry: () => ref.invalidate(systemStatusProvider))
          else
            const LoadingView(padding: EdgeInsets.symmetric(vertical: 40)),
          const SectionHeader('Maintenance'),
          MenuGroup(
            children: [
              MenuTile(
                icon: Icons.auto_delete_outlined,
                title: 'Expirer / archiver les anciennes offres',
                subtitle: 'Normalement déclenché chaque jour par n8n.',
                onTap: _expiring ? null : _expire,
                trailing: _expiring ? const _Spinner() : null,
              ),
              MenuTile(
                icon: Icons.sync_rounded,
                title: 'Recalculer le matching',
                subtitle: _waitingMatching
                    ? 'Recalcul en cours en arrière-plan...'
                    : 'Recalcule vos scores de compatibilité sur toutes les offres.',
                onTap: _recalculating ? null : _recalculate,
                trailing: (_recalculating || _waitingMatching) ? const _Spinner() : null,
              ),
            ],
          ),
          const SectionHeader('Collectes · 7 derniers jours'),
          if (scraping.hasValue)
            _ScrapingDetails(overview: scraping.value!)
          else if (scraping.hasError)
            InlineError(
              error: scraping.error!,
              onRetry: () => ref.invalidate(scrapingOverviewProvider),
            )
          else
            const LoadingView(padding: EdgeInsets.symmetric(vertical: 40)),
        ],
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) =>
      const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2));
}

class _SystemDetails extends StatelessWidget {
  const _SystemDetails({required this.status});

  final SystemStatus status;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SystemSummaryCard(status: status),
      const Gap(10),
      ServicesGrid(services: status.services),
      const Gap(10),
      SystemMetricsGrid(status: status, onUsersTap: () => context.push(Routes.adminUsers)),
      const SectionHeader('Offres par statut'),
      JobsByStatusRow(counts: status.jobsByStatus),
      const SectionHeader('Configuration'),
      SystemConfigCard(status: status),
    ],
  );
}

class _ScrapingDetails extends StatefulWidget {
  const _ScrapingDetails({required this.overview});

  final ScrapingOverview overview;

  @override
  State<_ScrapingDetails> createState() => _ScrapingDetailsState();
}

class _ScrapingDetailsState extends State<_ScrapingDetails> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final overview = widget.overview;
    // Sources en erreur d'abord, puis les plus actives.
    final sources = [...overview.sources]
      ..sort((a, b) {
        if (a.hasError != b.hasError) return a.hasError ? -1 : 1;
        return b.runs7d.compareTo(a.runs7d);
      });
    final tracked = sources.where((s) => s.isTracked || s.hasError).toList();
    final others = sources.length - tracked.length;
    final visible = _showAll ? sources : tracked;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (overview.runsByStatus7d.isEmpty)
          Text(
            'Aucune collecte sur les 7 derniers jours.',
            style: theme.bodyMedium?.copyWith(color: AppColors.textTertiary),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Pill('${overview.runs7d} au total', filled: false),
              for (final entry in overview.runsByStatus7d.entries)
                Pill(
                  '${ScrapingRunStatus.fromApi(entry.key)?.label ?? entry.key} · ${entry.value}',
                  color: ScrapingRunStatus.fromApi(entry.key)?.color,
                ),
            ],
          ),
        SectionHeader(
          'Sources suivies',
          action: 'Toutes les sources',
          onAction: () => context.push(Routes.adminSources),
        ),
        if (visible.isEmpty)
          Text(
            'Aucune source collectée automatiquement.',
            style: theme.bodyMedium?.copyWith(color: AppColors.textTertiary),
          )
        else
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < visible.length; i++) ...[
                  if (i > 0) const Divider(),
                  _SourceStatsTile(stats: visible[i]),
                ],
              ],
            ),
          ),
        if (others > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _showAll = !_showAll),
              child: Text(
                _showAll ? 'Masquer les sources inactives' : 'Afficher les $others autres sources',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ),
        SectionHeader(
          'Collectes récentes',
          action: 'Tout voir',
          onAction: () => context.push(Routes.adminRuns),
        ),
        if (overview.recentRuns.isEmpty)
          Text(
            'Aucune collecte récente.',
            style: theme.bodyMedium?.copyWith(color: AppColors.textTertiary),
          )
        else
          for (final run in overview.recentRuns.take(8)) ...[
            RunCard(
              run: run,
              onTap: () => showRunDetail(context, runId: run.id),
            ),
            const Gap(10),
          ],
        if (overview.n8nExecutions.isNotEmpty) ...[
          const SectionHeader('Derniers appels n8n'),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < overview.n8nExecutions.length; i++) ...[
                  if (i > 0) const Divider(),
                  _N8nTile(execution: overview.n8nExecutions[i]),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SourceStatsTile extends StatelessWidget {
  const _SourceStatsTile({required this.stats});

  final SourceStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final color = stats.hasError
        ? AppColors.danger
        : !stats.enabled
        ? AppColors.textTertiary
        : stats.lastSuccessAt != null
        ? AppColors.success
        : AppColors.textSecondary;
    return InkWell(
      onTap: stats.sourceId.isEmpty ? null : () => context.push(Routes.adminSource(stats.sourceId)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: StatusDot(color: color),
            ),
            const Gap(12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          stats.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
                        ),
                      ),
                      Text(
                        stats.typeLabel,
                        style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
                      ),
                    ],
                  ),
                  const Gap(4),
                  Wrap(
                    spacing: 12,
                    runSpacing: 2,
                    children: [
                      MetricText(
                        value: stats.runs7d,
                        label: 'collecte${stats.runs7d > 1 ? 's' : ''}',
                      ),
                      MetricText(
                        value: stats.failedRuns7d,
                        label: 'échec${stats.failedRuns7d > 1 ? 's' : ''}',
                        color: stats.failedRuns7d > 0 ? AppColors.danger : null,
                      ),
                      MetricText(
                        value: stats.jobsCreated7d,
                        label:
                            'offre${stats.jobsCreated7d > 1 ? 's' : ''} créée${stats.jobsCreated7d > 1 ? 's' : ''}',
                      ),
                    ],
                  ),
                  const Gap(2),
                  Text(
                    stats.hasError
                        ? stats.lastError!
                        : stats.lastRunAt == null
                        ? (stats.enabled ? 'Jamais collectée' : 'Désactivée')
                        : 'Dernière collecte ${Fmt.relative(stats.lastRunAt)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodySmall?.copyWith(
                      color: stats.hasError ? AppColors.danger : AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _N8nTile extends StatelessWidget {
  const _N8nTile({required this.execution});

  final N8nExecution execution;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final meta = [
      Fmt.relative(execution.receivedAt),
      if (execution.durationMs != null) '${execution.durationMs} ms',
      if (execution.executionId != null) 'exécution #${execution.executionId}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  execution.workflow ?? execution.endpoint ?? 'Appel n8n',
                  style: theme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
                ),
                const Gap(2),
                Text(
                  [if (execution.endpoint != null) execution.endpoint!, meta].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
                ),
                if (execution.errorCode != null) ...[
                  const Gap(2),
                  Text(
                    execution.errorCode!,
                    style: theme.bodySmall?.copyWith(color: AppColors.danger),
                  ),
                ],
              ],
            ),
          ),
          const Gap(10),
          execution.isSuccess
              ? const Pill('Succès', color: AppColors.success, dense: true)
              : const Pill('Échec', color: AppColors.danger, dense: true),
        ],
      ),
    );
  }
}
