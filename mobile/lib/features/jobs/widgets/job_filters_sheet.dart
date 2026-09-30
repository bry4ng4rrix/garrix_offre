import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/enums.dart';
import '../../../core/models/reference.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/ui.dart';
import '../data/job_filters.dart';
import 'country_picker_sheet.dart';

/// Libellé de l'ordre de tri, adapté au champ trié.
String sortOrderLabel(JobSortField field, bool desc) => switch (field) {
  JobSortField.score => desc ? 'Meilleurs scores d\'abord' : 'Scores les plus bas d\'abord',
  JobSortField.title => desc ? 'De Z à A' : 'De A à Z',
  JobSortField.publishedAt ||
  JobSortField.createdAt => desc ? 'Plus récentes d\'abord' : 'Plus anciennes d\'abord',
};

/// Ouvre la feuille de filtres ; renvoie les nouveaux filtres (null si fermée sans valider).
Future<JobFilters?> showJobFiltersSheet(BuildContext context, JobFilters initial) =>
    showAppSheet<JobFilters>(
      context,
      expand: true,
      builder: (_) => JobFiltersSheet(initial: initial),
    );

/// Tous les critères de `GET /jobs` : recherche, score, contrat, télétravail, lieu, compétence,
/// entreprise, source, niveau, pays, statut, dates de publication et tri. La catégorie de
/// source est fixée par le sous-onglet (offres d'emploi ou missions freelance).
class JobFiltersSheet extends ConsumerStatefulWidget {
  const JobFiltersSheet({super.key, required this.initial});

  final JobFilters initial;

  @override
  ConsumerState<JobFiltersSheet> createState() => _JobFiltersSheetState();
}

class _JobFiltersSheetState extends ConsumerState<JobFiltersSheet> {
  late final TextEditingController _search;
  late final TextEditingController _location;
  late final TextEditingController _skill;
  late final TextEditingController _company;
  late final TextEditingController _source;
  late double _minScore;
  String? _contract;
  String? _level;
  bool? _remote;
  late List<String> _countries;
  JobStatusFilter? _status;
  DateTime? _after;
  DateTime? _before;
  late JobSortField _sortBy;
  late bool _sortDesc;

  /// Change à chaque réinitialisation pour reconstruire les listes déroulantes.
  int _resetCount = 0;

  @override
  void initState() {
    super.initState();
    final f = widget.initial;
    _search = TextEditingController(text: f.search);
    _location = TextEditingController(text: f.location);
    _skill = TextEditingController(text: f.skill);
    _company = TextEditingController(text: f.company);
    _source = TextEditingController(text: f.source);
    _minScore = (f.minScore ?? 0).toDouble();
    _contract = f.contractType;
    _level = f.experienceLevel;
    _remote = f.remote;
    _countries = f.countries;
    _status = f.status;
    _after = f.publishedAfter;
    _before = f.publishedBefore;
    _sortBy = f.sortBy;
    _sortDesc = f.sortDesc;
  }

  @override
  void dispose() {
    _search.dispose();
    _location.dispose();
    _skill.dispose();
    _company.dispose();
    _source.dispose();
    super.dispose();
  }

  JobFilters _build() => JobFilters(
    search: _search.text,
    minScore: _minScore.round() > 0 ? _minScore.round() : null,
    contractType: _contract,
    remote: _remote,
    location: _location.text,
    skill: _skill.text,
    company: _company.text,
    source: _source.text,
    experienceLevel: _level,
    scope: widget.initial.scope,
    status: _status,
    publishedAfter: _after,
    publishedBefore: _before,
    sortBy: _sortBy,
    sortDesc: _sortDesc,
  ).copyWith(countries: _countries); // normalise les textes vides en null, trie les pays

  void _reset() {
    setState(() {
      for (final controller in [_search, _location, _skill, _company, _source]) {
        controller.clear();
      }
      _minScore = 0;
      _contract = null;
      _level = null;
      _remote = null;
      _countries = const [];
      _status = null;
      _after = null;
      _before = null;
      _sortBy = JobSortField.publishedAt;
      _sortDesc = true;
      _resetCount++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final contracts = ref.watch(contractTypesProvider).value ?? const <ContractType>[];
    final levels = ref.watch(experienceLevelsProvider).value ?? const <ExperienceLevel>[];
    final contractNames = {for (final c in contracts) c.code: c.name};
    final levelNames = {for (final l in levels) l.code: l.name};
    final count = _build().activeCount;

    return Column(
      children: [
        SheetHeader(
          title: count == 0 ? 'Filtres' : 'Filtres ($count)',
          trailing: TextButton(onPressed: _reset, child: const Text('Réinitialiser')),
        ),
        Expanded(
          child: ListView(
            primary: true,
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, AppSpacing.page, 24),
            children: [
              AppTextField(
                label: 'Recherche',
                controller: _search,
                hint: 'Titre, description, entreprise',
                prefixIcon: Icons.search_rounded,
                textInputAction: TextInputAction.search,
              ),
              formGap,
              const FieldLabel('Statut'),
              ChoiceChips<JobStatusFilter>(
                values: JobStatusFilter.values,
                selected: _status,
                labelOf: (s) => s.label,
                allowDeselect: true,
                onSelected: (s) => setState(() => _status = s),
              ),
              const Gap(6),
              Text(
                'Sans choix : offres nouvelles et actives, hors offres ignorées.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
              ),
              formGap,
              const FieldLabel('Pays'),
              _CountryField(
                countries: _countries,
                onTap: () async {
                  final picked = await showCountryPicker(context, _build());
                  if (picked != null && mounted) setState(() => _countries = picked);
                },
                onClear: () => setState(() => _countries = const []),
              ),
              formGap,
              SliderRow(
                label: 'Score de matching minimum',
                value: _minScore,
                divisions: 20,
                format: (v) => v.round() == 0 ? 'Tous' : '≥ ${v.round()}',
                onChanged: (v) => setState(() => _minScore = v),
              ),
              const Gap(6),
              const FieldLabel('Télétravail'),
              ChoiceChips<bool>(
                values: const [true, false],
                selected: _remote,
                labelOf: (v) => v ? 'Télétravail complet' : 'Sur site ou hybride',
                allowDeselect: true,
                onSelected: (v) => setState(() => _remote = v),
              ),
              formGap,
              KeyedSubtree(
                key: ValueKey('contract-$_resetCount-${contracts.length}'),
                child: AppDropdown<String>(
                  label: 'Type de contrat',
                  values: contractNames.keys.toList(),
                  value: contractNames.containsKey(_contract) ? _contract : null,
                  labelOf: (code) => contractNames[code] ?? code,
                  allowNull: true,
                  nullLabel: 'Tous',
                  onChanged: (v) => setState(() => _contract = v),
                ),
              ),
              formGap,
              KeyedSubtree(
                key: ValueKey('level-$_resetCount-${levels.length}'),
                child: AppDropdown<String>(
                  label: 'Niveau d\'expérience',
                  values: levelNames.keys.toList(),
                  value: levelNames.containsKey(_level) ? _level : null,
                  labelOf: (code) => levelNames[code] ?? code,
                  allowNull: true,
                  nullLabel: 'Tous',
                  onChanged: (v) => setState(() => _level = v),
                ),
              ),
              formGap,
              AppTextField(
                label: 'Lieu',
                controller: _location,
                hint: 'Ville ou pays',
                prefixIcon: Icons.place_outlined,
              ),
              formGap,
              AppTextField(
                label: 'Compétence',
                controller: _skill,
                hint: 'Ex. Python',
                prefixIcon: Icons.code_rounded,
              ),
              formGap,
              AppTextField(
                label: 'Entreprise',
                controller: _company,
                prefixIcon: Icons.business_outlined,
              ),
              formGap,
              AppTextField(
                label: 'Source',
                controller: _source,
                hint: 'Nom de la source',
                prefixIcon: Icons.public_rounded,
              ),
              formGap,
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DateField(
                      label: 'Publiée après le',
                      value: _after,
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                      onChanged: (d) => setState(() => _after = d),
                    ),
                  ),
                  const Gap(12),
                  Expanded(
                    child: DateField(
                      label: 'Publiée avant le',
                      value: _before,
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                      onChanged: (d) => setState(
                        () => _before = d == null
                            ? null
                            : DateTime(d.year, d.month, d.day, 23, 59, 59),
                      ),
                    ),
                  ),
                ],
              ),
              const Gap(28),
              const Divider(),
              const Gap(20),
              const FieldLabel('Trier par'),
              ChoiceChips<JobSortField>(
                values: JobSortField.values,
                selected: _sortBy,
                labelOf: (f) => f.label,
                onSelected: (f) => setState(() => _sortBy = f ?? _sortBy),
              ),
              const Gap(12),
              ChoiceChips<bool>(
                values: const [true, false],
                selected: _sortDesc,
                labelOf: (desc) => sortOrderLabel(_sortBy, desc),
                onSelected: (desc) => setState(() => _sortDesc = desc ?? _sortDesc),
              ),
            ],
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
                label: 'Afficher les offres',
                icon: Icons.check_rounded,
                onPressed: () => Navigator.of(context).pop(_build()),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Champ « Pays » : résumé de la sélection, ouvre la liste des pays.
class _CountryField extends StatelessWidget {
  const _CountryField({required this.countries, required this.onTap, required this.onClear});

  final List<String> countries;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: AppRadius.input,
    onTap: onTap,
    child: InputDecorator(
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.public_rounded, size: 20),
        suffixIcon: countries.isEmpty
            ? const Icon(Icons.expand_more_rounded)
            : IconButton(
                tooltip: 'Tous les pays',
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: onClear,
              ),
      ),
      child: Text(
        countries.isEmpty ? 'Tous les pays' : countries.map(countryLabel).join(', '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: countries.isEmpty ? AppColors.textTertiary : AppColors.textPrimary),
      ),
    ),
  );
}
