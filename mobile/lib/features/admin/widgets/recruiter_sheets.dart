import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/ui.dart';
import '../data/admin_providers.dart';
import '../data/admin_repository.dart';
import '../data/directory_models.dart';
import 'admin_ui.dart';
import 'company_sheets.dart';

/// Nom de l'entreprise d'un recruteur (chargé à la demande, gardé en cache).
class CompanyName extends ConsumerWidget {
  const CompanyName({super.key, required this.companyId, this.style});

  final String companyId;
  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(companyByIdProvider(companyId));
    return Text(
      company.value?.name ?? (company.hasError ? 'Entreprise introuvable' : '…'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}

/// Ouvre le formulaire (création si [recruiter] est null). Renvoie le recruteur enregistré.
Future<Recruiter?> showRecruiterForm(BuildContext context, {Recruiter? recruiter}) =>
    showAppSheet<Recruiter>(
      context,
      expand: true,
      builder: (_) => RecruiterFormSheet(recruiter: recruiter),
    );

/// Fiche d'un recruteur : coordonnées publiques et leur provenance.
class RecruiterDetailSheet extends ConsumerStatefulWidget {
  const RecruiterDetailSheet({
    super.key,
    required this.recruiter,
    required this.onUpdated,
    required this.onDeleted,
  });

  final Recruiter recruiter;
  final ValueChanged<Recruiter> onUpdated;
  final VoidCallback onDeleted;

  @override
  ConsumerState<RecruiterDetailSheet> createState() => _RecruiterDetailSheetState();
}

class _RecruiterDetailSheetState extends ConsumerState<RecruiterDetailSheet> {
  late Recruiter _recruiter = widget.recruiter;

  Future<void> _edit() async {
    final saved = await showRecruiterForm(context, recruiter: _recruiter);
    if (saved == null || !mounted) return;
    setState(() => _recruiter = saved);
    widget.onUpdated(saved);
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: 'Supprimer ce recruteur ?',
      message: '« ${_recruiter.displayName} » ne sera plus rattaché aux offres.',
      confirmLabel: 'Supprimer',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final done = await runAdmin(() async {
      await ref.read(adminRepositoryProvider).deleteRecruiter(_recruiter.id);
      return true;
    }, success: 'Recruteur supprimé');
    if (done != true) return;
    widget.onDeleted();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final r = _recruiter;
    final source = r.contactSource;

    return DetailSheet(
      title: 'Recruteur',
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
            AppAvatar(label: r.displayName, size: 52),
            const Gap(14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.displayName, style: theme.headlineSmall),
                  if (r.jobTitle != null) ...[
                    const Gap(2),
                    Text(
                      r.jobTitle!,
                      style: theme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                  if (r.companyId != null) ...[
                    const Gap(2),
                    CompanyName(
                      companyId: r.companyId!,
                      style: theme.bodyMedium?.copyWith(color: AppColors.textTertiary),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SheetSection('Coordonnées publiques'),
        InfoRow(
          icon: Icons.mail_outline_rounded,
          label: 'Email',
          value: r.email,
          onTap: r.email == null ? null : () => openLink('mailto:${r.email}'),
        ),
        InfoRow(
          icon: Icons.phone_outlined,
          label: 'Téléphone',
          value: r.phone,
          onTap: r.phone == null ? null : () => openLink('tel:${r.phone}'),
        ),
        InfoRow(
          icon: Icons.link_rounded,
          label: 'LinkedIn',
          value: r.linkedinUrl,
          onTap: r.linkedinUrl == null ? null : () => openLink(r.linkedinUrl!),
        ),
        InfoRow(
          icon: Icons.language_rounded,
          label: 'Site web',
          value: r.website,
          onTap: r.website == null ? null : () => openLink(r.website!),
        ),
        const SheetSection('Provenance'),
        InfoRow(
          icon: Icons.verified_outlined,
          label: 'Origine des coordonnées',
          value: source?.label ?? r.contactSourceValue ?? 'Non renseignée',
        ),
        InfoRow(
          icon: Icons.public_rounded,
          label: 'Page source',
          value: r.sourceUrl,
          onTap: r.sourceUrl == null ? null : () => openLink(r.sourceUrl!),
        ),
        if (r.hasContact && source == null) ...[
          const Gap(8),
          const NoteBox(
            message: 'Coordonnées sans provenance : complétez-la pour respecter la règle RG-07.',
            color: AppColors.warning,
            icon: Icons.warning_amber_rounded,
          ),
        ],
        if (r.notes != null && r.notes!.trim().isNotEmpty) ...[
          const SheetSection('Notes'),
          Text(
            r.notes!,
            style: theme.bodyMedium?.copyWith(color: AppColors.textSecondary, height: 1.45),
          ),
        ],
        const Gap(16),
        Text(
          'Ajouté le ${Fmt.date(r.createdAt)} · modifié ${Fmt.relative(r.updatedAt)}',
          style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
        ),
      ],
    );
  }
}

/// Formulaire d'un recruteur (`RecruiterCreate` / `RecruiterUpdate`).
///
/// Règle serveur : toute coordonnée (email, téléphone) exige une provenance, et les
/// provenances « site de l'entreprise » / « profil public » exigent l'URL de la page.
class RecruiterFormSheet extends ConsumerStatefulWidget {
  const RecruiterFormSheet({super.key, this.recruiter});

  final Recruiter? recruiter;

  @override
  ConsumerState<RecruiterFormSheet> createState() => _RecruiterFormSheetState();
}

class _RecruiterFormSheetState extends ConsumerState<RecruiterFormSheet> {
  static const _textKeys = [
    'name',
    'first_name',
    'last_name',
    'job_title',
    'email',
    'phone',
    'linkedin_url',
    'website',
    'source_url',
    'notes',
  ];

  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _fields;
  ContactSource? _contactSource;
  String? _companyId;
  String? _companyLabel;
  String? _provenanceError;
  bool _saving = false;

  bool get _editing => widget.recruiter != null;

  @override
  void initState() {
    super.initState();
    final values = widget.recruiter?.editableValues ?? const <String, String?>{};
    _fields = {for (final key in _textKeys) key: TextEditingController(text: values[key] ?? '')};
    _contactSource = widget.recruiter?.contactSource;
    _companyId = widget.recruiter?.companyId;
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Map<String, String?> get _edited => {
    for (final key in _textKeys) key: _fields[key]!.text,
    'company_id': _companyId,
    'contact_source': _contactSource?.apiValue,
  };

  Future<void> _pickCompany() async {
    final choice = await pickCompany(context);
    if (choice == null) return;
    setState(() {
      _companyId = choice.company?.id;
      _companyLabel = choice.company?.name;
    });
  }

  Future<void> _submit() async {
    final provenance = checkContactProvenance(
      email: _fields['email']!.text,
      phone: _fields['phone']!.text,
      contactSource: _contactSource,
      sourceUrl: _fields['source_url']!.text,
    );
    setState(() => _provenanceError = provenance);
    final valid = _formKey.currentState!.validate();
    if (!valid || provenance != null) return;

    final edited = _edited;
    final hasIdentity = [
      'name',
      'first_name',
      'last_name',
      'email',
    ].any((key) => (edited[key]?.trim().isNotEmpty ?? false));
    if (!hasIdentity) {
      showToast('Indiquez au moins un nom ou un email.', kind: ToastKind.error);
      return;
    }

    final repo = ref.read(adminRepositoryProvider);
    Map<String, dynamic> body;
    if (_editing) {
      body = changedFields(widget.recruiter!.editableValues, edited);
      if (body.isEmpty) {
        Navigator.of(context).pop();
        return;
      }
    } else {
      body = filledFields(edited);
    }
    setState(() => _saving = true);
    final saved = await runAdmin(
      () =>
          _editing ? repo.updateRecruiter(widget.recruiter!.id, body) : repo.createRecruiter(body),
      success: _editing ? 'Recruteur enregistré' : 'Recruteur ajouté',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (saved != null) Navigator.of(context).pop(saved);
  }

  Widget _field(
    String key,
    String label, {
    String? hint,
    String? helper,
    TextInputType? keyboard,
    String? Function(String?)? validator,
    int maxLines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: AppTextField(
      label: label,
      controller: _fields[key],
      hint: hint,
      helper: helper,
      optional: true,
      keyboardType: keyboard,
      validator: validator,
      maxLines: maxLines,
      minLines: maxLines > 1 ? 3 : null,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final needsUrl = sourcesRequiringUrl.contains(_contactSource);

    return FormSheet(
      title: _editing ? 'Modifier le recruteur' : 'Nouveau recruteur',
      subtitle: 'Uniquement des coordonnées professionnelles publiques, avec leur provenance.',
      formKey: _formKey,
      saving: _saving,
      submitLabel: _editing ? 'Enregistrer' : 'Ajouter',
      onSubmit: _submit,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _field('first_name', 'Prénom')),
            const Gap(12),
            Expanded(child: _field('last_name', 'Nom')),
          ],
        ),
        _field(
          'name',
          'Nom affiché',
          hint: 'Ex. Équipe recrutement',
          helper: 'Laissez vide pour utiliser le prénom et le nom.',
        ),
        _field('job_title', 'Fonction', hint: 'Ex. Talent Acquisition'),
        const FieldLabel('Entreprise', optional: true),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _pickCompany,
          child: InputDecorator(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.business_outlined, size: 20),
              suffixIcon: _companyId == null
                  ? const Icon(Icons.expand_more_rounded)
                  : IconButton(
                      tooltip: 'Retirer',
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () => setState(() {
                        _companyId = null;
                        _companyLabel = null;
                      }),
                    ),
            ),
            child: _companyId == null
                ? Text('Choisir une entreprise', style: TextStyle(color: AppColors.textTertiary))
                : _companyLabel != null
                ? Text(_companyLabel!)
                : CompanyName(companyId: _companyId!),
          ),
        ),
        const SheetSection('Coordonnées'),
        _field(
          'email',
          'Email professionnel',
          keyboard: TextInputType.emailAddress,
          validator: optionalEmail,
        ),
        _field('phone', 'Téléphone', keyboard: TextInputType.phone, validator: optionalPhone),
        _field(
          'linkedin_url',
          'LinkedIn',
          keyboard: TextInputType.url,
          validator: Validators.optionalUrl,
        ),
        _field(
          'website',
          'Site web',
          keyboard: TextInputType.url,
          validator: Validators.optionalUrl,
        ),
        const SheetSection('Provenance'),
        AppDropdown<ContactSource>(
          label: 'Origine des coordonnées',
          optional: true,
          values: ContactSource.values,
          value: _contactSource,
          labelOf: (s) => s.label,
          allowNull: true,
          nullLabel: 'Non renseignée',
          onChanged: (s) => setState(() {
            _contactSource = s;
            _provenanceError = null;
          }),
        ),
        const Gap(18),
        _field(
          'source_url',
          needsUrl ? 'URL de la page source (obligatoire)' : 'URL de la page source',
          hint: 'https://',
          keyboard: TextInputType.url,
          validator: Validators.optionalUrl,
        ),
        if (_provenanceError != null) ...[
          NoteBox(
            message: _provenanceError!,
            color: AppColors.danger,
            icon: Icons.error_outline_rounded,
          ),
          const Gap(18),
        ] else ...[
          Text(
            'Un email ou un téléphone doit toujours indiquer d\'où il provient.',
            style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
          ),
          const Gap(18),
        ],
        _field('notes', 'Notes', maxLines: 5),
      ],
    );
  }
}
