import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/enums.dart';
import '../../core/models/reference.dart';
import '../../core/network/api_exception.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/form_fields.dart';
import '../../core/widgets/ui.dart';
import 'data/job_draft.dart';
import 'data/jobs_repository.dart';
import 'job_labels.dart';
import 'jobs_providers.dart';
import 'widgets/bottom_bar.dart';

/// Ajout manuel d'une offre (`POST /jobs`). L'offre suit le même pipeline que les offres
/// collectées (normalisation, déduplication, matching).
class JobFormPage extends ConsumerStatefulWidget {
  const JobFormPage({super.key});

  @override
  ConsumerState<JobFormPage> createState() => _JobFormPageState();
}

class _JobFormPageState extends ConsumerState<JobFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _url = TextEditingController();
  final _description = TextEditingController();
  final _company = TextEditingController();
  final _companyWebsite = TextEditingController();
  final _city = TextEditingController();
  final _country = TextEditingController();
  final _salaryMin = TextEditingController();
  final _salaryMax = TextEditingController();
  final _currency = TextEditingController(text: 'EUR');
  final _years = TextEditingController();
  final _skillInput = TextEditingController();
  final _applyUrl = TextEditingController();
  final _applyEmail = TextEditingController();
  final _recruiterName = TextEditingController();
  final _recruiterEmail = TextEditingController();
  final _recruiterPhone = TextEditingController();
  final _recruiterLinkedin = TextEditingController();

  bool _remote = false;
  bool _hybrid = false;
  String? _contract;
  String? _workTime;
  String? _level;
  SalaryPeriod? _period = SalaryPeriod.year;
  final _skills = <SkillDraft>[];
  final _languages = <String>{};
  DateTime? _publishedAt;
  DateTime? _expiresAt;
  bool _saving = false;
  bool _dirty = false;
  String? _error;

  List<TextEditingController> get _controllers => [
    _title,
    _url,
    _description,
    _company,
    _companyWebsite,
    _city,
    _country,
    _salaryMin,
    _salaryMax,
    _currency,
    _years,
    _skillInput,
    _applyUrl,
    _applyEmail,
    _recruiterName,
    _recruiterEmail,
    _recruiterPhone,
    _recruiterLinkedin,
  ];

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _touch() {
    if (!_dirty) setState(() => _dirty = true);
  }

  void _addSkill() {
    final names = _skillInput.text
        .split(RegExp(r'[,;]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && s.length <= 100);
    setState(() {
      for (final name in names) {
        if (!_skills.any((s) => s.name.toLowerCase() == name.toLowerCase())) {
          _skills.add(SkillDraft(name));
        }
      }
      _skillInput.clear();
      _dirty = true;
    });
  }

  static num? _number(String text) =>
      num.tryParse(text.trim().replaceAll(RegExp(r'[\s  ]'), '').replaceAll(',', '.'));

  String? _validateSalaryMax(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final max = _number(value);
    if (max == null || max < 0) return 'Montant invalide';
    final min = _number(_salaryMin.text);
    if (min != null && max < min) return 'Inférieur au minimum';
    return null;
  }

  static String? _validateAmount(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final n = _number(value);
    return (n == null || n < 0) ? 'Montant invalide' : null;
  }

  static String? _validateOptionalEmail(String? value) =>
      (value == null || value.trim().isEmpty) ? null : Validators.email(value);

  static String? _validateTitle(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Champ obligatoire';
    if (text.length < 3) return '3 caractères minimum';
    return null;
  }

  JobDraft _draft() => JobDraft(
    title: _title.text,
    description: _description.text,
    url: _url.text,
    companyName: _company.text,
    companyWebsite: _companyWebsite.text,
    city: _city.text,
    country: _country.text,
    remote: _remote,
    hybrid: _hybrid,
    contractType: _contract,
    workTime: _workTime,
    salaryMin: _number(_salaryMin.text),
    salaryMax: _number(_salaryMax.text),
    salaryCurrency: _currency.text,
    salaryPeriod: _period,
    experienceLevel: _level,
    minYearsExperience: int.tryParse(_years.text.trim()),
    skills: List.of(_skills),
    languages: _languages.toList(),
    applicationUrl: _applyUrl.text,
    applicationEmail: _applyEmail.text,
    recruiterName: _recruiterName.text,
    recruiterEmail: _recruiterEmail.text,
    recruiterPhone: _recruiterPhone.text,
    recruiterLinkedin: _recruiterLinkedin.text,
    publishedAt: _publishedAt,
    expiresAt: _expiresAt == null
        ? null
        : DateTime(_expiresAt!.year, _expiresAt!.month, _expiresAt!.day, 23, 59),
  );

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_skillInput.text.trim().isNotEmpty) _addSkill();
    if (!_formKey.currentState!.validate()) {
      setState(() => _error = null);
      showToast('Vérifiez les champs signalés.', kind: ToastKind.error);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final job = await ref.read(jobsRepositoryProvider).create(_draft());
      ref.read(jobChangesProvider.notifier).emit(JobChange.created(job));
      showToast('Offre enregistrée', kind: ToastKind.success);
      _dirty = false;
      if (mounted) context.pushReplacement(Routes.job(job.id));
    } catch (error) {
      final message = error is ApiException ? _describe(error) : ApiException.describe(error);
      showToast(message, kind: ToastKind.error);
      if (mounted) setState(() => _error = message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Traduit les refus du pipeline (`INVALID_JOB` : `["#0 'titre': missing_identifier"]`).
  static String _describe(ApiException error) {
    if (error.code == 'INVALID_JOB' && error.details is List) {
      final codes = <String>{};
      for (final detail in error.details as List) {
        final text = detail.toString();
        final reasons = text.contains(':') ? text.substring(text.lastIndexOf(':') + 1) : text;
        codes.addAll(reasons.split(',').map((c) => c.trim()).where((c) => c.isNotEmpty));
      }
      if (codes.isNotEmpty) return codes.map(JobLabels.ingestionError).join('\n');
      return 'L\'offre a été refusée par le serveur.';
    }
    return error.userMessage;
  }

  Future<bool> _confirmLeave() => confirmDialog(
    context,
    title: 'Abandonner la saisie ?',
    message: 'Les informations saisies seront perdues.',
    confirmLabel: 'Abandonner',
    cancelLabel: 'Continuer',
    destructive: true,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final contracts = ref.watch(contractTypesProvider).value ?? const <ContractType>[];
    final levels = ref.watch(experienceLevelsProvider).value ?? const <ExperienceLevel>[];
    final contractNames = {for (final c in contracts.where((c) => c.isActive)) c.code: c.name};
    final levelNames = {for (final l in levels) l.code: l.name};

    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await _confirmLeave();
        if (leave && context.mounted) {
          setState(() => _dirty = false);
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Ajouter une offre')),
        bottomNavigationBar: BottomBar(
          children: [
            PrimaryButton(
              label: 'Enregistrer l\'offre',
              icon: Icons.check_rounded,
              loading: _saving,
              onPressed: _submit,
            ),
          ],
        ),
        body: Form(
          key: _formKey,
          onChanged: _touch,
          child: PageListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, AppSpacing.page, 40),
            children: [
              Text(
                'Une offre repérée ailleurs ? Ajoutez-la : elle sera analysée et comparée à votre profil.',
                style: theme.bodyMedium?.copyWith(color: AppColors.textSecondary),
              ),
              if (_error != null) ...[const Gap(16), _ErrorBanner(message: _error!)],
              const SectionHeader('L\'offre'),
              AppTextField(
                label: 'Intitulé du poste',
                controller: _title,
                hint: 'Ex. Développeur Full Stack Python',
                maxLength: 500,
                textInputAction: TextInputAction.next,
                validator: _validateTitle,
              ),
              formGap,
              AppTextField(
                label: 'Lien de l\'annonce',
                optional: true,
                controller: _url,
                hint: 'https://',
                keyboardType: TextInputType.url,
                prefixIcon: Icons.link_rounded,
                validator: Validators.optionalUrl,
              ),
              formGap,
              AppTextField(
                label: 'Description',
                optional: true,
                controller: _description,
                hint: 'Collez le texte de l\'annonce : les compétences y sont détectées.',
                maxLines: 10,
                minLines: 5,
                keyboardType: TextInputType.multiline,
              ),
              const SectionHeader('Entreprise'),
              AppTextField(
                label: 'Nom',
                optional: true,
                controller: _company,
                prefixIcon: Icons.business_outlined,
                textInputAction: TextInputAction.next,
              ),
              formGap,
              AppTextField(
                label: 'Site web',
                optional: true,
                controller: _companyWebsite,
                hint: 'https://',
                keyboardType: TextInputType.url,
                validator: Validators.optionalUrl,
              ),
              const SectionHeader('Lieu et contrat'),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: AppTextField(
                      label: 'Ville',
                      optional: true,
                      controller: _city,
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                  const Gap(12),
                  Expanded(
                    child: AppTextField(
                      label: 'Pays',
                      optional: true,
                      controller: _country,
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                ],
              ),
              const Gap(4),
              SwitchRow(
                title: 'Télétravail complet',
                value: _remote,
                onChanged: (v) => setState(() {
                  _remote = v;
                  if (v) _hybrid = false;
                  _dirty = true;
                }),
              ),
              SwitchRow(
                title: 'Hybride',
                subtitle: 'Télétravail partiel',
                value: _hybrid,
                onChanged: (v) => setState(() {
                  _hybrid = v;
                  if (v) _remote = false;
                  _dirty = true;
                }),
              ),
              formGap,
              AppDropdown<String>(
                label: 'Type de contrat',
                optional: true,
                values: contractNames.keys.toList(),
                value: contractNames.containsKey(_contract) ? _contract : null,
                labelOf: (code) => contractNames[code] ?? code,
                allowNull: true,
                nullLabel: 'Non précisé',
                onChanged: (v) => setState(() {
                  _contract = v;
                  _dirty = true;
                }),
              ),
              formGap,
              const FieldLabel('Temps de travail', optional: true),
              ChoiceChips<String>(
                values: const ['full_time', 'part_time'],
                selected: _workTime,
                labelOf: (code) => JobLabels.workTime(code) ?? code,
                allowDeselect: true,
                onSelected: (v) => setState(() {
                  _workTime = v;
                  _dirty = true;
                }),
              ),
              const SectionHeader('Profil recherché'),
              AppDropdown<String>(
                label: 'Niveau d\'expérience',
                optional: true,
                values: levelNames.keys.toList(),
                value: levelNames.containsKey(_level) ? _level : null,
                labelOf: (code) => levelNames[code] ?? code,
                allowNull: true,
                nullLabel: 'Non précisé',
                onChanged: (v) => setState(() {
                  _level = v;
                  _dirty = true;
                }),
              ),
              formGap,
              AppTextField(
                label: 'Années d\'expérience minimum',
                optional: true,
                controller: _years,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return null;
                  final years = int.tryParse(value.trim());
                  return (years == null || years > 50) ? 'Entre 0 et 50 ans' : null;
                },
              ),
              formGap,
              const FieldLabel('Compétences', optional: true),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: AppTextField(
                      controller: _skillInput,
                      hint: 'Ex. Python, Docker',
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _addSkill(),
                    ),
                  ),
                  const Gap(8),
                  SizedBox(
                    height: 50,
                    child: OutlinedButton(
                      onPressed: _addSkill,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      child: const Text('Ajouter'),
                    ),
                  ),
                ],
              ),
              if (_skills.isNotEmpty) ...[
                const Gap(12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final skill in _skills)
                      InputChip(
                        label: Text(
                          skill.requirement == SkillRequirement.required
                              ? skill.name
                              : '${skill.name} · souhaitée',
                        ),
                        onPressed: () => setState(() {
                          final i = _skills.indexOf(skill);
                          _skills[i] = skill.toggled();
                        }),
                        onDeleted: () => setState(() => _skills.remove(skill)),
                        deleteIcon: const Icon(Icons.close_rounded, size: 16),
                      ),
                  ],
                ),
                const Gap(6),
                Text(
                  'Touchez une compétence pour la marquer obligatoire ou souhaitée.',
                  style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
                ),
              ],
              formGap,
              const FieldLabel('Langues demandées', optional: true),
              MultiChoiceChips<String>(
                values: JobLabels.formLanguages,
                selected: _languages,
                labelOf: JobLabels.language,
                onChanged: (value) => setState(() {
                  _languages
                    ..clear()
                    ..addAll(value);
                  _dirty = true;
                }),
              ),
              const SectionHeader('Rémunération'),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: AppTextField(
                      label: 'Minimum',
                      optional: true,
                      controller: _salaryMin,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: _validateAmount,
                    ),
                  ),
                  const Gap(12),
                  Expanded(
                    child: AppTextField(
                      label: 'Maximum',
                      optional: true,
                      controller: _salaryMax,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: _validateSalaryMax,
                    ),
                  ),
                  const Gap(12),
                  SizedBox(
                    width: 84,
                    child: AppTextField(
                      label: 'Devise',
                      controller: _currency,
                      maxLength: 3,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp('[a-zA-Z]')),
                        _UpperCaseFormatter(),
                      ],
                      validator: (value) {
                        final hasAmount =
                            _salaryMin.text.trim().isNotEmpty || _salaryMax.text.trim().isNotEmpty;
                        if (!hasAmount || value == null || value.trim().isEmpty) return null;
                        return value.trim().length == 3 ? null : '3 lettres';
                      },
                    ),
                  ),
                ],
              ),
              const Gap(4),
              ChoiceChips<SalaryPeriod>(
                values: SalaryPeriod.values,
                selected: _period,
                labelOf: (p) => 'Par ${p.label}',
                allowDeselect: true,
                onSelected: (p) => setState(() {
                  _period = p;
                  _dirty = true;
                }),
              ),
              const SectionHeader('Candidature'),
              AppTextField(
                label: 'Lien pour postuler',
                optional: true,
                controller: _applyUrl,
                hint: 'https://',
                keyboardType: TextInputType.url,
                prefixIcon: Icons.link_rounded,
                validator: Validators.optionalUrl,
              ),
              formGap,
              AppTextField(
                label: 'Email pour postuler',
                optional: true,
                controller: _applyEmail,
                keyboardType: TextInputType.emailAddress,
                prefixIcon: Icons.alternate_email_rounded,
                validator: _validateOptionalEmail,
              ),
              const SectionHeader('Recruteur'),
              AppTextField(
                label: 'Nom',
                optional: true,
                controller: _recruiterName,
                prefixIcon: Icons.person_outline_rounded,
              ),
              formGap,
              AppTextField(
                label: 'Email',
                optional: true,
                controller: _recruiterEmail,
                keyboardType: TextInputType.emailAddress,
                validator: _validateOptionalEmail,
              ),
              formGap,
              AppTextField(
                label: 'Téléphone',
                optional: true,
                controller: _recruiterPhone,
                keyboardType: TextInputType.phone,
              ),
              formGap,
              AppTextField(
                label: 'Profil LinkedIn',
                optional: true,
                controller: _recruiterLinkedin,
                hint: 'https://linkedin.com/in/...',
                keyboardType: TextInputType.url,
                validator: Validators.optionalUrl,
              ),
              const SectionHeader('Dates'),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DateField(
                      label: 'Publiée le',
                      optional: true,
                      value: _publishedAt,
                      lastDate: DateTime.now(),
                      onChanged: (d) => setState(() {
                        _publishedAt = d;
                        _dirty = true;
                      }),
                    ),
                  ),
                  const Gap(12),
                  Expanded(
                    child: DateField(
                      label: 'Expire le',
                      optional: true,
                      value: _expiresAt,
                      firstDate: DateTime.now(),
                      onChanged: (d) => setState(() {
                        _expiresAt = d;
                        _dirty = true;
                      }),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.tint(AppColors.danger, 0.08),
      borderRadius: AppRadius.input,
      border: Border.all(color: AppColors.tint(AppColors.danger, 0.3)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline_rounded, size: 18, color: AppColors.danger),
        const Gap(10),
        Expanded(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.danger),
          ),
        ),
      ],
    ),
  );
}
