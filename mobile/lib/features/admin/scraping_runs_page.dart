import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/enums.dart';
import '../../core/network/paginated.dart';
import '../../core/realtime/realtime_service.dart';
import '../../core/widgets/paged_list_view.dart';
import '../../core/widgets/ui.dart';
import 'data/admin_repository.dart';
import 'data/source_models.dart';
import 'widgets/admin_ui.dart';
import 'widgets/run_widgets.dart';

/// Historique des collectes, filtrable par statut, mis à jour en temps réel.
class ScrapingRunsPage extends ConsumerStatefulWidget {
  const ScrapingRunsPage({super.key});

  @override
  ConsumerState<ScrapingRunsPage> createState() => _ScrapingRunsPageState();
}

class _ScrapingRunsPageState extends ConsumerState<ScrapingRunsPage> {
  final _controller = PagedListController();
  final _loadedIds = <String>{};
  ScrapingRunStatus? _status;
  int? _total;
  Timer? _refreshDebounce;

  @override
  void dispose() {
    _refreshDebounce?.cancel();
    super.dispose();
  }

  Future<Paginated<ScrapingRun>> _fetch(int page) async {
    final result = await ref.read(adminRepositoryProvider).runs(page: page, status: _status);
    if (page == 1) _loadedIds.clear();
    _loadedIds.addAll(result.items.map((r) => r.id));
    return result;
  }

  void _replace(ScrapingRun run) =>
      _controller.updateWhere<ScrapingRun>((r) => r.id == run.id, (_) => run);

  /// Collecte connue : mise à jour sur place ; nouvelle collecte : rechargement (groupé).
  Future<void> _onRunEvent(String? runId) async {
    if (runId != null && _loadedIds.contains(runId)) {
      try {
        _replace(await ref.read(adminRepositoryProvider).run(runId));
        return;
      } catch (_) {}
    }
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 800), () {
      if (mounted) _controller.refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(realtimeEventsProvider, (_, next) {
      final event = next.value;
      if (event == null) return;
      if (event.type == 'scraping_run' || event.type == 'scraping_error') {
        _onRunEvent(event.data['run_id']?.toString());
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Collectes'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _controller.refresh,
          ),
          const Gap(8),
        ],
      ),
      body: PagedListView<ScrapingRun>(
        key: ValueKey(_status),
        controller: _controller,
        fetch: _fetch,
        onTotal: (total) => setState(() => _total = total),
        header: [
          const Gap(4),
          ChipBar<ScrapingRunStatus>(
            values: ScrapingRunStatus.values,
            selected: _status,
            labelOf: (s) => s.label,
            allLabel: 'Toutes',
            onSelected: (s) => setState(() => _status = s),
          ),
          ListCount(count: _total, singular: 'collecte', plural: 'collectes'),
        ],
        emptyBuilder: (_) => EmptyState(
          icon: Icons.cloud_sync_outlined,
          title: 'Aucune collecte',
          message: _status == null
              ? 'Lancez une collecte depuis le détail d\'une source.'
              : 'Aucune collecte avec le statut « ${_status!.label} ».',
        ),
        itemBuilder: (context, run) => RunCard(
          run: run,
          onTap: () => showRunDetail(context, runId: run.id, onChanged: _replace),
        ),
      ),
    );
  }
}
