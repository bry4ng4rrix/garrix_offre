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

/// Mes compétences (`/skills`), groupées par catégorie.
class SkillsPage extends ConsumerWidget {
  const SkillsPage({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(profileSkillsProvider);
    try {
      await ref.read(profileSkillsProvider.future);
    } catch (_) {
      // Erreur affichée par la page.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skills = ref.watch(profileSkillsProvider);
    final categories = ref.watch(skillCategoriesProvider).value ?? const <SkillCategory>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Compétences')),
      floatingActionButton: skills.hasValue
          ? FloatingActionButton.extended(
              onPressed: () => openSkillSheet(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Ajouter'),
            )
          : null,
      body: AsyncValueView<List<ProfileSkill>>(
        value: skills,
        onRetry: () => ref.invalidate(profileSkillsProvider),
        data: (items) {
          if (items.isEmpty) {
            return PageListView(
              onRefresh: () => _refresh(ref),
              children: [
                EmptyState(
                  icon: Icons.psychology_outlined,
                  title: 'Aucune compétence',
                  message: 'Ajoutez ce que vous savez faire : elles sont comparées '
                      'aux compétences demandées par chaque offre.',
                  actionLabel: 'Ajouter une compétence',
                  onAction: () => openSkillSheet(context),
                ),
              ],
            );
          }
          final groups = <String, List<ProfileSkill>>{};
          for (final skill in items) {
            groups.putIfAbsent(skill.category ?? 'other', () => []).add(skill);
          }
          final keys = groups.keys.toList()
            ..sort((a, b) => categoryOrder(a, categories).compareTo(categoryOrder(b, categories)));
          final active = items.where((s) => s.enabled).length;

          return PageListView(
            onRefresh: () => _refresh(ref),
            children: [
              IntroText(
                '${items.length} compétence${items.length > 1 ? 's' : ''}, '
                '$active prise${active > 1 ? 's' : ''} en compte. Un niveau avancé ou expert '
                'est pleinement reconnu ; désactivez une compétence pour l\'ignorer sans la supprimer.',
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
                        _SkillRow(skill: groups[key]![i]),
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

class _SkillRow extends ConsumerWidget {
  const _SkillRow({required this.skill});

  final ProfileSkill skill;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ToggleListRow(
    title: skill.name,
    enabled: skill.enabled,
    onTap: () => openSkillSheet(context, skill: skill),
    onToggle: (value) =>
        runAction(() => ref.read(profileSkillsProvider.notifier).setEnabled(skill, value)),
    details: [
      LevelMeter(level: skill.level, dimmed: !skill.enabled),
      if (skill.yearsExperience != null && skill.yearsExperience! > 0)
        DetailText(yearsLabel(skill.yearsExperience!)),
      if (skill.priority != Priority.medium) PriorityPill(priority: skill.priority),
    ],
  );
}

/// Ouvre la feuille d'ajout (sans [skill]) ou de modification d'une compétence.
Future<void> openSkillSheet(BuildContext context, {ProfileSkill? skill}) =>
    showAppSheet<void>(context, builder: (_) => _SkillSheet(skill: skill));

class _SkillSheet extends ConsumerStatefulWidget {
  const _SkillSheet({this.skill});

  final ProfileSkill? skill;

  @override
  ConsumerState<_SkillSheet> createState() => _SkillSheetState();
}

class _SkillSheetState extends ConsumerState<_SkillSheet> {
  late String? _name = widget.skill?.name;
  late String? _category = widget.skill?.category;
  late SkillLevel _level = widget.skill?.level ?? SkillLevel.intermediate;
  late Priority _priority = widget.skill?.priority ?? Priority.medium;
  late bool _enabled = widget.skill?.enabled ?? true;
  late final _years = TextEditingController(
    text: widget.skill?.yearsExperience == null
        ? ''
        : _formatYears(widget.skill!.yearsExperience!),
  );
  bool _saving = false;
  String? _error;

  bool get _editing => widget.skill != null;

  static String _formatYears(double years) =>
      years == years.roundToDouble() ? years.round().toString() : years.toString().replaceAll('.', ',');

  @override
  void dispose() {
    _years.dispose();
    super.dispose();
  }

  double? get _yearsValue => double.tryParse(_years.text.trim().replaceAll(',', '.'));

  Future<void> _submit() async {
    final years = _yearsValue;
    if (_years.text.trim().isNotEmpty && (years == null || years < 0 || years > 60)) {
      setState(() => _error = 'Années de pratique : un nombre entre 0 et 60.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final notifier = ref.read(profileSkillsProvider.notifier);
    try {
      if (_editing) {
        await notifier.edit(widget.skill!.id, {
          'level': _level.apiValue,
          'years_experience': years,
          'priority': _priority.apiValue,
          'enabled': _enabled,
          // La catégorie est portée par le catalogue : envoyée seulement si elle change.
          if (_category != null && _category != widget.skill!.category) 'category': _category,
        });
      } else {
        await notifier.add({
          'name': _name,
          'category': _category,
          'level': _level.apiValue,
          'years_experience': years,
          'priority': _priority.apiValue,
          'enabled': _enabled,
        });
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      showToast(_editing ? 'Compétence mise à jour' : '« $_name » ajoutée', kind: ToastKind.success);
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
    final skill = widget.skill!;
    final confirmed = await confirmDialog(
      context,
      title: 'Retirer « ${skill.name} » ?',
      message: 'La compétence sera retirée de votre profil.',
      confirmLabel: 'Retirer',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(profileSkillsProvider.notifier).remove(skill.id);
      if (!mounted) return;
      Navigator.of(context).pop();
      showToast('Compétence retirée', kind: ToastKind.success);
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

    // Étape 1 (ajout) : choisir la compétence dans le catalogue ou en saisie libre.
    if (_name == null) {
      final existing = (ref.read(profileSkillsProvider).value ?? const <ProfileSkill>[])
          .map((s) => s.name.toLowerCase())
          .toSet();
      return FormSheet(
        title: 'Ajouter une compétence',
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
        ],
        children: [
          CatalogSearchPanel(
            existing: existing,
            onSelected: (name, category) => setState(() {
              _name = name;
              _category = category;
              _error = null;
            }),
          ),
        ],
      );
    }

    // Étape 2 : niveau, années, priorité, catégorie.
    final categoryCodes = [
      ...categories.map((c) => c.code),
      if (_category != null && !categories.any((c) => c.code == _category)) _category!,
    ];
    return FormSheet(
      title: _editing ? 'Modifier la compétence' : 'Ajouter une compétence',
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
        const FieldLabel('Niveau'),
        LevelSelector(value: _level, onChanged: (l) => setState(() => _level = l)),
        formGap,
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AppTextField(
                label: 'Années de pratique',
                controller: _years,
                optional: true,
                hint: 'ex. 3',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  LengthLimitingTextInputFormatter(4),
                ],
              ),
            ),
            const Gap(12),
            Expanded(
              child: AppDropdown<String>(
                label: 'Catégorie',
                values: categoryCodes,
                value: _category,
                allowNull: !_editing || widget.skill!.category == null,
                nullLabel: 'Non classée',
                labelOf: (code) => categoryLabel(code, categories),
                onChanged: (code) => setState(() => _category = code),
              ),
            ),
          ],
        ),
        formGap,
        const FieldLabel('Priorité'),
        PrioritySelector(value: _priority, onChanged: (p) => setState(() => _priority = p)),
        const Gap(8),
        SwitchRow(
          title: 'Prise en compte dans le matching',
          subtitle: 'Désactivée, la compétence est ignorée sans être supprimée.',
          value: _enabled,
          onChanged: (v) => setState(() => _enabled = v),
        ),
        if (_error != null) ...[const Gap(12), InlineError(message: _error!)],
      ],
    );
  }
}
