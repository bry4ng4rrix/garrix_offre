import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/enums.dart';
import '../../core/realtime/realtime_service.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/json.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/paged_list_view.dart';
import '../../core/widgets/ui.dart';
import '../dashboard/data/dashboard_repository.dart';
import 'data/job_filters.dart';
import 'data/job_models.dart';
import 'data/jobs_repository.dart';
import 'jobs_providers.dart';
import 'widgets/external_links.dart';
import 'widgets/job_card.dart';
import 'widgets/job_filters_sheet.dart';

/// Onglet « Offres » : recherche, filtres rapides, feuille de filtres complète et liste infinie.
class JobsPage extends ConsumerStatefulWidget {
  const JobsPage({super.key});

  @override
  ConsumerState<JobsPage> createState() => _JobsPageState();
}

class _JobsPageState extends ConsumerState<JobsPage> {
  final _list = PagedListController();
  late final TextEditingController _search;
  Timer? _debounce;
  int? _total;
  bool _atTop = true;
  int _pendingNew = 0;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: ref.read(jobFiltersProvider).search);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  JobFiltersNotifier get _filters => ref.read(jobFiltersProvider.notifier);

  void _onSearchChanged(String value) {
    setState(() {}); // bouton « effacer »
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _filters.setSearch(value));
  }

  void _clearSearch() {
    _debounce?.cancel();
    _search.clear();
    _filters.setSearch(null);
  }

  Future<void> _openFilters() async {
    final result = await showJobFiltersSheet(context, ref.read(jobFiltersProvider));
    if (result != null) _filters.set(result);
  }

  Future<void> _refresh() async {
    setState(() => _pendingNew = 0);
    await _list.refresh();
  }

  /// Vrai si l'offre a encore sa place dans la liste avec le filtre de statut courant.
  static bool _stillVisible(Job job, JobStatusFilter? status) => switch (status) {
    JobStatusFilter.saved => job.status.isSaved,
    JobStatusFilter.ignored => job.status.isIgnored,
    JobStatusFilter.all => true,
    _ => !job.status.isIgnored,
  };

  void _onJobChanged(JobChange? change) {
    if (change == null) return;
    if (change.created) {
      unawaited(_list.refresh());
    } else if (change.deleted) {
      _list.removeWhere<Job>((job) => job.id == change.id);
    } else {
      final job = change.job!;
      if (_stillVisible(job, ref.read(jobFiltersProvider).status)) {
        _list.updateWhere<Job>((item) => item.id == job.id, (_) => job);
      } else {
        _list.removeWhere<Job>((item) => item.id == job.id);
      }
    }
  }

  void _onRealtime(RealtimeEvent? event) {
    if (event == null) return;
    if (event.type != 'new_job' && event.type != 'matching_recalculated') return;
    // En haut de liste : rechargement direct ; sinon on propose d'actualiser.
    if (_atTop) {
      unawaited(_refresh());
    } else {
      final count = event.type == 'new_job' ? (parseInt(event.data['count']) ?? 1) : 0;
      setState(() => _pendingNew += math.max(count, 1));
    }
  }

  Future<void> _updateState(Job job, JobStateUpdate update, {String? success}) async {
    final updated = await runAction(
      () => ref.read(jobsRepositoryProvider).updateState(job.id, update),
      success: success,
    );
    if (updated != null) ref.read(jobChangesProvider.notifier).emit(JobChange.updated(updated));
  }

  Future<void> _toggleSave(Job job) => _updateState(
    job,
    JobStateUpdate(isSaved: !job.status.isSaved),
    success: job.status.isSaved ? 'Retirée des sauvegardes' : 'Offre sauvegardée',
  );

  Future<void> _ignore(Job job) async {
    final updated = await runAction(
      () => ref.read(jobsRepositoryProvider).updateState(job.id, const JobStateUpdate(isIgnored: true)),
    );
    if (updated == null) return;
    ref.read(jobChangesProvider.notifier).emit(JobChange.updated(updated));
    showToast(
      'Offre ignorée',
      action: SnackBarAction(
        label: 'Annuler',
        onPressed: () async {
          final restored = await runAction(
            () => ref
                .read(jobsRepositoryProvider)
                .updateState(job.id, const JobStateUpdate(isIgnored: false)),
          );
          if (restored != null && mounted) await _list.refresh();
        },
      ),
    );
  }

  Future<void> _showActions(Job job) async {
    final action = await showJobActionsSheet(context, job);
    if (action == null || !mounted) return;
    switch (action) {
      case JobQuickAction.open:
        unawaited(context.push(Routes.job(job.id)));
      case JobQuickAction.toggleSave:
        await _toggleSave(job);
      case JobQuickAction.toggleIgnore:
        if (job.status.isIgnored) {
          await _updateState(job, const JobStateUpdate(isIgnored: false), success: 'Offre rétablie');
        } else {
          await _ignore(job);
        }
      case JobQuickAction.toggleSeen:
        await _updateState(
          job,
          JobStateUpdate(seen: job.status.isNew),
          success: job.status.isNew ? 'Marquée comme vue' : 'Marquée comme non vue',
        );
      case JobQuickAction.openListing:
        await openExternalUrl(job.listingUrl!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filters = ref.watch(jobFiltersProvider);
    final threshold = ref.watch(dashboardOverviewProvider).value?.matchingThreshold ?? 70;

    ref.listen(jobFiltersProvider, (previous, next) {
      if ((next.search ?? '') != _search.text.trim()) _search.text = next.search ?? '';
      if (previous != next) {
        setState(() {
          _total = null;
          _pendingNew = 0;
        });
      }
    });
    ref.listen(jobChangesProvider, (_, change) => _onJobChanged(change));
    ref.listen(realtimeEventsProvider, (_, next) => _onRealtime(next.value));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Offres'),
        actions: [
          IconButton(
            tooltip: 'Filtres',
            onPressed: _openFilters,
            icon: Badge(
              isLabelVisible: filters.activeCount > 0,
              label: Text('${filters.activeCount}'),
              backgroundColor: AppColors.accent,
              textColor: AppColors.onAccent,
              child: const Icon(Icons.tune_rounded),
            ),
          ),
          const Gap(8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'jobs-add',
        onPressed: () => context.push(Routes.jobNew),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Ajouter'),
      ),
      body: Column(
        children: [
          PageBody(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xs, AppSpacing.page, 0),
            child: TextField(
              controller: _search,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              onSubmitted: (value) {
                _debounce?.cancel();
                _filters.setSearch(value);
              },
              decoration: InputDecoration(
                hintText: 'Rechercher un poste, une entreprise…',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Effacer',
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: _clearSearch,
                      ),
              ),
            ),
          ),
          const Gap(12),
          _QuickFilters(filters: filters, threshold: threshold, onOpenFilters: _openFilters),
          const Gap(4),
          Expanded(
            child: Stack(
              children: [
                NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification.depth == 0 && notification.metrics.axis == Axis.vertical) {
                      _atTop = notification.metrics.pixels < 120;
                    }
                    return false;
                  },
                  child: PagedListView<Job>(
                    key: ValueKey(filters),
                    controller: _list,
                    fetch: (page) => ref.read(jobsRepositoryProvider).search(filters, page: page),
                    onTotal: (total) {
                      if (mounted) setState(() => _total = total);
                    },
                    header: [
                      _ResultsHeader(
                        total: _total,
                        filters: filters,
                        onSort: (sortBy, desc) =>
                            _filters.set(filters.copyWith(sortBy: sortBy, sortDesc: desc)),
                        onReset: () {
                          _clearSearch();
                          _filters.resetFilters();
                        },
                      ),
                    ],
                    itemBuilder: (context, job) => JobCard(
                      job: job,
                      onTap: () => context.push(Routes.job(job.id)),
                      onToggleSave: () => _toggleSave(job),
                      onMore: () => _showActions(job),
                    ),
                    emptyBuilder: (context) => filters.activeCount > 0 || filters.hasSearch
                        ? EmptyState(
                            icon: Icons.search_off_rounded,
                            title: 'Aucune offre ne correspond',
                            message: 'Essayez d\'élargir vos critères de recherche.',
                            actionLabel: 'Réinitialiser les filtres',
                            onAction: () {
                              _clearSearch();
                              _filters.resetFilters();
                            },
                          )
                        : EmptyState(
                            icon: Icons.work_outline_rounded,
                            title: 'Aucune offre pour l\'instant',
                            message:
                                'Les offres collectées apparaîtront ici. Vous pouvez aussi en ajouter une vous-même.',
                            actionLabel: 'Ajouter une offre',
                            onAction: () => context.push(Routes.jobNew),
                          ),
                  ),
                ),
                if (_pendingNew > 0)
                  Positioned(
                    top: 8,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: _NewJobsBanner(count: _pendingNew, onTap: _refresh),
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

/// Rangée horizontale de filtres rapides.
class _QuickFilters extends ConsumerWidget {
  const _QuickFilters({required this.filters, required this.threshold, required this.onOpenFilters});

  final JobFilters filters;
  final int threshold;
  final VoidCallback onOpenFilters;

  Future<void> _pickStatus(BuildContext context, WidgetRef ref) async {
    final choice = await showAppSheet<_StatusChoice>(
      context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHeader(title: 'Statut des offres'),
            for (final status in <JobStatusFilter?>[null, ...JobStatusFilter.values])
              ListTile(
                minTileHeight: 48,
                title: Text(status?.label ?? 'Par défaut (nouvelles et actives)'),
                trailing: status == filters.status
                    ? const Icon(Icons.check_rounded, color: AppColors.textPrimary)
                    : null,
                onTap: () => Navigator.of(context).pop(_StatusChoice(status)),
              ),
            const Gap(8),
          ],
        ),
      ),
    );
    if (choice != null) {
      ref.read(jobFiltersProvider.notifier).set(filters.copyWith(status: choice.status));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(jobFiltersProvider.notifier);
    final count = filters.activeCount;
    final minScore = filters.minScore;
    final chips = <Widget>[
      _Chip(
        label: count > 0 ? 'Filtres · $count' : 'Filtres',
        icon: Icons.tune_rounded,
        selected: count > 0,
        onTap: onOpenFilters,
      ),
      _Chip(
        label: filters.status?.label ?? 'Statut',
        trailingIcon: Icons.expand_more_rounded,
        selected: filters.status != null,
        onTap: () => _pickStatus(context, ref),
      ),
      _Chip(
        label: minScore != null ? 'Score ≥ $minScore' : 'Score ≥ $threshold',
        icon: Icons.bolt_rounded,
        selected: minScore != null,
        onTap: () => notifier.set(filters.copyWith(minScore: minScore != null ? null : threshold)),
      ),
      _Chip(
        label: 'Télétravail',
        icon: Icons.home_work_outlined,
        selected: filters.remote == true,
        onTap: () => notifier.set(filters.copyWith(remote: filters.remote == true ? null : true)),
      ),
      for (final category in SourceCategory.values)
        _Chip(
          label: category.label,
          icon: category.icon,
          selected: filters.sourceCategory == category,
          onTap: () => notifier.set(
            filters.copyWith(sourceCategory: filters.sourceCategory == category ? null : category),
          ),
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final side =
            AppSpacing.page + math.max(0.0, (constraints.maxWidth - AppSpacing.maxContentWidth) / 2);
        return SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: side),
            itemCount: chips.length,
            separatorBuilder: (_, _) => const Gap(8),
            itemBuilder: (_, index) => chips[index],
          ),
        );
      },
    );
  }
}

class _StatusChoice {
  const _StatusChoice(this.status);
  final JobStatusFilter? status;
}

/// Pastille de filtre : fond blanc quand active.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.trailingIcon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.onAccent : AppColors.textPrimary;
    return Material(
      color: selected ? AppColors.accent : AppColors.surface,
      shape: StadiumBorder(
        side: BorderSide(color: selected ? AppColors.accent : AppColors.borderStrong),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: selected ? AppColors.onAccent : AppColors.textSecondary),
                const Gap(6),
              ],
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (trailingIcon != null) ...[
                const Gap(4),
                Icon(trailingIcon, size: 16, color: fg),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// « 296 offres · Trier ».
class _ResultsHeader extends StatelessWidget {
  const _ResultsHeader({
    required this.total,
    required this.filters,
    required this.onSort,
    required this.onReset,
  });

  final int? total;
  final JobFilters filters;
  final void Function(JobSortField sortBy, bool desc) onSort;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final count = total;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              count == null ? ' ' : (count <= 1 ? '$count offre' : '${Fmt.number(count)} offres'),
              style: theme.labelLarge?.copyWith(color: AppColors.textSecondary),
            ),
          ),
          if (filters.activeCount > 0 || filters.hasSearch)
            TextButton(
              onPressed: onReset,
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 40),
                foregroundColor: AppColors.textSecondary,
              ),
              child: const Text('Réinitialiser'),
            ),
          PopupMenuButton<Object>(
            tooltip: 'Trier',
            position: PopupMenuPosition.under,
            onSelected: (value) {
              if (value is JobSortField) {
                onSort(value, value != JobSortField.title);
              } else {
                onSort(filters.sortBy, !filters.sortDesc);
              }
            },
            itemBuilder: (context) => [
              for (final field in JobSortField.values)
                CheckedPopupMenuItem<Object>(
                  value: field,
                  checked: field == filters.sortBy,
                  child: Text(field.label),
                ),
              const PopupMenuDivider(),
              PopupMenuItem<Object>(
                value: 'order',
                child: Row(
                  children: [
                    const Icon(Icons.swap_vert_rounded, size: 18, color: AppColors.textSecondary),
                    const Gap(10),
                    Text(sortOrderLabel(filters.sortBy, !filters.sortDesc)),
                  ],
                ),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.sort_rounded, size: 18, color: AppColors.textSecondary),
                  const Gap(6),
                  Text(
                    filters.sortBy.label,
                    style: theme.labelLarge?.copyWith(color: AppColors.textSecondary),
                  ),
                  Icon(
                    filters.sortDesc ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                    size: 14,
                    color: AppColors.textTertiary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bandeau « Nouvelles offres · Actualiser » (événements temps réel).
class _NewJobsBanner extends StatelessWidget {
  const _NewJobsBanner({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.accent,
    shape: const StadiumBorder(),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.arrow_upward_rounded, size: 16, color: AppColors.onAccent),
            const Gap(8),
            Text(
              count == 1 ? 'Nouveautés · Actualiser' : '$count nouveautés · Actualiser',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppColors.onAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
