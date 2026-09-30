import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/enums.dart';
import '../../core/models/reference.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/form_fields.dart';
import '../../core/widgets/ui.dart';
import 'data/profile_labels.dart';
import 'data/profile_models.dart';
import 'data/profile_providers.dart';
import 'widgets/catalog_search.dart';
import 'widgets/profile_widgets.dart';

/// Technologies recherchées (`/experience-preferences`), groupées par catégorie.
class TechnologiesPage extends ConsumerWidget {
  const TechnologiesPage({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(technologiesProvider);
    try {
      await ref.read(technologiesProvider.future);
    } catch (_) {
      // Erreur affichée par la page.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final technologies = ref.watch(technologiesProvider);
    final categories = ref.watch(skillCategoriesProvider).value ?? const <SkillCategory>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Technologies recherchées')),
      floatingActionButton: technologies.hasValue
          ? FloatingActionButton.extended(
              onPressed: () => _openSheet(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Ajouter'),
            )
          : null,
      body: AsyncValueView<List<TechnologyPreference>>(
        value: technologies,
        onRetry: () => ref.invalidate(technologiesProvider),
        data: (items) {
          if (items.isEmpty) {
            return PageListView(
              onRefresh: () => _refresh(ref),
              children: [
                EmptyState(
                  icon: Icons.memory_outlined,
                  title: 'Aucune technologie recherchée',
                  message: 'Indiquez les technologies que vous voulez retrouver dans les offres '
                      '(React, Django, AWS…). Elles pèsent selon leur priorité.',
                  actionLabel: 'Ajouter une technologie',
                  onAction: () => _openSheet(context),
                ),
              ],
            );
          }
          final groups = <String, List<TechnologyPreference>>{};
          for (final item in items) {
            groups.putIfAbsent(item.category ?? 'other', () => []).add(item);
          }
          final keys = groups.keys.toList()
            ..sort((a, b) => categoryOrder(a, categories).compareTo(categoryOrder(b, categories)));

          return PageListView(
            onRefresh: () => _refresh(ref),
            children: [
              const IntroText(
                'Les technologies que vous voulez retrouver dans les offres. Plus la priorité est '
                'haute, plus elles pèsent. Une technologie obligatoire absente plafonne le score à 50 %.',
              ),
              for (final key in keys) ...[
                SectionHeader(
                  categoryLabel(key, categories),
                  trailing: Text(
                    '${groups[key]!.length}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < groups[key]!.length; i++) ...[
                        if (i > 0) const Divider(indent: AppSpacing.lg),
                        _TechnologyRow(item: groups[key]![i]),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _TechnologyRow extends ConsumerWidget {
  const _TechnologyRow({required this.item});

  final TechnologyPreference item;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ToggleListRow(
    title: item.technology,
    enabled: item.enabled,
    onTap: () => _openSheet(context, item: item),
    onToggle: (value) =>
        runAction(() => ref.read(technologiesProvider.notifier).setEnabled(item, value)),
    details: [
      LevelMeter(level: item.level, dimmed: !item.enabled),
      if (item.minYears > 0) DetailText('${yearsLabel(item.minYears)} min.'),
      if (item.isRequired)
        const Pill('Obligatoire', icon: Icons.lock_outline_rounded, color: AppColors.violet, dense: true),
      if (item.priority != Priority.medium) PriorityPill(priority: item.priority),
    ],
  );
}

Future<void> _openSheet(BuildContext context, {TechnologyPreference? item}) =>
    showAppSheet<void>(context, builder: (_) => _TechnologySheet(item: item));

class _TechnologySheet extends ConsumerStatefulWidget {
  const _TechnologySheet({this.item});

  final TechnologyPreference? item;

  @override
  ConsumerState<_TechnologySheet> createState() => _TechnologySheetState();
}

class _TechnologySheetState extends ConsumerState<_TechnologySheet> {
  late String? _name = widget.item?.technology;
  late String? _category = widget.item?.category;
  late SkillLevel _level = widget.item?.level ?? SkillLevel.intermediate;
  late Priority _priority = widget.item?.priority ?? Priority.medium;
  late bool _required = widget.item?.isRequired ?? false;
  late bool _enabled = widget.item?.enabled ?? true;
  late final _minYears = TextEditingController(
    text: (widget.item?.minYears ?? 0) > 0 ? widget.item!.minYears.toString() : '',
  );
  bool _saving = false;
  String? _error;

  bool get _editing => widget.item != null;

  @override
  void dispose() {
    _minYears.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final minYears = int.tryParse(_minYears.text.trim()) ?? 0;
    if (minYears > 60) {
      setState(() => _error = 'Années minimum : 60 au maximum.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final notifier = ref.read(technologiesProvider.notifier);
    final body = {
      'level': _level.apiValue,
      'priority': _priority.apiValue,
      'min_years': minYears,
      'is_required': _required,
      'enabled': _enabled,
    };
    try {
      if (_editing) {
        await notifier.edit(widget.item!.id, body);
      } else {
        await notifier.add({'technology': _name, 'category': _category, ...body});
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      showToast(_editing ? 'Technologie mise à jour' : '« $_name » ajoutée', kind: ToastKind.success);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = ApiException.describe(error);
        });
      }
    }
  }

  Future<void> _delete() async {
    final item = widget.item!;
    final confirmed = await confirmDialog(
      context,
      title: 'Retirer « ${item.technology} » ?',
      message: 'Elle ne sera plus recherchée dans les offres.',
      confirmLabel: 'Retirer',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(technologiesProvider.notifier).remove(item.id);
      if (!mounted) return;
      Navigator.of(context).pop();
      showToast('Technologie retirée', kind: ToastKind.success);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = ApiException.describe(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(skillCategoriesProvider).value ?? const <SkillCategory>[];

    // Étape 1 (ajout) : catalogue, saisie libre ou suggestion tirée de mes compétences.
    if (_name == null) {
      final existing = (ref.read(technologiesProvider).value ?? const <TechnologyPreference>[])
          .map((t) => t.technology.toLowerCase())
          .toSet();
      final skills = ref.watch(profileSkillsProvider).value ?? const <ProfileSkill>[];
      return FormSheet(
        title: 'Ajouter une technologie',
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
        ],
        children: [
          CatalogSearchPanel(
            existing: existing,
            existingLabel: 'Déjà suivie',
            suggestionsLabel: 'Depuis vos compétences',
            suggestions: [
              for (final skill in skills.where((s) => s.enabled))
                CatalogSuggestion(skill.name, skill.category),
            ],
            onSelected: (name, category) => setState(() {
              _name = name;
              _category = category;
              _error = null;
            }),
          ),
        ],
      );
    }

    // Étape 2 : niveau, priorité, années, obligatoire.
    final categoryCodes = [
      ...categories.map((c) => c.code),
      if (_category != null && !categories.any((c) => c.code == _category)) _category!,
    ];
    return FormSheet(
      title: _editing ? 'Modifier la technologie' : 'Ajouter une technologie',
      trailing: _editing
          ? IconButton(
              tooltip: 'Retirer',
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
            )
          : null,
      actions: [
        OutlinedButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        PrimaryButton(
          label: _editing ? 'Enregistrer' : 'Ajouter',
          loading: _saving,
          onPressed: _submit,
        ),
      ],
      children: [
        ChosenItemCard(
          name: _name!,
          subtitle: _category == null ? null : categoryLabel(_category, categories),
          onChange: _editing ? null : () => setState(() => _name = null),
        ),
        const Gap(20),
        const FieldLabel('Votre niveau'),
        LevelSelector(value: _level, onChanged: (l) => setState(() => _level = l)),
        formGap,
        const FieldLabel('Priorité'),
        PrioritySelector(value: _priority, onChanged: (p) => setState(() => _priority = p)),
        const Gap(6),
        Text(
          'Poids dans le score : basse ×1, moyenne ×2, haute ×3.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
        ),
        formGap,
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AppTextField(
                label: 'Années d\'expérience',
                controller: _minYears,
                optional: true,
                hint: '0',
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(2),
                ],
              ),
            ),
            if (!_editing) ...[
              const Gap(12),
              Expanded(
                child: AppDropdown<String>(
                  label: 'Catégorie',
                  values: categoryCodes,
                  value: _category,
                  allowNull: true,
                  nullLabel: 'Non classée',
                  labelOf: (code) => categoryLabel(code, categories),
                  onChanged: (code) => setState(() => _category = code),
                ),
              ),
            ],
          ],
        ),
        const Gap(8),
        SwitchRow(
          title: 'Obligatoire',
          subtitle: 'Absente d\'une offre, le score de celle-ci est plafonné à 50 %.',
          value: _required,
          onChanged: (v) => setState(() => _required = v),
        ),
        SwitchRow(
          title: 'Recherche active',
          subtitle: 'Désactivée, la technologie est ignorée sans être supprimée.',
          value: _enabled,
          onChanged: (v) => setState(() => _enabled = v),
        ),
        if (_error != null) ...[const Gap(12), InlineError(message: _error!)],
      ],
    );
  }
}
