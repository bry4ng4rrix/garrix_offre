import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/ui.dart';
import '../data/admin_providers.dart';
import '../data/admin_repository.dart';
import '../data/source_models.dart';
import 'admin_ui.dart';

/// Ouvre le formulaire de création ([source] null) ou de modification d'une source.
/// Renvoie la source enregistrée.
Future<Source?> showSourceForm(BuildContext context, {Source? source}) =>
    showAppSheet<Source>(context, expand: true, builder: (_) => SourceFormSheet(source: source));

/// Formulaire simplifié d'une source (`SourceCreate` / `SourceUpdate`).
class SourceFormSheet extends ConsumerStatefulWidget {
  const SourceFormSheet({super.key, this.source});

  final Source? source;

  @override
  ConsumerState<SourceFormSheet> createState() => _SourceFormSheetState();
}

class _SourceFormSheetState extends ConsumerState<SourceFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _baseUrl;
  late final TextEditingController _config;
  late final TextEditingController _rateLimit;
  late final TextEditingController _notes;
  late SourceType? _type;
  late SourceCategory _category;
  late FetchMode _fetchMode;
  String? _adapter;
  late bool _enabled;
  late bool _scrapingEnabled;
  late bool _termsReviewed;
  late double _priority;
  bool _saving = false;

  bool get _editing => widget.source != null;

  @override
  void initState() {
    super.initState();
    final s = widget.source;
    _name = TextEditingController(text: s?.name ?? '');
    _baseUrl = TextEditingController(text: s?.baseUrl ?? '');
    _config = TextEditingController(
      text: (s == null || s.configuration.isEmpty) ? '{}' : JsonBlock.format(s.configuration),
    );
    _rateLimit = TextEditingController(text: s?.rateLimit?.toString() ?? '');
    _notes = TextEditingController(text: s?.notes ?? '');
    _type = s == null ? SourceType.rss : s.type;
    _category = s?.category ?? SourceCategory.jobs;
    _fetchMode = s?.fetchMode ?? FetchMode.backend;
    _adapter = s?.adapter;
    _enabled = s?.enabled ?? true;
    _scrapingEnabled = s?.scrapingEnabled ?? false;
    _termsReviewed = s?.termsReviewed ?? false;
    _priority = (s?.priority ?? 5).toDouble();
  }

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
    _config.dispose();
    _rateLimit.dispose();
    _notes.dispose();
    super.dispose();
  }

  String? _validateConfig(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    try {
      final decoded = jsonDecode(text);
      return decoded is Map ? null : 'Un objet JSON est attendu : { ... }';
    } catch (_) {
      return 'JSON invalide';
    }
  }

  String? _validateRateLimit(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final n = int.tryParse(value.trim());
    if (n == null || n < 1 || n > 600) return 'Entre 1 et 600 requêtes par minute';
    return null;
  }

  void _insertTemplate(AdapterInfo adapter) {
    Map<String, dynamic> current = {};
    try {
      final decoded = jsonDecode(_config.text.trim().isEmpty ? '{}' : _config.text);
      if (decoded is Map) current = decoded.cast<String, dynamic>();
    } catch (_) {}
    // Les valeurs déjà saisies sont conservées.
    final merged = {...adapter.template(), ...current};
    setState(() => _config.text = JsonBlock.format(merged));
  }

  Future<void> _submit() async {
    if (_type == null) {
      showToast('Choisissez le type de source.', kind: ToastKind.error);
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    final configText = _config.text.trim();
    final configuration = configText.isEmpty
        ? <String, dynamic>{}
        : (jsonDecode(configText) as Map).cast<String, dynamic>();
    final input = SourceInput(
      name: _name.text,
      type: _type!,
      category: _category,
      fetchMode: _fetchMode,
      adapter: _adapter,
      baseUrl: _baseUrl.text,
      enabled: _enabled,
      scrapingEnabled: _scrapingEnabled,
      priority: _priority.round(),
      configuration: configuration,
      rateLimit: int.tryParse(_rateLimit.text.trim()),
      termsReviewed: _termsReviewed,
      notes: _notes.text,
    );
    setState(() => _saving = true);
    final repo = ref.read(adminRepositoryProvider);
    final saved = await runAdmin(
      () => _editing
          ? repo.updateSource(widget.source!.id, input.toJson())
          : repo.createSource(input),
      success: _editing ? 'Source enregistrée' : 'Source créée',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (saved != null) Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final adapters = ref.watch(adaptersProvider);
    final available = (adapters.value ?? const <AdapterInfo>[])
        .where((a) => a.supports(_type) || a.key == _adapter)
        .toList();
    final selected = available.where((a) => a.key == _adapter).firstOrNull;

    return FormSheet(
      title: _editing ? 'Modifier la source' : 'Nouvelle source',
      formKey: _formKey,
      saving: _saving,
      submitLabel: _editing ? 'Enregistrer' : 'Créer la source',
      onSubmit: _submit,
      children: [
        AppTextField(
          label: 'Nom',
          controller: _name,
          hint: 'Ex. Flux RSS Python',
          validator: Validators.required,
          maxLength: 150,
        ),
        formGap,
        const FieldLabel('Catégorie'),
        ChoiceChips<SourceCategory>(
          values: SourceCategory.values,
          selected: _category,
          labelOf: (c) => c.label,
          onSelected: (c) => setState(() => _category = c ?? _category),
        ),
        formGap,
        const FieldLabel('Type'),
        ChoiceChips<SourceType>(
          values: SourceType.values,
          selected: _type,
          labelOf: (t) => t.label,
          onSelected: (t) => setState(() {
            _type = t ?? _type;
            // Adapter incompatible avec le nouveau type : on le retire.
            final current = (adapters.value ?? const <AdapterInfo>[])
                .where((a) => a.key == _adapter)
                .firstOrNull;
            if (current != null && !current.supports(_type)) _adapter = null;
          }),
        ),
        formGap,
        const FieldLabel('Récupération des offres'),
        ChoiceChips<FetchMode>(
          values: FetchMode.values,
          selected: _fetchMode,
          labelOf: (m) => m == FetchMode.backend ? 'Par le serveur' : 'Par n8n',
          onSelected: (m) => setState(() => _fetchMode = m ?? _fetchMode),
        ),
        formGap,
        if (adapters.hasError)
          InlineError(error: adapters.error!, onRetry: () => ref.invalidate(adaptersProvider))
        else
          AppDropdown<String>(
            key: ValueKey('adapter-${_type?.apiValue}-${adapters.hasValue}'),
            label: 'Adapter',
            optional: true,
            values: [for (final a in available) a.key],
            value: selected?.key,
            labelOf: (key) => key,
            allowNull: true,
            nullLabel: 'Aucun (n8n, alertes email, saisie manuelle)',
            onChanged: (key) => setState(() => _adapter = key),
          ),
        if (selected != null) ...[
          const Gap(8),
          Text(
            selected.description + (selected.respectsRobotsTxt ? ' · respecte robots.txt' : ''),
            style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
          ),
        ],
        formGap,
        AppTextField(
          label: 'URL du site',
          controller: _baseUrl,
          optional: true,
          hint: 'https://exemple.com',
          keyboardType: TextInputType.url,
          validator: Validators.optionalUrl,
        ),
        formGap,
        Row(
          children: [
            const Expanded(child: FieldLabel('Configuration (JSON)')),
            if (selected != null)
              TextButton.icon(
                onPressed: () => _insertTemplate(selected),
                icon: const Icon(Icons.auto_fix_high_outlined, size: 16),
                label: const Text('Insérer un modèle'),
              ),
          ],
        ),
        TextFormField(
          controller: _config,
          minLines: 4,
          maxLines: 14,
          validator: _validateConfig,
          keyboardType: TextInputType.multiline,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.4),
          decoration: const InputDecoration(hintText: '{ }'),
        ),
        const Gap(8),
        if (selected != null && selected.fields.isNotEmpty)
          _AdapterFieldsHelp(adapter: selected)
        else
          Text(
            'Les clés secrètes ne se saisissent pas ici : elles sont lues dans le .env du serveur.',
            style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
          ),
        formGap,
        SliderRow(
          label: 'Priorité',
          value: _priority,
          min: 1,
          max: 10,
          divisions: 9,
          onChanged: (v) => setState(() => _priority = v),
        ),
        formGap,
        AppTextField(
          label: 'Limite de requêtes par minute',
          controller: _rateLimit,
          optional: true,
          hint: 'Ex. 10',
          keyboardType: TextInputType.number,
          validator: _validateRateLimit,
        ),
        const Gap(8),
        SwitchRow(
          title: 'Source active',
          value: _enabled,
          onChanged: (v) => setState(() => _enabled = v),
        ),
        SwitchRow(
          title: 'Collecte automatique',
          subtitle: 'Incluse dans les collectes planifiées.',
          value: _scrapingEnabled,
          onChanged: (v) => setState(() => _scrapingEnabled = v),
        ),
        SwitchRow(
          title: 'Conditions d\'utilisation vérifiées',
          subtitle: 'Les CGU du site autorisent la collecte automatique (obligatoire en HTML).',
          value: _termsReviewed,
          onChanged: (v) => setState(() => _termsReviewed = v),
        ),
        formGap,
        AppTextField(
          label: 'Notes',
          controller: _notes,
          optional: true,
          minLines: 2,
          maxLines: 6,
          maxLength: 5000,
        ),
      ],
    );
  }
}

/// Liste des champs de configuration attendus par l'adapter choisi.
class _AdapterFieldsHelp extends StatelessWidget {
  const _AdapterFieldsHelp({required this.adapter});

  final AdapterInfo adapter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Champs de « ${adapter.key} » (* obligatoire)',
            style: theme.labelMedium?.copyWith(color: AppColors.textSecondary),
          ),
          const Gap(6),
          for (final field in adapter.fields)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${field.name}${field.isRequired ? ' *' : ''}',
                      style: const TextStyle(fontFamily: 'monospace', color: AppColors.textPrimary),
                    ),
                    TextSpan(text: '  ${field.type}'),
                    if (field.description != null) TextSpan(text: ' — ${field.description}'),
                  ],
                ),
                style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
              ),
            ),
          const Gap(6),
          Text(
            'Les clés secrètes ne se saisissent pas ici : elles sont lues dans le .env du serveur.',
            style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}
