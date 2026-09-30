import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/enums.dart';
import '../../core/models/reference.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/form_fields.dart';
import '../../core/widgets/ui.dart';
import 'data/profile_labels.dart';
import 'data/profile_models.dart';
import 'data/profile_providers.dart';
import 'data/profile_repository.dart';
import 'widgets/profile_widgets.dart';

/// Préférences de recherche (`GET/PUT /preferences`).
class PreferencesPage extends ConsumerWidget {
  const PreferencesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(searchPreferencesProvider);
    final value = preferences.value;
    // Clé fixe : un rechargement en arrière-plan ne remplace pas la saisie en cours.
    if (value != null) return _PreferencesForm(key: const ValueKey('preferences'), initial: value);
    return Scaffold(
      appBar: AppBar(title: const Text('Préférences de recherche')),
      body: AsyncValueView<SearchPreferences>(
        value: preferences,
        onRetry: () => ref.invalidate(searchPreferencesProvider),
        data: (_) => const SizedBox.shrink(),
      ),
    );
  }
}

class _PreferencesForm extends ConsumerStatefulWidget {
  const _PreferencesForm({super.key, required this.initial});

  final SearchPreferences initial;

  @override
  ConsumerState<_PreferencesForm> createState() => _PreferencesFormState();
}

class _PreferencesFormState extends ConsumerState<_PreferencesForm> {
  late Set<String> _contracts = {...widget.initial.contractTypes};
  late Set<String> _levels = {...widget.initial.experienceLevels};
  late final List<LocationPreference> _locations = [...widget.initial.locations];
  late bool _remote = widget.initial.remote;
  late bool _hybrid = widget.initial.hybrid;
  late bool _onsite = widget.initial.onsite;
  late final _salary = TextEditingController(text: widget.initial.minimumSalary?.toString());
  late String _currency = widget.initial.currency;
  late SalaryPeriod _period = widget.initial.salaryPeriod;
  late Set<String> _languages = {...widget.initial.languages};
  late double _threshold = widget.initial.matchingThreshold.toDouble();
  late String _savedState;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _savedState = jsonEncode(_current().toUpdateJson());
  }

  @override
  void dispose() {
    _salary.dispose();
    super.dispose();
  }

  SearchPreferences _current() => SearchPreferences(
    contractTypes: _contracts.toList(),
    experienceLevels: _levels.toList(),
    locations: _locations,
    remote: _remote,
    hybrid: _hybrid,
    onsite: _onsite,
    minimumSalary: int.tryParse(_salary.text.trim()),
    currency: _currency,
    salaryPeriod: _period,
    languages: _languages.toList()..sort(),
    matchingThreshold: _threshold.round(),
  );

  bool get _hasChanges => jsonEncode(_current().toUpdateJson()) != _savedState;

  Future<void> _onPop() async {
    if (_saving) return;
    if (!_hasChanges || await confirmDiscard(context)) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_remote && !_hybrid && !_onsite) {
      showToast('Choisissez au moins un mode de travail.', kind: ToastKind.error);
      return;
    }
    setState(() => _saving = true);
    final repository = ref.read(profileRepositoryProvider);
    final preferences = _current();
    try {
      await ref.read(searchPreferencesProvider.notifier).save(preferences);
      _savedState = jsonEncode(preferences.toUpdateJson());
      showSavedWithRecalculate('Préférences enregistrées', repository);
    } catch (error) {
      showError(error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addLocation() async {
    final location = await showAppSheet<LocationPreference>(
      context,
      builder: (_) => const _LocationSheet(),
    );
    if (location == null || _locations.contains(location)) return;
    setState(() => _locations.add(location));
  }

  Future<void> _addLanguage() async {
    final code = await promptText(
      context,
      title: 'Autre langue',
      label: 'Code ISO à 2 lettres (ex. de, it)',
      confirmLabel: 'Ajouter',
    );
    final value = code?.trim().toLowerCase() ?? '';
    if (value.isEmpty) return;
    if (!RegExp(r'^[a-z]{2,3}$').hasMatch(value)) {
      showToast('Code de langue invalide (2 ou 3 lettres, ex. « de »).', kind: ToastKind.error);
      return;
    }
    setState(() => _languages = {..._languages, value});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final contractTypes = ref.watch(contractTypesProvider);
    final levels = ref.watch(experienceLevelsProvider);
    final hint = theme.bodySmall?.copyWith(color: AppColors.textTertiary);
    final languageCodes = {
      ...kLanguages.keys.take(kCommonLanguageCount),
      ..._languages,
    }.toList();
    final currencies = [...kCurrencies, if (!kCurrencies.contains(_currency)) _currency];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onPop();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Préférences de recherche')),
        bottomNavigationBar: BottomActionBar(
          children: [
            PrimaryButton(
              label: 'Enregistrer',
              icon: Icons.check_rounded,
              loading: _saving,
              onPressed: _save,
            ),
          ],
        ),
        body: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.xxl),
          child: PageBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const IntroText(
                  'Ces critères filtrent et notent les offres collectées. '
                  'Pensez à recalculer vos scores après une modification.',
                ),
                const _TargetsCard(),

                const SectionHeader('Types de contrat'),
                _ReferenceChips<ContractType>(
                  value: contractTypes,
                  onRetry: () => ref.invalidate(contractTypesProvider),
                  builder: (types) {
                    final active = types.where((t) => t.isActive || _contracts.contains(t.code));
                    final codes = [
                      ...active.map((t) => t.code),
                      ..._contracts.where((c) => !types.any((t) => t.code == c)),
                    ];
                    return MultiChoiceChips<String>(
                      values: codes,
                      selected: _contracts,
                      labelOf: (code) => types
                          .firstWhere(
                            (t) => t.code == code,
                            orElse: () => ContractType(id: code, code: code, name: code.toUpperCase()),
                          )
                          .name,
                      onChanged: (value) => setState(() => _contracts = value),
                    );
                  },
                ),
                if (_contracts.isEmpty) ...[
                  const Gap(8),
                  Text('Aucun choix : tous les contrats conviennent.', style: hint),
                ],

                const SectionHeader('Niveau d\'expérience visé'),
                _ReferenceChips<ExperienceLevel>(
                  value: levels,
                  onRetry: () => ref.invalidate(experienceLevelsProvider),
                  builder: (items) => MultiChoiceChips<String>(
                    values: [
                      ...items.map((l) => l.code),
                      ..._levels.where((c) => !items.any((l) => l.code == c)),
                    ],
                    selected: _levels,
                    labelOf: (code) => experienceLevelName(code, items),
                    onChanged: (value) => setState(() => _levels = value),
                  ),
                ),

                SectionHeader(
                  'Lieux souhaités',
                  trailing: Text('${_locations.length}/20', style: hint),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final location in _locations)
                      InputChip(
                        avatar: const Icon(Icons.place_outlined, size: 16),
                        label: Text(location.label),
                        deleteIcon: const Icon(Icons.close_rounded, size: 16),
                        deleteButtonTooltipMessage: 'Retirer',
                        onDeleted: () => setState(() => _locations.remove(location)),
                      ),
                    if (_locations.length < 20)
                      ActionChip(
                        avatar: const Icon(Icons.add_rounded, size: 16),
                        label: const Text('Ajouter un lieu'),
                        onPressed: _addLocation,
                      ),
                  ],
                ),
                if (_locations.isEmpty) ...[
                  const Gap(8),
                  Text('Aucun lieu : la ville et le pays de votre profil sont utilisés.', style: hint),
                ],

                const SectionHeader('Mode de travail'),
                AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 4),
                  child: Column(
                    children: [
                      SwitchRow(
                        title: 'Télétravail complet',
                        value: _remote,
                        onChanged: (v) => setState(() => _remote = v),
                      ),
                      const Divider(),
                      SwitchRow(
                        title: 'Hybride',
                        value: _hybrid,
                        onChanged: (v) => setState(() => _hybrid = v),
                      ),
                      const Divider(),
                      SwitchRow(
                        title: 'Sur site',
                        value: _onsite,
                        onChanged: (v) => setState(() => _onsite = v),
                      ),
                    ],
                  ),
                ),

                const SectionHeader('Salaire minimum'),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: AppTextField(
                        controller: _salary,
                        hint: 'Aucun minimum',
                        prefixIcon: Icons.payments_outlined,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(9),
                        ],
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      flex: 2,
                      child: AppDropdown<String>(
                        values: currencies,
                        value: _currency,
                        labelOf: (c) => c,
                        onChanged: (c) => setState(() => _currency = c ?? _currency),
                      ),
                    ),
                  ],
                ),
                const Gap(12),
                ChoiceChips<SalaryPeriod>(
                  values: SalaryPeriod.values,
                  selected: _period,
                  labelOf: salaryPeriodLabel,
                  onSelected: (p) => setState(() => _period = p ?? _period),
                ),
                const Gap(8),
                Text(
                  'Comparé au salaire des offres, converti sur l\'année. '
                  'Partagé avec votre profil.',
                  style: hint,
                ),

                const SectionHeader('Langues de travail'),
                MultiChoiceChips<String>(
                  values: languageCodes,
                  selected: _languages,
                  labelOf: languageName,
                  onChanged: (value) => setState(() => _languages = value),
                ),
                const Gap(8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _languages.length >= 10 ? null : _addLanguage,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Autre langue'),
                  ),
                ),

                const SectionHeader('Seuil d\'alerte'),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SliderRow(
                        label: 'Alerter à partir de',
                        value: _threshold,
                        divisions: 20,
                        format: (v) => '${v.round()} %',
                        onChanged: (v) => setState(() => _threshold = v),
                      ),
                      Text(
                        'Vous êtes notifié quand une nouvelle offre atteint ce score de compatibilité.',
                        style: hint,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Postes et technologies recherchés (gérés sur leurs propres écrans).
class _TargetsCard extends ConsumerWidget {
  const _TargetsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final titles = ref.watch(jobTitlesProvider).value;
    final technologies = ref.watch(technologiesProvider).value;
    return MenuGroup(
      children: [
        _TargetRow(
          icon: Icons.badge_outlined,
          title: 'Postes recherchés',
          values: titles?.where((t) => t.enabled).map((t) => t.title).toList(),
          empty: 'Aucun poste actif',
          onTap: () => context.push(Routes.jobTitles),
        ),
        _TargetRow(
          icon: Icons.memory_outlined,
          title: 'Technologies recherchées',
          values: technologies?.where((t) => t.enabled).map((t) => t.technology).toList(),
          empty: 'Aucune technologie active',
          onTap: () => context.push(Routes.technologies),
        ),
      ],
    );
  }
}

class _TargetRow extends StatelessWidget {
  const _TargetRow({
    required this.icon,
    required this.title,
    required this.values,
    required this.empty,
    required this.onTap,
  });

  static const _maxPills = 6;

  final IconData icon;
  final String title;
  final List<String>? values;
  final String empty;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final items = values;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 14, AppSpacing.sm, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 19, color: AppColors.textSecondary),
            const Gap(14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.bodyLarge?.copyWith(fontWeight: FontWeight.w500)),
                  const Gap(8),
                  if (items == null)
                    Text('Chargement…', style: theme.bodySmall)
                  else if (items.isEmpty)
                    Text(empty, style: theme.bodySmall?.copyWith(color: AppColors.textTertiary))
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final value in items.take(_maxPills)) Pill(value, dense: true),
                        if (items.length > _maxPills)
                          Pill('+${items.length - _maxPills}', dense: true, filled: false),
                      ],
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// Pastilles alimentées par un référentiel (chargement / erreur discrets).
class _ReferenceChips<T> extends StatelessWidget {
  const _ReferenceChips({required this.value, required this.builder, required this.onRetry});

  final AsyncValue<List<T>> value;
  final Widget Function(List<T> items) builder;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final items = value.value;
    if (items != null) return builder(items);
    if (value.hasError) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Impossible de charger la liste. Réessayer'),
        ),
      );
    }
    return const LoadingView(padding: EdgeInsets.symmetric(vertical: 12));
  }
}

/// Saisie d'un lieu (ville et/ou pays).
class _LocationSheet extends StatefulWidget {
  const _LocationSheet();

  @override
  State<_LocationSheet> createState() => _LocationSheetState();
}

class _LocationSheetState extends State<_LocationSheet> {
  final _city = TextEditingController();
  final _country = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _city.dispose();
    _country.dispose();
    super.dispose();
  }

  void _submit() {
    final city = _city.text.trim();
    final country = _country.text.trim();
    if (city.isEmpty && country.isEmpty) {
      setState(() => _error = 'Indiquez au moins une ville ou un pays.');
      return;
    }
    Navigator.of(context).pop(
      LocationPreference(city: city.isEmpty ? null : city, country: country.isEmpty ? null : country),
    );
  }

  @override
  Widget build(BuildContext context) => FormSheet(
    title: 'Ajouter un lieu',
    actions: [
      OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
      FilledButton(onPressed: _submit, child: const Text('Ajouter')),
    ],
    children: [
      AppTextField(
        label: 'Ville',
        controller: _city,
        hint: 'Antananarivo',
        autofocus: true,
        textInputAction: TextInputAction.next,
        inputFormatters: [LengthLimitingTextInputFormatter(100)],
      ),
      formGap,
      AppTextField(
        label: 'Pays',
        controller: _country,
        hint: 'Madagascar',
        textInputAction: TextInputAction.done,
        inputFormatters: [LengthLimitingTextInputFormatter(100)],
        onSubmitted: (_) => _submit(),
      ),
      const Gap(8),
      Text(
        'Une ville seule, un pays seul (tout le pays) ou les deux.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
      ),
      if (_error != null) ...[const Gap(12), InlineError(message: _error!)],
    ],
  );
}
