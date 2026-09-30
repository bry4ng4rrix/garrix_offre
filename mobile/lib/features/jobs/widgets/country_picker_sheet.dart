import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/ui.dart';
import '../data/job_filters.dart';
import '../data/job_models.dart';
import '../jobs_providers.dart';

/// Choix des pays (plusieurs possibles). Renvoie la nouvelle sélection, ou null si fermée.
///
/// Les pays proposés et leur nombre d'offres tiennent compte des autres filtres de [filters].
Future<List<String>?> showCountryPicker(BuildContext context, JobFilters filters) =>
    showAppSheet<List<String>>(
      context,
      expand: true,
      builder: (_) => CountryPickerSheet(filters: filters),
    );

class CountryPickerSheet extends ConsumerStatefulWidget {
  const CountryPickerSheet({super.key, required this.filters});

  final JobFilters filters;

  @override
  ConsumerState<CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends ConsumerState<CountryPickerSheet> {
  late final Set<String> _selected = {...widget.filters.countries};
  String _query = '';

  void _toggle(String value) =>
      setState(() => _selected.contains(value) ? _selected.remove(value) : _selected.add(value));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final countries = ref.watch(jobCountriesProvider(widget.filters));

    return Column(
      children: [
        SheetHeader(
          title: _selected.isEmpty ? 'Pays' : 'Pays (${_selected.length})',
          trailing: _selected.isEmpty
              ? null
              : TextButton(
                  onPressed: () => setState(_selected.clear),
                  child: const Text('Tout effacer'),
                ),
        ),
        Expanded(
          child: AsyncValueView<List<CountryCount>>(
            value: countries,
            onRetry: () => ref.invalidate(jobCountriesProvider(widget.filters)),
            data: (items) {
              // Pays déjà choisis mais absents des résultats actuels : toujours affichés.
              final known = {for (final item in items) item.filterValue};
              final all = [
                ...items,
                for (final value in _selected)
                  if (!known.contains(value))
                    CountryCount(country: value == kNoCountry ? null : value, count: 0),
              ];
              final query = _query.trim().toLowerCase();
              final visible = query.isEmpty
                  ? all
                  : all
                        .where((c) => countryLabel(c.filterValue).toLowerCase().contains(query))
                        .toList();
              if (all.isEmpty) {
                return const EmptyState(
                  icon: Icons.public_off_rounded,
                  title: 'Aucun pays',
                  message: 'Aucune offre ne correspond aux autres filtres.',
                );
              }
              return ListView(
                primary: true,
                padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, 16),
                children: [
                  if (all.length > 8) ...[
                    TextField(
                      autofocus: false,
                      onChanged: (value) => setState(() => _query = value),
                      decoration: const InputDecoration(
                        hintText: 'Rechercher un pays',
                        prefixIcon: Icon(Icons.search_rounded, size: 20),
                      ),
                    ),
                    const Gap(12),
                  ],
                  Text(
                    'Nombre d\'offres selon vos autres filtres.',
                    style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
                  ),
                  const Gap(8),
                  for (final country in visible)
                    _CountryTile(
                      country: country,
                      selected: _selected.contains(country.filterValue),
                      onTap: () => _toggle(country.filterValue),
                    ),
                  if (visible.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'Aucun pays ne correspond à « $_query ».',
                        textAlign: TextAlign.center,
                        style: theme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.page, 12, AppSpacing.page, 12),
              child: PrimaryButton(
                label: _selected.isEmpty
                    ? 'Tous les pays'
                    : (_selected.length == 1
                          ? 'Afficher ce pays'
                          : 'Afficher ces ${_selected.length} pays'),
                icon: Icons.check_rounded,
                onPressed: () => Navigator.of(context).pop([..._selected]..sort()),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CountryTile extends StatelessWidget {
  const _CountryTile({required this.country, required this.selected, required this.onTap});

  final CountryCount country;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final isNone = country.country == null;
    return InkWell(
      borderRadius: AppRadius.input,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Checkbox(value: selected, onChanged: (_) => onTap()),
            const Gap(4),
            Icon(
              isNone ? Icons.public_rounded : Icons.place_outlined,
              size: 18,
              color: AppColors.textTertiary,
            ),
            const Gap(10),
            Expanded(
              child: Text(
                countryLabel(country.filterValue),
                style: theme.bodyLarge?.copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            Pill(Fmt.number(country.count), dense: true),
          ],
        ),
      ),
    );
  }
}
