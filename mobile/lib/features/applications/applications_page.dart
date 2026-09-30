import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/enums.dart';
import '../../core/network/api_exception.dart';
import '../../core/realtime/realtime_service.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/paged_list_view.dart';
import '../../core/widgets/ui.dart';
import 'application_providers.dart';
import 'data/application_models.dart';
import 'data/applications_repository.dart';
import 'widgets/application_card.dart';
import 'widgets/create_application_sheet.dart';

/// Onglet « Candidatures » : statistiques, filtre par statut, liste paginée.
class ApplicationsPage extends ConsumerStatefulWidget {
  const ApplicationsPage({super.key});

  @override
  ConsumerState<ApplicationsPage> createState() => _ApplicationsPageState();
}

class _ApplicationsPageState extends ConsumerState<ApplicationsPage> {
  final _list = PagedListController();
  ApplicationStatus? _filter;
  bool _loadedOnce = false;

  void _refreshAll() {
    _list.refresh();
    _refreshCounters();
  }

  void _refreshCounters() {
    ref.invalidate(applicationStatsProvider);
    ref.invalidate(unreadResponsesCountProvider);
  }

  /// Au retour du détail : met à jour la carte sans recharger toute la liste.
  Future<void> _open(Application application) async {
    await context.push(Routes.application(application.id));
    if (!mounted) return;
    _refreshCounters();
    try {
      final updated = await ref.read(applicationsRepositoryProvider).get(application.id);
      if (_filter != null && updated.status != _filter) {
        _list.removeWhere<Application>((a) => a.id == application.id);
      } else {
        _list.updateWhere<Application>((a) => a.id == application.id, (_) => updated);
      }
    } on ApiException catch (error) {
      if (error.isNotFound) _list.removeWhere<Application>((a) => a.id == application.id);
    } catch (_) {
      // Liste indicative : la prochaine actualisation corrigera.
    }
  }

  Future<void> _create() async {
    final created = await showAppSheet<Application>(
      context,
      expand: true,
      builder: (_) => const CreateApplicationSheet(),
    );
    if (created == null || !mounted) return;
    showToast('Candidature créée', kind: ToastKind.success);
    _refreshAll();
    await _open(created);
  }

  Future<void> _openResponses() async {
    await context.push(Routes.recruiterResponses);
    if (mounted) _refreshAll();
  }

  void _setFilter(ApplicationStatus? status) {
    if (status == _filter) return;
    setState(() => _filter = status);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(realtimeEventsProvider, (_, next) {
      final type = next.value?.type;
      if (type == 'application_status' || type == 'recruiter_response') _refreshAll();
    });
    final stats = ref.watch(applicationStatsProvider);
    final unread = ref.watch(unreadResponsesCountProvider).value ?? 0;
    final repository = ref.watch(applicationsRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Candidatures'),
        actions: [
          IconButton(
            tooltip: 'Réponses des recruteurs',
            onPressed: _openResponses,
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              child: const Icon(Icons.forum_outlined),
            ),
          ),
          const Gap(8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nouvelle'),
      ),
      body: PagedListView<Application>(
        key: ValueKey(_filter),
        controller: _list,
        fetch: (page) => repository.list(page: page, status: _filter),
        onTotal: (_) {
          // Pull-to-refresh : les compteurs suivent la liste.
          if (_loadedOnce) _refreshCounters();
          _loadedOnce = true;
        },
        header: [
          _StatsStrip(stats: stats.value, onTapResponses: _openResponses),
          const Gap(16),
          _StatusFilter(selected: _filter, stats: stats.value, onSelected: _setFilter),
          const Gap(14),
        ],
        itemBuilder: (context, application) =>
            ApplicationCard(application: application, onTap: () => _open(application)),
        emptyBuilder: (context) => _filter == null
            ? EmptyState(
                icon: Icons.send_outlined,
                title: 'Aucune candidature',
                message:
                    'Depuis une offre, touchez « Postuler », ou créez une candidature '
                    'pour une offre vue ailleurs.',
                actionLabel: 'Nouvelle candidature',
                onAction: _create,
              )
            : EmptyState(
                icon: Icons.filter_alt_off_outlined,
                title: 'Aucune candidature « ${_filter!.label} »',
                actionLabel: 'Tout afficher',
                onAction: () => _setFilter(null),
              ),
      ),
    );
  }
}

/// Bandeau de chiffres clés (`GET /monitoring/applications`).
class _StatsStrip extends StatelessWidget {
  const _StatsStrip({required this.stats, required this.onTapResponses});

  final ApplicationStats? stats;
  final VoidCallback onTapResponses;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final s = stats;
    String value(num? n) => s == null ? '—' : Fmt.number(n);
    final extras = <String>[
      if (s != null && s.offers > 0)
        '${s.offers} offre${s.offers > 1 ? 's' : ''} reçue${s.offers > 1 ? 's' : ''}',
      if (s?.averageResponseDays != null)
        'réponse en ${Fmt.number(s!.averageResponseDays)} j en moyenne',
    ];
    return AppCard(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 14),
      child: Column(
        children: [
          Row(
            children: [
              _Metric(label: 'Total', value: value(s?.total)),
              _Metric(label: 'Envoyées', value: value(s?.submittedTotal)),
              _Metric(
                label: 'Réponses',
                value: s == null ? '—' : '${(s.responseRate * 100).round()} %',
                onTap: onTapResponses,
              ),
              _Metric(
                label: 'Entretiens',
                value: value(s?.interviews),
                color: (s?.interviews ?? 0) > 0 ? AppColors.success : null,
              ),
            ],
          ),
          if (extras.isNotEmpty) ...[
            const Gap(12),
            Text(
              extras.join(' · '),
              textAlign: TextAlign.center,
              style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.color, this.onTap});

  final String label;
  final String value;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              Text(
                value,
                maxLines: 1,
                style: theme.titleLarge?.copyWith(
                  color: color ?? AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Gap(2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.labelSmall?.copyWith(color: AppColors.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Filtre par statut (le serveur n'accepte qu'un statut à la fois).
class _StatusFilter extends StatelessWidget {
  const _StatusFilter({required this.selected, required this.stats, required this.onSelected});

  final ApplicationStatus? selected;
  final ApplicationStats? stats;
  final ValueChanged<ApplicationStatus?> onSelected;

  @override
  Widget build(BuildContext context) {
    final s = stats;
    // Avec les statistiques : seulement les statuts présents (+ le filtre courant).
    final statuses = ApplicationStatus.values
        .where((status) => s == null || s.count(status) > 0 || status == selected)
        .toList();

    Widget chip(String label, ApplicationStatus? value, int? count) {
      final isSelected = value == selected;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(count == null ? label : '$label  $count'),
          selected: isSelected,
          labelStyle: TextStyle(
            color: isSelected ? AppColors.onAccent : AppColors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
          onSelected: (_) => onSelected(value),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip('Toutes', null, s?.total),
          for (final status in statuses) chip(status.label, status, s?.count(status)),
        ],
      ),
    );
  }
}
