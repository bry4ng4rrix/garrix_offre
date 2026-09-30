import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/reference.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/ui.dart';
import '../data/admin_providers.dart';
import '../data/admin_repository.dart';
import 'admin_ui.dart';

/// Formulaires des référentiels (types de contrat, niveaux, catégories, catalogue).
/// Chaque formulaire renvoie `true` après un enregistrement ou une suppression.

/// Rafraîchit les listes de référence utilisées dans toute l'application.
void invalidateReferenceData(WidgetRef ref) {
  ref.invalidate(adminContractTypesProvider);
  ref.invalidate(contractTypesProvider);
  ref.invalidate(experienceLevelsProvider);
  ref.invalidate(skillCategoriesProvider);
}

/// Supprime un élément de référentiel après confirmation.
Future<bool> _confirmDelete(
  BuildContext context,
  String label,
  Future<void> Function() delete,
) async {
  final ok = await confirmDialog(
    context,
    title: 'Supprimer « $label » ?',
    message: 'Les profils et offres qui l\'utilisent ne seront plus rattachés à cette valeur.',
    confirmLabel: 'Supprimer',
    destructive: true,
  );
  if (!ok) return false;
  final done = await runAdmin(() async {
    await delete();
    return true;
  }, success: 'Supprimé');
  return done == true;
}

String? _optionalInt(String? value, {required int min, required int max}) {
  if (value == null || value.trim().isEmpty) return null;
  final n = int.tryParse(value.trim());
  if (n == null) return 'Nombre entier attendu';
  if (n < min || n > max) return 'Entre $min et $max';
  return null;
}

String? _requiredInt(String? value, {required int min, required int max}) {
  if (value == null || value.trim().isEmpty) return 'Champ obligatoire';
  return _optionalInt(value, min: min, max: max);
}

String? _blank(String text) => text.trim().isEmpty ? null : text.trim();

// -----------------------------------------------------------------------------
// Types de contrat
// -----------------------------------------------------------------------------

class ContractTypeForm extends ConsumerStatefulWidget {
  const ContractTypeForm({super.key, this.item});

  final ContractType? item;

  @override
  ConsumerState<ContractTypeForm> createState() => _ContractTypeFormState();
}

class _ContractTypeFormState extends ConsumerState<ContractTypeForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.item?.name ?? '');
  late final _code = TextEditingController(text: widget.item?.code ?? '');
  late final _description = TextEditingController(text: widget.item?.description ?? '');
  late final _aliases = TextEditingController(text: widget.item?.aliases.join(', ') ?? '');
  late final _sortOrder = TextEditingController(text: '${widget.item?.sortOrder ?? 0}');
  late bool _active = widget.item?.isActive ?? true;
  bool _saving = false;

  bool get _editing => widget.item != null;

  @override
  void dispose() {
    for (final c in [_name, _code, _description, _aliases, _sortOrder]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final repo = ref.read(adminRepositoryProvider);
    final body = {
      'name': _name.text.trim(),
      'description': _blank(_description.text),
      'aliases': splitList(_aliases.text),
      'is_active': _active,
      'sort_order': int.tryParse(_sortOrder.text.trim()) ?? 0,
      if (!_editing && _blank(_code.text) != null) 'code': _blank(_code.text),
    };
    setState(() => _saving = true);
    final done = await runAdmin(() async {
      _editing
          ? await repo.updateContractType(widget.item!.id, body)
          : await repo.createContractType(body);
      return true;
    }, success: _editing ? 'Type de contrat enregistré' : 'Type de contrat créé');
    if (!mounted) return;
    setState(() => _saving = false);
    if (done == true) {
      invalidateReferenceData(ref);
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _delete() async {
    final item = widget.item!;
    final ok = await _confirmDelete(
      context,
      item.name,
      () => ref.read(adminRepositoryProvider).deleteContractType(item.id),
    );
    if (!ok || !mounted) return;
    invalidateReferenceData(ref);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => FormSheet(
    title: _editing ? 'Type de contrat' : 'Nouveau type de contrat',
    formKey: _formKey,
    saving: _saving,
    onSubmit: _submit,
    onDelete: _editing ? _delete : null,
    children: [
      AppTextField(
        label: 'Nom',
        controller: _name,
        hint: 'Ex. CDI',
        validator: Validators.required,
        maxLength: 100,
      ),
      formGap,
      AppTextField(
        label: 'Code',
        controller: _code,
        optional: !_editing,
        enabled: !_editing,
        hint: 'Déduit du nom si vide',
        helper: _editing ? 'Le code ne peut pas être modifié.' : null,
      ),
      formGap,
      AppTextField(
        label: 'Synonymes',
        controller: _aliases,
        optional: true,
        hint: 'permanent, contrat à durée indéterminée',
        helper: 'Séparés par des virgules : servent à reconnaître le contrat dans les offres.',
        maxLines: 3,
        minLines: 1,
      ),
      formGap,
      AppTextField(
        label: 'Description',
        controller: _description,
        optional: true,
        maxLines: 3,
        minLines: 1,
      ),
      formGap,
      AppTextField(
        label: 'Ordre d\'affichage',
        controller: _sortOrder,
        keyboardType: TextInputType.number,
        validator: (v) => _optionalInt(v, min: 0, max: 1000),
      ),
      const Gap(8),
      SwitchRow(
        title: 'Actif',
        subtitle: 'Un type inactif n\'est plus proposé dans les préférences.',
        value: _active,
        onChanged: (v) => setState(() => _active = v),
      ),
    ],
  );
}

// -----------------------------------------------------------------------------
// Niveaux d'expérience
// -----------------------------------------------------------------------------

class ExperienceLevelForm extends ConsumerStatefulWidget {
  const ExperienceLevelForm({super.key, this.item});

  final ExperienceLevel? item;

  @override
  ConsumerState<ExperienceLevelForm> createState() => _ExperienceLevelFormState();
}

class _ExperienceLevelFormState extends ConsumerState<ExperienceLevelForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.item?.name ?? '');
  late final _code = TextEditingController(text: widget.item?.code ?? '');
  late final _rank = TextEditingController(text: widget.item == null ? '' : '${widget.item!.rank}');
  late final _minYears = TextEditingController(text: '${widget.item?.minYears ?? 0}');
  late final _aliases = TextEditingController(text: widget.item?.aliases.join(', ') ?? '');
  late final _description = TextEditingController(text: widget.item?.description ?? '');
  bool _saving = false;

  bool get _editing => widget.item != null;

  @override
  void dispose() {
    for (final c in [_name, _code, _rank, _minYears, _aliases, _description]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final repo = ref.read(adminRepositoryProvider);
    final body = {
      'name': _name.text.trim(),
      'rank': int.parse(_rank.text.trim()),
      'min_years': int.tryParse(_minYears.text.trim()) ?? 0,
      'aliases': splitList(_aliases.text),
      'description': _blank(_description.text),
      if (!_editing) 'code': _code.text.trim(),
    };
    setState(() => _saving = true);
    final done = await runAdmin(() async {
      _editing
          ? await repo.updateExperienceLevel(widget.item!.id, body)
          : await repo.createExperienceLevel(body);
      return true;
    }, success: _editing ? 'Niveau enregistré' : 'Niveau créé');
    if (!mounted) return;
    setState(() => _saving = false);
    if (done == true) {
      invalidateReferenceData(ref);
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _delete() async {
    final item = widget.item!;
    final ok = await _confirmDelete(
      context,
      item.name,
      () => ref.read(adminRepositoryProvider).deleteExperienceLevel(item.id),
    );
    if (!ok || !mounted) return;
    invalidateReferenceData(ref);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => FormSheet(
    title: _editing ? 'Niveau d\'expérience' : 'Nouveau niveau',
    formKey: _formKey,
    saving: _saving,
    onSubmit: _submit,
    onDelete: _editing ? _delete : null,
    children: [
      AppTextField(
        label: 'Nom',
        controller: _name,
        hint: 'Ex. Confirmé',
        validator: Validators.required,
        maxLength: 100,
      ),
      formGap,
      AppTextField(
        label: 'Code',
        controller: _code,
        enabled: !_editing,
        hint: 'Ex. senior',
        helper: _editing ? 'Le code ne peut pas être modifié.' : null,
        validator: _editing ? null : Validators.required,
        maxLength: 40,
      ),
      formGap,
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: AppTextField(
              label: 'Rang',
              controller: _rank,
              hint: '0 à 100',
              keyboardType: TextInputType.number,
              validator: (v) => _requiredInt(v, min: 0, max: 100),
            ),
          ),
          const Gap(12),
          Expanded(
            child: AppTextField(
              label: 'Années minimum',
              controller: _minYears,
              keyboardType: TextInputType.number,
              validator: (v) => _optionalInt(v, min: 0, max: 60),
            ),
          ),
        ],
      ),
      formGap,
      AppTextField(
        label: 'Synonymes',
        controller: _aliases,
        optional: true,
        hint: 'senior, expérimenté',
        helper: 'Séparés par des virgules.',
        maxLines: 3,
        minLines: 1,
      ),
      formGap,
      AppTextField(
        label: 'Description',
        controller: _description,
        optional: true,
        maxLines: 3,
        minLines: 1,
      ),
    ],
  );
}

// -----------------------------------------------------------------------------
// Catégories de compétences
// -----------------------------------------------------------------------------

class SkillCategoryForm extends ConsumerStatefulWidget {
  const SkillCategoryForm({super.key, this.item});

  final SkillCategory? item;

  @override
  ConsumerState<SkillCategoryForm> createState() => _SkillCategoryFormState();
}

class _SkillCategoryFormState extends ConsumerState<SkillCategoryForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.item?.name ?? '');
  late final _code = TextEditingController(text: widget.item?.code ?? '');
  late final _description = TextEditingController(text: widget.item?.description ?? '');
  bool _saving = false;

  bool get _editing => widget.item != null;

  @override
  void dispose() {
    for (final c in [_name, _code, _description]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final repo = ref.read(adminRepositoryProvider);
    final body = {
      'name': _name.text.trim(),
      'description': _blank(_description.text),
      if (!_editing) 'code': _code.text.trim(),
    };
    setState(() => _saving = true);
    final done = await runAdmin(() async {
      _editing
          ? await repo.updateSkillCategory(widget.item!.id, body)
          : await repo.createSkillCategory(body);
      return true;
    }, success: _editing ? 'Catégorie enregistrée' : 'Catégorie créée');
    if (!mounted) return;
    setState(() => _saving = false);
    if (done == true) {
      invalidateReferenceData(ref);
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _delete() async {
    final item = widget.item!;
    final ok = await _confirmDelete(
      context,
      item.name,
      () => ref.read(adminRepositoryProvider).deleteSkillCategory(item.id),
    );
    if (!ok || !mounted) return;
    invalidateReferenceData(ref);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => FormSheet(
    title: _editing ? 'Catégorie' : 'Nouvelle catégorie',
    formKey: _formKey,
    saving: _saving,
    expand: false,
    onSubmit: _submit,
    onDelete: _editing ? _delete : null,
    children: [
      AppTextField(
        label: 'Nom',
        controller: _name,
        hint: 'Ex. Backend',
        validator: Validators.required,
        maxLength: 100,
      ),
      formGap,
      AppTextField(
        label: 'Code',
        controller: _code,
        enabled: !_editing,
        hint: 'Ex. backend',
        helper: _editing
            ? 'Le code ne peut pas être modifié.'
            : 'Identifiant technique, en minuscules.',
        validator: _editing ? null : Validators.required,
        maxLength: 50,
      ),
      formGap,
      AppTextField(
        label: 'Description',
        controller: _description,
        optional: true,
        maxLines: 3,
        minLines: 1,
      ),
    ],
  );
}

// -----------------------------------------------------------------------------
// Catalogue de compétences
// -----------------------------------------------------------------------------

/// Modification d'une compétence du catalogue (catégorie et synonymes). Renvoie la
/// compétence enregistrée.
class CatalogSkillForm extends ConsumerStatefulWidget {
  const CatalogSkillForm({super.key, required this.skill});

  final CatalogSkill skill;

  @override
  ConsumerState<CatalogSkillForm> createState() => _CatalogSkillFormState();
}

class _CatalogSkillFormState extends ConsumerState<CatalogSkillForm> {
  final _formKey = GlobalKey<FormState>();
  late final _aliases = TextEditingController(text: widget.skill.aliases.join(', '));
  late String? _category = widget.skill.category;
  bool _saving = false;

  @override
  void dispose() {
    _aliases.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    final saved = await runAdmin(
      () => ref
          .read(adminRepositoryProvider)
          .updateCatalogSkill(
            widget.skill.id,
            category: _category,
            aliases: splitList(_aliases.text),
          ),
      success: 'Compétence enregistrée',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (saved != null) Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(skillCategoriesProvider).value ?? const <SkillCategory>[];
    final codes = categories.map((c) => c.code).toList();
    // Catégorie inconnue de la liste : on la garde sélectionnable.
    if (_category != null && !codes.contains(_category)) codes.add(_category!);
    String labelOf(String code) =>
        categories.where((c) => c.code == code).map((c) => c.name).firstOrNull ?? code;

    return FormSheet(
      title: widget.skill.name,
      subtitle: 'Compétence du catalogue partagé.',
      formKey: _formKey,
      saving: _saving,
      expand: false,
      onSubmit: _submit,
      children: [
        AppDropdown<String>(
          key: ValueKey('cat-${codes.length}'),
          label: 'Catégorie',
          optional: true,
          values: codes,
          value: _category,
          labelOf: labelOf,
          allowNull: true,
          nullLabel: 'Sans catégorie',
          onChanged: (v) => setState(() => _category = v),
        ),
        formGap,
        AppTextField(
          label: 'Synonymes',
          controller: _aliases,
          optional: true,
          hint: 'js, ecmascript',
          helper: 'Séparés par des virgules : servent à reconnaître la compétence dans les offres.',
          maxLines: 3,
          minLines: 1,
        ),
      ],
    );
  }
}
