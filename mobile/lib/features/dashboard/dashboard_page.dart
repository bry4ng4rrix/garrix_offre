import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/models/enums.dart';
import '../../core/realtime/realtime_service.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/ui.dart';
import '../jobs/data/job_filters.dart';
import '../jobs/data/job_models.dart';
import '../jobs/data/jobs_repository.dart';
import '../jobs/jobs_providers.dart';
import 'data/dashboard_repository.dart';
import 'widgets/dashboard_sections.dart';

/// Onglet « Accueil » : indicateurs du jour, meilleures offres, suivi des candidatures,
/// actions rapides et (admin) état des services.
class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  /// Regroupe les événements temps réel rapprochés (collecte = rafale d'événements).
  Timer? _realtimeDebounce;
  bool _recalculating = false;

  static const _jobEvents = {'new_job', 'high_match', 'matching_recalculated'};
  static const _applicationEvents = {'application_status', 'recruiter_response'};

  @override
  void dispose() {
    _realtimeDebounce?.cancel();
    super.dispose();
  }

  void _invalidateAll() {
    ref.invalidate(dashboardOverviewProvider);
    ref.invalidate(applicationStatsProvider);
    ref.invalidate(topMatchesProvider);
  }

  Future<void> _refresh() async {
    _invalidateAll();
    ref.invalidate(greetingNameProvider);
    unawaited(ref.read(unreadCountProvider.notifier).refresh());
    try {
      await Future.wait<Object?>([
        ref.read(dashboardOverviewProvider.future),
        ref.read(applicationStatsProvider.future),
        ref.read(topMatchesProvider.future),
      ]);
    } catch (_) {
      // Les erreurs sont affichées dans chaque section.
    }
  }

  void _onRealtime(RealtimeEvent? event) {
    if (event == null) return;
    final jobs = _jobEvents.contains(event.type);
    if (!jobs && !_applicationEvents.contains(event.type)) return;
    _realtimeDebounce?.cancel();
    _realtimeDebounce = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      ref.invalidate(dashboardOverviewProvider);
      if (jobs) {
        ref.invalidate(topMatchesProvider);
      } else {
        ref.invalidate(applicationStatsProvider);
      }
    });
  }

  /// Met à jour les meilleures offres quand une offre change ailleurs (score, sauvegarde...).
  void _onJobChanged(JobChange? change) {
    if (change == null) return;
    if (change.created || change.deleted) {
      ref.invalidate(topMatchesProvider);
      ref.invalidate(dashboardOverviewProvider);
      return;
    }
    final job = change.job!;
    final top = ref.read(topMatchesProvider).value?.items ?? const <Job>[];
    for (final current in top) {
      if (current.id != job.id) continue;
      if (current.score != job.score ||
          current.status.isIgnored != job.status.isIgnored ||
          current.status.isSaved != job.status.isSaved) {
        ref.invalidate(topMatchesProvider);
      }
      return;
    }
  }

  Future<void> _recalculate() async {
    setState(() => _recalculating = true);
    final result = await runAction(() => ref.read(jobsRepositoryProvider).recalculateAll());
    if (!mounted) return;
    setState(() => _recalculating = false);
    if (result == null) return;
    if (result.isQueued) {
      showToast(
        'Recalcul lancé : les scores seront mis à jour dans un instant.',
        kind: ToastKind.success,
      );
    } else {
      final count = result.jobsMatched ?? 0;
      showToast(
        count <= 1 ? '$count offre recalculée' : '$count offres recalculées',
        kind: ToastKind.success,
      );
      _invalidateAll();
    }
  }

  /// Ouvre l'onglet Offres avec les filtres donnés.
  void _openJobs(JobFilters filters) {
    ref.read(jobFiltersProvider.notifier).set(filters);
    context.go(Routes.jobs);
  }

  /// Onglet Offres filtré sur les offres au-dessus du seuil, triées par score.
  void _openBestMatches() {
    final threshold = ref.read(dashboardOverviewProvider).value?.matchingThreshold ?? 70;
    ref.read(jobFiltersProvider.notifier).showBestMatches(threshold);
    context.go(Routes.jobs);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(realtimeEventsProvider, (_, next) => _onRealtime(next.value));
    ref.listen(jobChangesProvider, (_, change) => _onJobChanged(change));

    final overview = ref.watch(dashboardOverviewProvider);
    final isAdmin = ref.watch(isAdminProvider);
    final threshold = overview.value?.matchingThreshold ?? 70;
    final total = ref.watch(topMatchesProvider).value?.total ?? 0;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: PageListView(
          onRefresh: _refresh,
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.lg, AppSpacing.page, 40),
          children: [
            const DashboardGreeting(),
            const Gap(24),
            StatsGrid(
              onBestMatches: _openBestMatches,
              onNewJobs: () => _openJobs(const JobFilters(sortBy: JobSortField.createdAt)),
            ),
            SectionHeader(
              'Meilleures offres',
              action: total > 0 ? 'Tout voir' : null,
              onAction: _openBestMatches,
            ),
            TopMatchesCard(threshold: threshold),
            SectionHeader(
              'Candidatures',
              action: 'Tout voir',
              onAction: () => context.go(Routes.applications),
            ),
            const PipelineCard(),
            const SectionHeader('Actions rapides'),
            Row(
              children: [
                Expanded(
                  child: QuickActionTile(
                    icon: Icons.auto_graph_rounded,
                    label: 'Recalculer le matching',
                    loading: _recalculating,
                    onTap: _recalculate,
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: QuickActionTile(
                    icon: Icons.add_rounded,
                    label: 'Ajouter une offre',
                    onTap: () => context.push(Routes.jobNew),
                  ),
                ),
              ],
            ),
            if (isAdmin) ...[
              SectionHeader(
                'Système',
                action: 'Détails',
                onAction: () => context.push(Routes.adminSystem),
              ),
              const ServicesCard(),
            ],
          ],
        ),
      ),
    );
  }
}
