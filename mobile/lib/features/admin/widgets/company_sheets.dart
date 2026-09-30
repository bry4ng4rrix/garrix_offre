import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/paginated.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/ui.dart';
import '../data/admin_labels.dart';
import '../data/admin_providers.dart';
import '../data/admin_repository.dart';
import '../data/directory_models.dart';
import 'admin_ui.dart';

/// Résultat d'une feuille entreprise : modifiée ou supprimée.
sealed class CompanyChange {
  const CompanyChange();
}

class CompanyUpdated extends CompanyChange {
  const CompanyUpdated(this.company);
  final Company company;
}

class CompanyDeleted extends CompanyChange {
  const CompanyDeleted(this.id);
  final String id;
}

/// Ouvre le formulaire (création si [company] est null). Renvoie l'entreprise enregistrée.
Future<Company?> showCompanyForm(BuildContext context, {Company? company}) => showAppSheet<Company>(
  context,
  expand: true,
  builder: (_) => CompanyFormSheet(company: company),
);

/// Supprime une entreprise après confirmation. Renvoie true si supprimée.
Future<bool> deleteCompany(BuildContext context, WidgetRef ref, Company company) async {
  final ok = await confirmDialog(
    context,
    title: 'Supprimer « ${company.name} » ?',
    message: 'Les offres et recruteurs liés sont conservés mais ne seront plus rattachés.',
    confirmLabel: 'Supprimer',
    destructive: true,
  );
  if (!ok) return false;
  final done = await runAdmin(() async {
    await ref.read(adminRepositoryProvider).deleteCompany(company.id);
    return true;
  }, success: 'Entreprise supprimée');
  if (done == true) ref.invalidate(companyByIdProvider(company.id));
  return done == true;
}

/// Fiche complète d'une entreprise (avec la provenance des champs collectés).
class CompanyDetailSheet extends ConsumerStatefulWidget {
  const CompanyDetailSheet({super.key, required this.company, required this.onChanged});

  final Company company;
  final ValueChanged<CompanyChange> onChanged;

  @override
  ConsumerState<CompanyDetailSheet> createState() => _CompanyDetailSheetState();
}

class _CompanyDetailSheetState extends ConsumerState<CompanyDetailSheet> {
  late Company _company = widget.company;

  Future<void> _edit() async {
    final saved = await showCompanyForm(context, company: _company);
    if (saved == null || !mounted) return;
    setState(() => _company = saved);
    widget.onChanged(CompanyUpdated(saved));
  }

  Future<void> _delete() async {
    if (!await deleteCompany(context, ref, _company)) return;
    widget.onChanged(CompanyDeleted(_company.id));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final c = _company;
    final address = [
      c.address,
      [c.postalCode, c.city].whereType<String>().where((e) => e.trim().isNotEmpty).join(' '),
      c.country,
    ].whereType<String>().where((e) => e.trim().isNotEmpty).join(', ');

    InfoRow link(IconData icon, String label, String? url) => InfoRow(
      icon: icon,
      label: label,
      value: url,
      onTap: url == null ? null : () => openLink(url),
    );

    return DetailSheet(
      title: 'Entreprise',
      actions: [
        PrimaryButton(
          label: 'Supprimer',
          icon: Icons.delete_outline_rounded,
          outlined: true,
          onPressed: _delete,
        ),
        PrimaryButton(label: 'Modifier', icon: Icons.edit_outlined, onPressed: _edit),
      ],
      children: [
        Row(
          children: [
            AppAvatar(label: c.name, imageUrl: c.logoUrl, size: 52),
            const Gap(14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.name, style: theme.headlineSmall),
                  if (c.subtitle != null) ...[
                    const Gap(2),
                    Text(
                      c.subtitle!,
                      style: theme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (c.description != null && c.description!.trim().isNotEmpty) ...[
          const Gap(16),
          Text(
            c.description!,
            style: theme.bodyMedium?.copyWith(color: AppColors.textSecondary, height: 1.45),
          ),
        ],
        const SheetSection('Coordonnées'),
        link(Icons.language_rounded, 'Site web', c.website),
        InfoRow(
          icon: Icons.mail_outline_rounded,
          label: 'Email',
          value: c.email,
          onTap: c.email == null ? null : () => openLink('mailto:${c.email}'),
        ),
        InfoRow(
          icon: Icons.phone_outlined,
          label: 'Téléphone',
          value: c.phone,
          onTap: c.phone == null ? null : () => openLink('tel:${c.phone}'),
        ),
        InfoRow(icon: Icons.place_outlined, label: 'Adresse', value: address),
        InfoRow(icon: Icons.groups_outlined, label: 'Effectif', value: c.employeeCount),
        if (c.linkedinUrl != null) link(Icons.link_rounded, 'LinkedIn', c.linkedinUrl),
        if (c.facebookUrl != null) link(Icons.link_rounded, 'Facebook', c.facebookUrl),
        if (c.instagramUrl != null) link(Icons.link_rounded, 'Instagram', c.instagramUrl),
        const SheetSection('Provenance'),
        InfoRow(
          icon: Icons.input_rounded,
          label: 'Origine',
          value: c.dataSource?.label ?? c.dataSourceValue,
        ),
        if (c.sourceId != null)
          InfoRow(
            icon: Icons.rss_feed_rounded,
            label: 'Source',
            value: 'Voir la source',
            onTap: () {
              Navigator.of(context).pop();
              context.push(Routes.adminSource(c.sourceId!));
            },
          ),
        if (c.sourceUrl != null) link(Icons.public_rounded, 'Page source', c.sourceUrl),
        if (c.fieldSources.isNotEmpty) ...[
          const Gap(8),
          Text(
            'Champs collectés',
            style: theme.labelMedium?.copyWith(color: AppColors.textSecondary),
          ),
          const Gap(6),
          for (final entry in c.fieldSources.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(
                      companyFieldLabel(entry.key),
                      style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
                    ),
                  ),
                  Expanded(
                    child: SelectableText(
                      '${entry.value}',
                      style: theme.bodySmall?.copyWith(color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
        ],
        const Gap(8),
        Text(
          'Créée le ${Fmt.date(c.createdAt)} · modifiée ${Fmt.relative(c.updatedAt)}',
          style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
        ),
      ],
    );
  }
}

/// Formulaire d'une entreprise (`CompanyCreate` / `CompanyUpdate`).
///
/// En modification, seuls les champs changés sont envoyés : la provenance des autres
/// champs collectés est conservée par le serveur.
class CompanyFormSheet extends ConsumerStatefulWidget {
  const CompanyFormSheet({super.key, this.company});

  final Company? company;

  @override
  ConsumerState<CompanyFormSheet> createState() => _CompanyFormSheetState();
}

class _CompanyFormSheetState extends ConsumerState<CompanyFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _fields;
  bool _saving = false;

  bool get _editing => widget.company != null;

  @override
  void initState() {
    super.initState();
    final values = widget.company?.editableValues ?? const <String, String?>{};
    _fields = {
      for (final key in const [
        'name',
        'website',
        'logo_url',
        'description',
        'industry',
        'employee_count',
        'address',
        'postal_code',
        'city',
        'country',
        'email',
        'phone',
        'linkedin_url',
        'facebook_url',
        'instagram_url',
        'source_url',
      ])
        key: TextEditingController(text: values[key] ?? ''),
    };
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final edited = {for (final e in _fields.entries) e.key: e.value.text};
    final repo = ref.read(adminRepositoryProvider);
    Map<String, dynamic> body;
    if (_editing) {
      body = changedFields(widget.company!.editableValues, edited);
      if (body.isEmpty) {
        Navigator.of(context).pop();
        return;
      }
    } else {
      body = filledFields(edited);
    }
    setState(() => _saving = true);
    final saved = await runAdmin(
      () => _editing ? repo.updateCompany(widget.company!.id, body) : repo.createCompany(body),
      success: _editing ? 'Entreprise enregistrée' : 'Entreprise créée',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (saved != null) {
      ref.invalidate(companyByIdProvider(saved.id));
      Navigator.of(context).pop(saved);
    }
  }

  Widget _field(
    String key,
    String label, {
    String? hint,
    TextInputType? keyboard,
    String? Function(String?)? validator,
    int maxLines = 1,
    bool optional = true,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: AppTextField(
      label: label,
      controller: _fields[key],
      hint: hint,
      optional: optional,
      keyboardType: keyboard,
      validator: validator,
      maxLines: maxLines,
      minLines: maxLines > 1 ? 3 : null,
    ),
  );

  @override
  Widget build(BuildContext context) => FormSheet(
    title: _editing ? 'Modifier l\'entreprise' : 'Nouvelle entreprise',
    formKey: _formKey,
    saving: _saving,
    submitLabel: _editing ? 'Enregistrer' : 'Créer',
    onSubmit: _submit,
    children: [
      _field('name', 'Nom', validator: Validators.required, optional: false),
      _field('industry', 'Secteur', hint: 'Ex. Logiciel'),
      _field('description', 'Description', maxLines: 6),
      _field('employee_count', 'Effectif', hint: 'Ex. 50-200'),
      const SheetSection('Coordonnées publiques'),
      _field(
        'website',
        'Site web',
        hint: 'https://',
        keyboard: TextInputType.url,
        validator: Validators.optionalUrl,
      ),
      _field('email', 'Email', keyboard: TextInputType.emailAddress, validator: optionalEmail),
      _field('phone', 'Téléphone', keyboard: TextInputType.phone, validator: optionalPhone),
      _field('address', 'Adresse'),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: _field('postal_code', 'Code postal')),
          const Gap(12),
          Expanded(child: _field('city', 'Ville')),
        ],
      ),
      _field('country', 'Pays'),
      const SheetSection('Liens'),
      _field(
        'logo_url',
        'Logo (URL)',
        keyboard: TextInputType.url,
        validator: Validators.optionalUrl,
      ),
      _field(
        'linkedin_url',
        'LinkedIn',
        keyboard: TextInputType.url,
        validator: Validators.optionalUrl,
      ),
      _field(
        'facebook_url',
        'Facebook',
        keyboard: TextInputType.url,
        validator: Validators.optionalUrl,
      ),
      _field(
        'instagram_url',
        'Instagram',
        keyboard: TextInputType.url,
        validator: Validators.optionalUrl,
      ),
      _field(
        'source_url',
        'Page publique d\'où viennent les informations',
        keyboard: TextInputType.url,
        validator: Validators.optionalUrl,
      ),
    ],
  );
}

/// Choix d'une entreprise (recherche). Renvoie `(company: null)` pour « aucune ».
Future<({Company? company})?> pickCompany(BuildContext context, {bool allowNone = true}) =>
    showAppSheet<({Company? company})>(
      context,
      expand: true,
      builder: (_) => _CompanyPickerSheet(allowNone: allowNone),
    );

class _CompanyPickerSheet extends ConsumerStatefulWidget {
  const _CompanyPickerSheet({required this.allowNone});

  final bool allowNone;

  @override
  ConsumerState<_CompanyPickerSheet> createState() => _CompanyPickerSheetState();
}

class _CompanyPickerSheetState extends ConsumerState<_CompanyPickerSheet> {
  String _search = '';
  late Future<Paginated<Company>> _results = _load();

  Future<Paginated<Company>> _load() =>
      ref.read(adminRepositoryProvider).companies(search: _search, pageSize: 40);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SheetHeader(title: 'Choisir une entreprise'),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, 4, AppSpacing.page, 8),
          child: SearchField(
            hint: 'Nom de l\'entreprise',
            onChanged: (value) => setState(() {
              _search = value;
              _results = _load();
            }),
          ),
        ),
        Expanded(
          child: FutureBuilder<Paginated<Company>>(
            future: _results,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return ErrorState(
                  error: snapshot.error!,
                  onRetry: () => setState(() => _results = _load()),
                );
              }
              if (!snapshot.hasData) return const LoadingView();
              final items = snapshot.data!.items;
              return ListView(
                primary: true,
                padding: const EdgeInsets.fromLTRB(AppSpacing.page, 4, AppSpacing.page, 24),
                children: [
                  if (widget.allowNone)
                    ListTile(
                      leading: const Icon(Icons.block_rounded),
                      title: const Text('Aucune entreprise'),
                      onTap: () => Navigator.of(context).pop((company: null)),
                    ),
                  if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Aucune entreprise trouvée.',
                        textAlign: TextAlign.center,
                        style: theme.bodyMedium?.copyWith(color: AppColors.textTertiary),
                      ),
                    ),
                  for (final company in items)
                    ListTile(
                      leading: AppAvatar(label: company.name, imageUrl: company.logoUrl, size: 36),
                      title: Text(company.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: company.subtitle == null
                          ? null
                          : Text(company.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.of(context).pop((company: company)),
                    ),
                  if (snapshot.data!.total > items.length)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        '${snapshot.data!.total - items.length} autres résultats : précisez la recherche.',
                        textAlign: TextAlign.center,
                        style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
