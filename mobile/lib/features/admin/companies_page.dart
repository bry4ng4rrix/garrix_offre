import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/form_fields.dart';
import '../../core/widgets/paged_list_view.dart';
import '../../core/widgets/ui.dart';
import 'data/admin_repository.dart';
import 'data/directory_models.dart';
import 'widgets/admin_ui.dart';
import 'widgets/company_sheets.dart';

/// Filtres de la liste des entreprises.
typedef _CompanyFilters = ({String search, String city, String country, String industry});

/// Entreprises : recherche, fiche détaillée (provenance), création, modification, suppression.
class CompaniesPage extends ConsumerStatefulWidget {
  const CompaniesPage({super.key});

  @override
  ConsumerState<CompaniesPage> createState() => _CompaniesPageState();
}

class _CompaniesPageState extends ConsumerState<CompaniesPage> {
  final _controller = PagedListController();
  _CompanyFilters _filters = (search: '', city: '', country: '', industry: '');
  int? _total;

  bool get _hasExtra =>
      _filters.city.isNotEmpty || _filters.country.isNotEmpty || _filters.industry.isNotEmpty;

  void _apply(CompanyChange change) {
    switch (change) {
      case CompanyUpdated(:final company):
        _controller.updateWhere<Company>((c) => c.id == company.id, (_) => company);
      case CompanyDeleted(:final id):
        _controller.removeWhere<Company>((c) => c.id == id);
    }
  }

  void _open(Company company) => showAppSheet<void>(
    context,
    expand: true,
    builder: (_) => CompanyDetailSheet(company: company, onChanged: _apply),
  );

  Future<void> _create() async {
    final company = await showCompanyForm(context);
    if (company != null) await _controller.refresh();
  }

  Future<void> _openFilters() async {
    final result = await showAppSheet<_CompanyFilters>(
      context,
      builder: (_) => _FiltersSheet(initial: _filters),
    );
    if (result != null && result != _filters) setState(() => _filters = result);
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(adminRepositoryProvider);
    final filters = _filters;
    final extra = [
      if (filters.industry.isNotEmpty) filters.industry,
      if (filters.city.isNotEmpty) filters.city,
      if (filters.country.isNotEmpty) filters.country,
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Entreprises'),
        actions: [
          FilterAction(active: _hasExtra, onPressed: _openFilters),
          const Gap(8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Entreprise'),
      ),
      body: Column(
        children: [
          PageBody(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, 4, AppSpacing.page, 0),
            child: SearchField(
              hint: 'Rechercher une entreprise',
              initialValue: filters.search,
              onChanged: (value) => setState(
                () => _filters = (
                  search: value,
                  city: filters.city,
                  country: filters.country,
                  industry: filters.industry,
                ),
              ),
            ),
          ),
          Expanded(
            child: PagedListView<Company>(
              key: ValueKey(filters),
              controller: _controller,
              fetch: (page) => repo.companies(
                page: page,
                search: filters.search,
                city: filters.city,
                country: filters.country,
                industry: filters.industry,
              ),
              onTotal: (total) => setState(() => _total = total),
              header: [
                if (extra.isNotEmpty) ...[
                  const Gap(8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      InputChip(
                        label: Text(extra.join(' · ')),
                        onDeleted: () => setState(
                          () => _filters = (
                            search: filters.search,
                            city: '',
                            country: '',
                            industry: '',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                ListCount(count: _total, singular: 'entreprise', plural: 'entreprises'),
              ],
              emptyBuilder: (_) => const EmptyState(
                icon: Icons.business_outlined,
                title: 'Aucune entreprise',
                message: 'Aucune entreprise ne correspond à la recherche.',
              ),
              itemBuilder: (context, company) =>
                  _CompanyCard(company: company, onTap: () => _open(company)),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompanyCard extends StatelessWidget {
  const _CompanyCard({required this.company, required this.onTap});

  final Company company;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          AppAvatar(label: company.name, imageUrl: company.logoUrl, size: 42),
          const Gap(14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  company.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                const Gap(2),
                Text(
                  company.subtitle ?? company.website ?? 'Aucune information complémentaire',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
          const Gap(8),
          Pill(company.dataSource?.label ?? company.dataSourceValue ?? '—', dense: true),
        ],
      ),
    );
  }
}

class _FiltersSheet extends StatefulWidget {
  const _FiltersSheet({required this.initial});

  final _CompanyFilters initial;

  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  late final _industry = TextEditingController(text: widget.initial.industry);
  late final _city = TextEditingController(text: widget.initial.city);
  late final _country = TextEditingController(text: widget.initial.country);

  @override
  void dispose() {
    _industry.dispose();
    _city.dispose();
    _country.dispose();
    super.dispose();
  }

  void _submit({bool reset = false}) => Navigator.of(context).pop((
    search: widget.initial.search,
    industry: reset ? '' : _industry.text.trim(),
    city: reset ? '' : _city.text.trim(),
    country: reset ? '' : _country.text.trim(),
  ));

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Filtres', style: Theme.of(context).textTheme.titleLarge),
          const Gap(20),
          AppTextField(label: 'Secteur', controller: _industry, hint: 'Ex. Logiciel'),
          formGap,
          AppTextField(label: 'Ville', controller: _city, hint: 'Ex. Paris'),
          formGap,
          AppTextField(
            label: 'Pays',
            controller: _country,
            hint: 'Ex. France',
            onSubmitted: (_) => _submit(),
          ),
          const Gap(28),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _submit(reset: true),
                  child: const Text('Réinitialiser'),
                ),
              ),
              const Gap(10),
              Expanded(
                child: FilledButton(onPressed: _submit, child: const Text('Appliquer')),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
