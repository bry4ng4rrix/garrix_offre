import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/enums.dart';
import '../../core/models/reference.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/json.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/form_fields.dart';
import '../../core/widgets/ui.dart';
import 'data/profile_labels.dart';
import 'data/profile_models.dart';
import 'data/profile_providers.dart';
import 'widgets/profile_widgets.dart';

/// Modification du profil professionnel (`PUT /profile`) et de la photo.
class EditProfilePage extends ConsumerWidget {
  const EditProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final value = profile.value;
    if (value != null) return _EditProfileForm(key: ValueKey(value.id), initial: value);
    return Scaffold(
      appBar: AppBar(title: const Text('Modifier le profil')),
      body: AsyncValueView<Profile>(
        value: profile,
        onRetry: () => ref.invalidate(profileProvider),
        data: (_) => const SizedBox.shrink(),
      ),
    );
  }
}

/// Ligne « langue + niveau » (clé stable pour la liste).
class _LanguageRow {
  _LanguageRow(this.key, this.code, this.level);
  final int key;
  String code;
  LanguageLevel level;
}

final _phonePattern = RegExp(r'^\+?[0-9 ().-]{6,30}$');

class _EditProfileForm extends ConsumerStatefulWidget {
  const _EditProfileForm({super.key, required this.initial});

  final Profile initial;

  @override
  ConsumerState<_EditProfileForm> createState() => _EditProfileFormState();
}

class _EditProfileFormState extends ConsumerState<_EditProfileForm> {
  final _formKey = GlobalKey<FormState>();

  late final _firstName = TextEditingController(text: widget.initial.firstName);
  late final _lastName = TextEditingController(text: widget.initial.lastName);
  late final _title = TextEditingController(text: widget.initial.professionalTitle);
  late final _bio = TextEditingController(text: widget.initial.bio);
  late final _email = TextEditingController(text: widget.initial.email);
  late final _phone = TextEditingController(text: widget.initial.phone);
  late final _city = TextEditingController(text: widget.initial.city);
  late final _country = TextEditingController(text: widget.initial.country);
  late final _address = TextEditingController(text: widget.initial.professionalAddress);
  late final _linkedin = TextEditingController(text: widget.initial.linkedinUrl);
  late final _github = TextEditingController(text: widget.initial.githubUrl);
  late final _portfolio = TextEditingController(text: widget.initial.portfolioUrl);
  late final _years = TextEditingController(text: widget.initial.yearsOfExperience?.toString());
  late final _salary = TextEditingController(text: widget.initial.minimumSalary?.toString());

  late Availability? _availability = widget.initial.availability;
  late DateTime? _availableFrom = widget.initial.availableFrom;
  late String? _level = widget.initial.experienceLevel;
  late Mobility? _mobility = widget.initial.mobility;
  late String _currency = widget.initial.currency;
  late SalaryPeriod _period = widget.initial.salaryPeriod;
  late bool _remote = widget.initial.remote;
  late final List<_LanguageRow> _languages = [
    for (var i = 0; i < widget.initial.languages.length; i++)
      _LanguageRow(i, widget.initial.languages[i].code, widget.initial.languages[i].level),
  ];
  late int _nextLanguageKey = _languages.length;

  late final String _initialBody;
  bool _saving = false;
  bool _uploading = false;

  List<TextEditingController> get _controllers => [
    _firstName,
    _lastName,
    _title,
    _bio,
    _email,
    _phone,
    _city,
    _country,
    _address,
    _linkedin,
    _github,
    _portfolio,
    _years,
    _salary,
  ];

  @override
  void initState() {
    super.initState();
    // État initial figé pour détecter les modifications non enregistrées.
    _initialBody = jsonEncode(_body());
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  static String? _text(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  /// Corps complet de `PUT /profile` (les champs vides effacent la valeur).
  Map<String, dynamic> _body() {
    final seen = <String>{};
    final languages = [
      for (final row in _languages)
        if (seen.add(row.code)) LanguageSkill(code: row.code, level: row.level).toJson(),
    ];
    return {
      'first_name': _text(_firstName),
      'last_name': _text(_lastName),
      'professional_title': _text(_title),
      'bio': _text(_bio),
      'email': _text(_email),
      'phone': _text(_phone),
      'city': _text(_city),
      'country': _text(_country),
      'professional_address': _text(_address),
      'linkedin_url': _text(_linkedin),
      'github_url': _text(_github),
      'portfolio_url': _text(_portfolio),
      'years_of_experience': int.tryParse(_years.text.trim()),
      'experience_level': _level,
      'availability': _availability?.apiValue,
      'available_from': _availableFrom == null ? null : formatApiDate(_availableFrom!),
      'mobility': _mobility?.apiValue,
      'languages': languages,
      'minimum_salary': int.tryParse(_salary.text.trim().replaceAll(' ', '')),
      'currency': _currency,
      'salary_period': _period.apiValue,
      'remote': _remote,
    };
  }

  bool get _hasChanges => jsonEncode(_body()) != _initialBody;

  Future<void> _onPop() async {
    if (_saving) return;
    if (!_hasChanges || await confirmDiscard(context)) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) {
      showToast('Vérifiez les champs signalés.', kind: ToastKind.error);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(profileProvider.notifier).save(_body());
      showToast('Profil enregistré', kind: ToastKind.success);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      showError(error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickPhoto() async {
    try {
      final file = await FilePicker.pickFile(
        dialogTitle: 'Choisir une photo',
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      );
      if (file == null) return;
      setState(() => _uploading = true);
      final path = file.path;
      await ref
          .read(profileProvider.notifier)
          .uploadPhoto(
            filename: file.name,
            path: path,
            bytes: path == null ? await file.readAsBytes() : null,
          );
      showToast('Photo mise à jour', kind: ToastKind.success);
    } catch (error) {
      showError(error);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _deletePhoto() async {
    final confirmed = await confirmDialog(
      context,
      title: 'Supprimer la photo ?',
      confirmLabel: 'Supprimer',
      destructive: true,
    );
    if (!confirmed) return;
    setState(() => _uploading = true);
    await runAction(
      () => ref.read(profileProvider.notifier).deletePhoto(),
      success: 'Photo supprimée',
    );
    if (mounted) setState(() => _uploading = false);
  }

  void _addLanguage() {
    final used = _languages.map((l) => l.code).toSet();
    final code = kLanguages.keys.firstWhere((c) => !used.contains(c), orElse: () => 'en');
    setState(
      () => _languages.add(_LanguageRow(_nextLanguageKey++, code, LanguageLevel.intermediate)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final levels = ref.watch(experienceLevelsProvider).value ?? const <ExperienceLevel>[];
    final levelCodes = [
      ...levels.map((l) => l.code),
      if (_level != null && !levels.any((l) => l.code == _level)) _level!,
    ];
    final currencies = [...kCurrencies, if (!kCurrencies.contains(_currency)) _currency];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onPop();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Modifier le profil')),
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
        body: Form(
          key: _formKey,
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
            child: PageBody(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Gap(AppSpacing.sm),
                  _PhotoSection(busy: _uploading, onPick: _pickPhoto, onDelete: _deletePhoto),

                  const SectionHeader('Identité'),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: AppTextField(
                          label: 'Prénom',
                          controller: _firstName,
                          textInputAction: TextInputAction.next,
                          inputFormatters: [LengthLimitingTextInputFormatter(100)],
                        ),
                      ),
                      const Gap(12),
                      Expanded(
                        child: AppTextField(
                          label: 'Nom',
                          controller: _lastName,
                          textInputAction: TextInputAction.next,
                          inputFormatters: [LengthLimitingTextInputFormatter(100)],
                        ),
                      ),
                    ],
                  ),
                  formGap,
                  AppTextField(
                    label: 'Titre professionnel',
                    controller: _title,
                    hint: 'Développeur Full Stack Python / React',
                    textInputAction: TextInputAction.next,
                    inputFormatters: [LengthLimitingTextInputFormatter(200)],
                  ),
                  formGap,
                  AppTextField(
                    label: 'Présentation',
                    controller: _bio,
                    optional: true,
                    hint: 'Quelques lignes sur votre parcours et ce que vous cherchez.',
                    minLines: 3,
                    maxLines: 8,
                    keyboardType: TextInputType.multiline,
                    inputFormatters: [LengthLimitingTextInputFormatter(5000)],
                  ),

                  const SectionHeader('Coordonnées'),
                  AppTextField(
                    label: 'Email de contact',
                    controller: _email,
                    prefixIcon: Icons.alternate_email_rounded,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    validator: (v) => (v == null || v.trim().isEmpty) ? null : Validators.email(v),
                  ),
                  formGap,
                  AppTextField(
                    label: 'Téléphone',
                    controller: _phone,
                    hint: '+261 34 00 000 00',
                    prefixIcon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty || _phonePattern.hasMatch(v.trim()))
                        ? null
                        : 'Numéro invalide',
                  ),
                  formGap,
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: AppTextField(
                          label: 'Ville',
                          controller: _city,
                          textInputAction: TextInputAction.next,
                          inputFormatters: [LengthLimitingTextInputFormatter(100)],
                        ),
                      ),
                      const Gap(12),
                      Expanded(
                        child: AppTextField(
                          label: 'Pays',
                          controller: _country,
                          textInputAction: TextInputAction.next,
                          inputFormatters: [LengthLimitingTextInputFormatter(100)],
                        ),
                      ),
                    ],
                  ),
                  formGap,
                  AppTextField(
                    label: 'Adresse professionnelle',
                    controller: _address,
                    optional: true,
                    maxLines: 2,
                    inputFormatters: [LengthLimitingTextInputFormatter(500)],
                  ),

                  const SectionHeader('Liens'),
                  AppTextField(
                    label: 'LinkedIn',
                    controller: _linkedin,
                    optional: true,
                    hint: 'https://linkedin.com/in/…',
                    prefixIcon: Icons.link_rounded,
                    keyboardType: TextInputType.url,
                    validator: Validators.optionalUrl,
                  ),
                  formGap,
                  AppTextField(
                    label: 'GitHub',
                    controller: _github,
                    optional: true,
                    hint: 'https://github.com/…',
                    prefixIcon: Icons.code_rounded,
                    keyboardType: TextInputType.url,
                    validator: Validators.optionalUrl,
                  ),
                  formGap,
                  AppTextField(
                    label: 'Portfolio / site',
                    controller: _portfolio,
                    optional: true,
                    hint: 'https://…',
                    prefixIcon: Icons.public_rounded,
                    keyboardType: TextInputType.url,
                    validator: Validators.optionalUrl,
                  ),

                  const SectionHeader('Expérience et disponibilité'),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: AppTextField(
                          label: 'Années d\'expérience',
                          controller: _years,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(2),
                          ],
                          validator: (v) {
                            final years = int.tryParse(v?.trim() ?? '');
                            return years != null && years > 60 ? '60 ans maximum' : null;
                          },
                        ),
                      ),
                      const Gap(12),
                      Expanded(
                        child: AppDropdown<String>(
                          label: 'Niveau',
                          values: levelCodes,
                          value: _level,
                          allowNull: true,
                          nullLabel: 'Non précisé',
                          labelOf: (code) => experienceLevelName(code, levels),
                          onChanged: (code) => setState(() => _level = code),
                        ),
                      ),
                    ],
                  ),
                  formGap,
                  const FieldLabel('Disponibilité'),
                  ChoiceChips<Availability>(
                    values: Availability.values,
                    selected: _availability,
                    allowDeselect: true,
                    labelOf: (a) => a.label,
                    onSelected: (a) => setState(() => _availability = a),
                  ),
                  formGap,
                  DateField(
                    label: 'Disponible à partir du',
                    optional: true,
                    value: _availableFrom,
                    onChanged: (date) => setState(() => _availableFrom = date),
                  ),
                  formGap,
                  const FieldLabel('Mobilité géographique'),
                  ChoiceChips<Mobility>(
                    values: Mobility.values,
                    selected: _mobility,
                    allowDeselect: true,
                    labelOf: (m) => m.label,
                    onSelected: (m) => setState(() => _mobility = m),
                  ),

                  SectionHeader(
                    'Langues',
                    trailing: Text(
                      '${_languages.length}/15',
                      style: theme.labelSmall?.copyWith(color: AppColors.textTertiary),
                    ),
                  ),
                  if (_languages.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Aucune langue. Les langues servent au matching des offres.',
                        style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
                      ),
                    ),
                  for (final row in _languages)
                    Padding(
                      key: ValueKey(row.key),
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _LanguageRowField(
                        row: row,
                        onChanged: () => setState(() {}),
                        onRemove: () => setState(() => _languages.remove(row)),
                      ),
                    ),
                  if (_languages.length < 15)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _addLanguage,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Ajouter une langue'),
                      ),
                    ),

                  const SectionHeader('Rémunération et télétravail'),
                  Text(
                    'Ces réglages sont partagés avec vos préférences de recherche.',
                    style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
                  ),
                  const Gap(12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: AppTextField(
                          label: 'Salaire minimum',
                          controller: _salary,
                          optional: true,
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
                          label: 'Devise',
                          values: currencies,
                          value: _currency,
                          labelOf: (c) => c,
                          onChanged: (c) => setState(() => _currency = c ?? _currency),
                        ),
                      ),
                    ],
                  ),
                  formGap,
                  ChoiceChips<SalaryPeriod>(
                    values: SalaryPeriod.values,
                    selected: _period,
                    labelOf: salaryPeriodLabel,
                    onSelected: (p) => setState(() => _period = p ?? _period),
                  ),
                  const Gap(8),
                  SwitchRow(
                    title: 'Ouvert au télétravail',
                    subtitle: 'Les offres en télétravail complet vous correspondent.',
                    value: _remote,
                    onChanged: (v) => setState(() => _remote = v),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Photo de profil avec actions « Changer » et « Supprimer ».
class _PhotoSection extends ConsumerWidget {
  const _PhotoSection({required this.busy, required this.onPick, required this.onDelete});

  final bool busy;
  final VoidCallback onPick;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).value;
    if (profile == null) return const SizedBox.shrink();
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            GestureDetector(
              onTap: busy ? null : onPick,
              child: ProfileAvatar(profile: profile, size: 96),
            ),
            if (busy)
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
          ],
        ),
        const Gap(12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 4,
          children: [
            TextButton.icon(
              onPressed: busy ? null : onPick,
              icon: const Icon(Icons.photo_camera_outlined, size: 18),
              label: Text(profile.hasPhoto ? 'Changer la photo' : 'Ajouter une photo'),
            ),
            if (profile.hasPhoto)
              TextButton.icon(
                onPressed: busy ? null : onDelete,
                style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('Supprimer'),
              ),
          ],
        ),
        Text(
          'JPG, PNG ou WebP',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
        ),
      ],
    );
  }
}

/// Langue + niveau + bouton de suppression.
class _LanguageRowField extends StatelessWidget {
  const _LanguageRowField({required this.row, required this.onChanged, required this.onRemove});

  final _LanguageRow row;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final codes = [...kLanguages.keys, if (!kLanguages.containsKey(row.code)) row.code];
    return Row(
      children: [
        Expanded(
          child: AppDropdown<String>(
            values: codes,
            value: row.code,
            labelOf: languageName,
            onChanged: (code) {
              if (code == null) return;
              row.code = code;
              onChanged();
            },
          ),
        ),
        const Gap(10),
        Expanded(
          child: AppDropdown<LanguageLevel>(
            values: LanguageLevel.values,
            value: row.level,
            labelOf: (l) => l.label,
            onChanged: (level) {
              if (level == null) return;
              row.level = level;
              onChanged();
            },
          ),
        ),
        IconButton(
          tooltip: 'Retirer',
          onPressed: onRemove,
          icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.textTertiary),
        ),
      ],
    );
  }
}
