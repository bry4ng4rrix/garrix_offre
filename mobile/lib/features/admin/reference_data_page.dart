import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/reference.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/paged_list_view.dart';
import '../../core/widgets/ui.dart';
import 'data/admin_providers.dart';
import 'data/admin_repository.dart';
import 'widgets/admin_ui.dart';
import 'widgets/reference_forms.dart';

/// Référentiels partagés : types de contrat, niveaux d'expérience, catégories et
/// catalogue de compétences.
class ReferenceDataPage extends ConsumerStatefulWidget {
  const ReferenceDataPage({super.key});

  @override
  ConsumerState<ReferenceDataPage> createState() => _ReferenceDataPageState();
}

class _ReferenceDataPageState extends ConsumerState<ReferenceDataPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this)
    ..addListener(() {
      if (!_tabs.indexIsChanging && mounted) setState(() {});
    });

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _add() {
    final Widget form = switch (_tabs.index) {
      0 => const ContractTypeForm(),
      1 => const ExperienceLevelForm(),
      _ => const SkillCategoryForm(),
    };
    showAppSheet<bool>(context, expand: _tabs.index != 2, builder: (_) => form);
  }

  @override
  Widget build(BuildContext context) {
    final label = switch (_tabs.index) {
      0 => 'Type de contrat',
      1 => 'Niveau',
      _ => 'Catégorie',
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('Référentiels'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          tabs: const [
            Tab(text: 'Types de contrat'),
            Tab(text: 'Niveaux d\'expérience'),
            Tab(text: 'Catégories de compétences'),
            Tab(text: 'Catalogue de compétences'),
          ],
        ),
      ),
      floatingActionButton: _tabs.index == 3
          ? null
          : FloatingActionButton.extended(
              onPressed: _add,
              icon: const Icon(Icons.add_rounded),
              label: Text(label),
            ),
      body: TabBarView(
        controller: _tabs,
        children: const [_ContractTypesTab(), _LevelsTab(), _CategoriesTab(), _CatalogTab()],
      ),
    );
  }
}

/// Ligne d'un référentiel : nom, code, informations secondaires.
class _RefTile extends StatelessWidget {
  const _RefTile({
    required this.name,
    required this.code,
    this.details,
    this.trailing = const [],
    this.muted = false,
    this.monoCode = true,
    this.onTap,
  });

  final String name;
  final String code;
  final bool monoCode;
  final String? details;
  final List<Widget> trailing;
  final bool muted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: theme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: muted ? AppColors.textTertiary : AppColors.textPrimary,
                  ),
                ),
                const Gap(2),
                Text(
                  code,
                  style: theme.bodySmall?.copyWith(
                    fontFamily: monoCode ? 'monospace' : null,
                    color: AppColors.textTertiary,
                  ),
                ),
                if (details != null && details!.isNotEmpty) ...[
                  const Gap(4),
                  Text(
                    details!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodySmall?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          if (trailing.isNotEmpty) ...[
            const Gap(10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < trailing.length; i++) ...[if (i > 0) const Gap(6), trailing[i]],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Liste simple d'un référentiel, avec pull-to-refresh.
class _RefList<T> extends StatelessWidget {
  const _RefList({
    required this.value,
    required this.onRefresh,
    required this.itemBuilder,
    required this.emptyTitle,
    this.intro,
  });

  final AsyncValue<List<T>> value;
  final Future<void> Function() onRefresh;
  final Widget Function(T item) itemBuilder;
  final String emptyTitle;
  final String? intro;

  @override
  Widget build(BuildContext context) => AsyncValueView<List<T>>(
    value: value,
    onRetry: onRefresh,
    data: (items) => PageListView(
      onRefresh: onRefresh,
      children: [
        const Gap(8),
        if (intro != null) ...[
          Text(
            intro!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
          ),
          const Gap(14),
        ],
        if (items.isEmpty)
          EmptyState(icon: Icons.category_outlined, title: emptyTitle)
        else
          for (final item in items) ...[itemBuilder(item), const Gap(8)],
      ],
    ),
  );
}

class _ContractTypesTab extends ConsumerWidget {
  const _ContractTypesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) => _RefList<ContractType>(
    value: ref.watch(adminContractTypesProvider),
    onRefresh: () async {
      ref.invalidate(adminContractTypesProvider);
      await ref.read(adminContractTypesProvider.future).then((_) {}, onError: (_) {});
    },
    emptyTitle: 'Aucun type de contrat',
    intro: 'Les synonymes servent à reconnaître le contrat dans le texte des offres.',
    itemBuilder: (item) => _RefTile(
      name: item.name,
      code: item.code,
      details: item.aliases.join(', '),
      muted: !item.isActive,
      trailing: [
        if (!item.isActive) const Pill('Inactif', dense: true),
        Pill('#${item.sortOrder}', dense: true, filled: false),
      ],
      onTap: () =>
          showAppSheet<bool>(context, expand: true, builder: (_) => ContractTypeForm(item: item)),
    ),
  );
}

class _LevelsTab extends ConsumerWidget {
  const _LevelsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) => _RefList<ExperienceLevel>(
    value: ref.watch(experienceLevelsProvider),
    onRefresh: () async {
      ref.invalidate(experienceLevelsProvider);
      await ref.read(experienceLevelsProvider.future).then((_) {}, onError: (_) {});
    },
    emptyTitle: 'Aucun niveau d\'expérience',
    intro: 'Le rang ordonne les niveaux pour le matching (0 = débutant).',
    itemBuilder: (item) => _RefTile(
      name: item.name,
      code: item.code,
      details: item.aliases.join(', '),
      trailing: [
        Pill('Rang ${item.rank}', dense: true),
        Pill('${item.minYears} an${item.minYears > 1 ? 's' : ''} min.', dense: true, filled: false),
      ],
      onTap: () => showAppSheet<bool>(
        context,
        expand: true,
        builder: (_) => ExperienceLevelForm(item: item),
      ),
    ),
  );
}

class _CategoriesTab extends ConsumerWidget {
  const _CategoriesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) => _RefList<SkillCategory>(
    value: ref.watch(skillCategoriesProvider),
    onRefresh: () async {
      ref.invalidate(skillCategoriesProvider);
      await ref.read(skillCategoriesProvider.future).then((_) {}, onError: (_) {});
    },
    emptyTitle: 'Aucune catégorie',
    itemBuilder: (item) => _RefTile(
      name: item.name,
      code: item.code,
      details: item.description,
      onTap: () => showAppSheet<bool>(context, builder: (_) => SkillCategoryForm(item: item)),
    ),
  );
}

/// Catalogue de compétences : recherche, filtre par catégorie, modification.
class _CatalogTab extends ConsumerStatefulWidget {
  const _CatalogTab();

  @override
  ConsumerState<_CatalogTab> createState() => _CatalogTabState();
}

class _CatalogTabState extends ConsumerState<_CatalogTab> with AutomaticKeepAliveClientMixin {
  final _controller = PagedListController();
  String _search = '';
  String? _category;
  int? _total;

  @override
  bool get wantKeepAlive => true;

  Future<void> _edit(CatalogSkill skill) async {
    final saved = await showAppSheet<CatalogSkill>(
      context,
      builder: (_) => CatalogSkillForm(skill: skill),
    );
    if (saved != null) {
      _controller.updateWhere<CatalogSkill>((s) => s.id == saved.id, (_) => saved);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final repo = ref.watch(adminRepositoryProvider);
    final categories = ref.watch(skillCategoriesProvider).value ?? const <SkillCategory>[];
    final names = {for (final c in categories) c.code: c.name};

    return Column(
      children: [
        PageBody(
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, 12, AppSpacing.page, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SearchField(
                hint: 'Rechercher une compétence',
                initialValue: _search,
                onChanged: (value) => setState(() => _search = value),
              ),
              if (categories.isNotEmpty) ...[
                const Gap(10),
                ChipBar<String>(
                  values: [for (final c in categories) c.code],
                  selected: _category,
                  labelOf: (code) => names[code] ?? code,
                  allLabel: 'Toutes',
                  onSelected: (code) => setState(() => _category = code),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: PagedListView<CatalogSkill>(
            key: ValueKey('$_search|$_category'),
            controller: _controller,
            separator: const Gap(8),
            fetch: (page) => repo.catalog(page: page, search: _search, category: _category),
            onTotal: (total) => setState(() => _total = total),
            header: [ListCount(count: _total, singular: 'compétence', plural: 'compétences')],
            emptyBuilder: (_) => const EmptyState(
              icon: Icons.psychology_outlined,
              title: 'Aucune compétence',
              message: 'Aucune compétence ne correspond à la recherche.',
            ),
            itemBuilder: (context, skill) => _RefTile(
              name: skill.name,
              code: skill.category == null
                  ? 'Sans catégorie'
                  : (names[skill.category] ?? skill.category!),
              monoCode: false,
              details: skill.aliases.join(', '),
              onTap: () => _edit(skill),
            ),
          ),
        ),
      ],
    );
  }
}
