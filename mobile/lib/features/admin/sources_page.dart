import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/enums.dart';
import '../../core/network/api_exception.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/form_fields.dart';
import '../../core/widgets/paged_list_view.dart';
import '../../core/widgets/ui.dart';
import 'data/admin_providers.dart';
import 'data/admin_repository.dart';
import 'data/source_models.dart';
import 'widgets/admin_ui.dart';
import 'widgets/source_form_sheet.dart';

/// Filtres de la liste des sources.
class _SourceFilters {
  const _SourceFilters({this.category, this.type, this.enabled});

  final SourceCategory? category;
  final SourceType? type;
  final bool? enabled;

  bool get hasExtra => type != null || enabled != null;

  _SourceFilters copyWith({
    SourceCategory? Function()? category,
    SourceType? Function()? type,
    bool? Function()? enabled,
  }) => _SourceFilters(
    category: category == null ? this.category : category(),
    type: type == null ? this.type : type(),
    enabled: enabled == null ? this.enabled : enabled(),
  );

  @override
  bool operator ==(Object other) =>
      other is _SourceFilters &&
      other.category == category &&
      other.type == type &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(category, type, enabled);
}

/// Sources d'offres : filtre par catégorie, activation rapide, création.
class SourcesPage extends ConsumerStatefulWidget {
  const SourcesPage({super.key});

  @override
  ConsumerState<SourcesPage> createState() => _SourcesPageState();
}

class _SourcesPageState extends ConsumerState<SourcesPage> {
  final _controller = PagedListController();
  _SourceFilters _filters = const _SourceFilters();
  int? _total;

  Future<void> _create() async {
    final source = await showSourceForm(context);
    if (source == null || !mounted) return;
    await _controller.refresh();
    if (mounted) await context.push(Routes.adminSource(source.id));
  }

  Future<void> _open(Source source) async {
    await context.push(Routes.adminSource(source.id));
    if (!mounted) return;
    // La source a pu être modifiée ou supprimée depuis le détail.
    try {
      final fresh = await ref.read(adminRepositoryProvider).source(source.id);
      _controller.updateWhere<Source>((s) => s.id == source.id, (_) => fresh);
    } on ApiException catch (error) {
      if (error.isNotFound) _controller.removeWhere<Source>((s) => s.id == source.id);
    } catch (_) {}
  }

  Future<void> _toggle(Source source, bool enabled) async {
    _controller.updateWhere<Source>((s) => s.id == source.id, (s) => s.copyWith(enabled: enabled));
    try {
      final saved = await ref.read(adminRepositoryProvider).updateSource(source.id, {
        'enabled': enabled,
      });
      _controller.updateWhere<Source>((s) => s.id == source.id, (_) => saved);
      ref.invalidate(sourceDetailProvider(source.id));
      showToast(enabled ? 'Source activée' : 'Source désactivée', kind: ToastKind.success);
    } catch (error) {
      _controller.updateWhere<Source>((s) => s.id == source.id, (_) => source);
      showAdminError(error);
    }
  }

  Future<void> _openFilters() async {
    final result = await showAppSheet<_SourceFilters>(
      context,
      builder: (_) => _FiltersSheet(initial: _filters),
    );
    if (result != null && result != _filters) setState(() => _filters = result);
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(adminRepositoryProvider);
    final filters = _filters;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sources'),
        actions: [
          FilterAction(active: filters.hasExtra, onPressed: _openFilters),
          const Gap(8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Source'),
      ),
      body: PagedListView<Source>(
        key: ValueKey(filters),
        controller: _controller,
        fetch: (page) => repo.sources(
          page: page,
          category: filters.category,
          type: filters.type,
          enabled: filters.enabled,
        ),
        onTotal: (total) => setState(() => _total = total),
        header: [
          const Gap(4),
          ChipBar<SourceCategory>(
            values: SourceCategory.values,
            selected: filters.category,
            labelOf: (c) => c.label,
            iconOf: (c) => c.icon,
            allLabel: 'Toutes',
            onSelected: (c) => setState(() => _filters = filters.copyWith(category: () => c)),
          ),
          if (filters.hasExtra) ...[
            const Gap(10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (filters.enabled != null)
                  InputChip(
                    label: Text(filters.enabled! ? 'Actives' : 'Désactivées'),
                    onDeleted: () =>
                        setState(() => _filters = filters.copyWith(enabled: () => null)),
                  ),
                if (filters.type != null)
                  InputChip(
                    label: Text(filters.type!.label),
                    onDeleted: () => setState(() => _filters = filters.copyWith(type: () => null)),
                  ),
              ],
            ),
          ],
          ListCount(count: _total, singular: 'source', plural: 'sources'),
        ],
        emptyBuilder: (_) => EmptyState(
          icon: Icons.rss_feed_rounded,
          title: 'Aucune source',
          message: filters == const _SourceFilters()
              ? 'Ajoutez une première source d\'offres.'
              : 'Aucune source ne correspond à ces filtres.',
        ),
        itemBuilder: (context, source) => _SourceCard(
          source: source,
          showCategory: filters.category == null,
          onTap: () => _open(source),
          onToggle: (value) => _toggle(source, value),
        ),
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.source,
    required this.showCategory,
    required this.onTap,
    required this.onToggle,
  });

  final Source source;
  final bool showCategory;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final lastRun = source.lastRunAt == null
        ? 'Jamais collectée'
        : 'Dernière collecte ${Fmt.relative(source.lastRunAt)}';
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  source.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.titleSmall?.copyWith(
                    color: source.enabled ? AppColors.textPrimary : AppColors.textTertiary,
                  ),
                ),
                const Gap(8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (showCategory)
                      Pill(source.categoryLabel, icon: source.category?.icon, dense: true),
                    Pill(source.typeLabel, dense: true),
                    Pill(source.fetchModeLabel, dense: true, filled: false),
                    if (source.hasAdapter) Pill(source.adapter!, dense: true, filled: false),
                    if (source.scrapingEnabled)
                      const Pill(
                        'Auto',
                        dense: true,
                        color: AppColors.info,
                        icon: Icons.schedule_rounded,
                      ),
                  ],
                ),
                const Gap(8),
                Row(
                  children: [
                    Icon(
                      source.hasError ? Icons.error_outline_rounded : Icons.history_rounded,
                      size: 14,
                      color: source.hasError ? AppColors.danger : AppColors.textTertiary,
                    ),
                    const Gap(6),
                    Expanded(
                      child: Text(
                        source.hasError ? 'Erreur : ${source.lastError}' : lastRun,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.bodySmall?.copyWith(
                          color: source.hasError ? AppColors.danger : AppColors.textTertiary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Tooltip(
            message: source.enabled ? 'Désactiver' : 'Activer',
            child: Switch(value: source.enabled, onChanged: onToggle),
          ),
        ],
      ),
    );
  }
}

class _FiltersSheet extends StatefulWidget {
  const _FiltersSheet({required this.initial});

  final _SourceFilters initial;

  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  late _SourceFilters _filters = widget.initial;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Filtres', style: theme.titleLarge),
            const Gap(20),
            const FieldLabel('État'),
            ChoiceChips<bool>(
              values: const [true, false],
              selected: _filters.enabled,
              allowDeselect: true,
              labelOf: (v) => v ? 'Actives' : 'Désactivées',
              onSelected: (v) => setState(() => _filters = _filters.copyWith(enabled: () => v)),
            ),
            formGap,
            const FieldLabel('Type'),
            ChoiceChips<SourceType>(
              values: SourceType.values,
              selected: _filters.type,
              allowDeselect: true,
              labelOf: (t) => t.label,
              onSelected: (t) => setState(() => _filters = _filters.copyWith(type: () => t)),
            ),
            const Gap(28),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        Navigator.of(context).pop(_SourceFilters(category: _filters.category)),
                    child: const Text('Réinitialiser'),
                  ),
                ),
                const Gap(10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(_filters),
                    child: const Text('Appliquer'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
