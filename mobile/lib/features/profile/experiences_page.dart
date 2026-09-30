import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import 'widgets/tag_input.dart';

/// Parcours professionnel (`/experiences`) présenté en frise chronologique.
class ExperiencesPage extends ConsumerWidget {
  const ExperiencesPage({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(experiencesProvider);
    try {
      await ref.read(experiencesProvider.future);
    } catch (_) {
      // Erreur affichée par la page.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final experiences = ref.watch(experiencesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Expériences')),
      floatingActionButton: experiences.hasValue
          ? FloatingActionButton.extended(
              onPressed: () => _openForm(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Ajouter'),
            )
          : null,
      body: AsyncValueView<List<Experience>>(
        value: experiences,
        onRetry: () => ref.invalidate(experiencesProvider),
        data: (items) {
          if (items.isEmpty) {
            return PageListView(
              onRefresh: () => _refresh(ref),
              children: [
                EmptyState(
                  icon: Icons.timeline_rounded,
                  title: 'Aucune expérience',
                  message: 'Ajoutez vos postes successifs : entreprise, dates, missions '
                      'et technologies utilisées.',
                  actionLabel: 'Ajouter une expérience',
                  onAction: () => _openForm(context),
                ),
              ],
            );
          }
          return PageListView(
            onRefresh: () => _refresh(ref),
            children: [
              IntroText(
                '${items.length} expérience${items.length > 1 ? 's' : ''}, '
                'de la plus récente à la plus ancienne.',
              ),
              const Gap(AppSpacing.sm),
              for (var i = 0; i < items.length; i++)
                _TimelineItem(
                  experience: items[i],
                  isFirst: i == 0,
                  isLast: i == items.length - 1,
                  onTap: () => _openForm(context, experience: items[i]),
                ),
            ],
          );
        },
      ),
    );
  }
}

Future<void> _openForm(BuildContext context, {Experience? experience}) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _ExperienceFormPage(experience: experience),
      ),
    );

/// Élément de la frise : point + trait vertical, puis la carte de l'expérience.
class _TimelineItem extends StatelessWidget {
  const _TimelineItem({
    required this.experience,
    required this.isFirst,
    required this.isLast,
    required this.onTap,
  });

  final Experience experience;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final current = experience.isCurrent;
    final place = [
      experience.companyName,
      if (experience.location?.trim().isNotEmpty == true) experience.location!,
    ].join(' · ');

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 20,
            child: Column(
              children: [
                Container(
                  width: 1,
                  height: 22,
                  color: isFirst ? Colors.transparent : AppColors.borderStrong,
                ),
                Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: current ? AppColors.textPrimary : AppColors.background,
                    border: Border.all(
                      color: current ? AppColors.textPrimary : AppColors.textTertiary,
                      width: 1.5,
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 1,
                    color: isLast ? Colors.transparent : AppColors.borderStrong,
                  ),
                ),
              ],
            ),
          ),
          const Gap(12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AppCard(
                onTap: onTap,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: Text(experience.jobTitle, style: theme.titleMedium)),
                        if (current) ...[
                          const Gap(8),
                          const Pill('En poste', color: AppColors.success, dense: true),
                        ],
                      ],
                    ),
                    const Gap(2),
                    Text(place, style: theme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
                    const Gap(4),
                    Text(
                      '${periodLabel(experience.startDate, experience.endDate, current: current)}'
                      ' · ${durationLabel(experience.startDate, current ? null : experience.endDate)}',
                      style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
                    ),
                    if (experience.description?.trim().isNotEmpty == true) ...[
                      const Gap(10),
                      Text(
                        experience.description!.trim(),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                    if (experience.technologies.isNotEmpty) ...[
                      const Gap(12),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final technology in experience.technologies)
                            Pill(technology, dense: true),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Création / modification d'une expérience en plein écran.
class _ExperienceFormPage extends ConsumerStatefulWidget {
  const _ExperienceFormPage({this.experience});

  final Experience? experience;

  @override
  ConsumerState<_ExperienceFormPage> createState() => _ExperienceFormPageState();
}

class _ExperienceFormPageState extends ConsumerState<_ExperienceFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final _jobTitle = TextEditingController(text: widget.experience?.jobTitle);
  late final _company = TextEditingController(text: widget.experience?.companyName);
  late final _location = TextEditingController(text: widget.experience?.location);
  late final _description = TextEditingController(text: widget.experience?.description);
  late DateTime? _start = widget.experience?.startDate;
  late DateTime? _end = widget.experience?.endDate;
  late bool _current = widget.experience?.isCurrent ?? false;
  late List<String> _technologies = [...?widget.experience?.technologies];
  late final String _initialState;
  String? _startError;
  String? _endError;
  bool _saving = false;

  bool get _editing => widget.experience != null;

  @override
  void initState() {
    super.initState();
    _initialState = _snapshot();
  }

  @override
  void dispose() {
    _jobTitle.dispose();
    _company.dispose();
    _location.dispose();
    _description.dispose();
    super.dispose();
  }

  /// Photographie des valeurs du formulaire (détection des modifications).
  String _snapshot() => jsonEncode({
    'job_title': _jobTitle.text.trim(),
    'company': _company.text.trim(),
    'location': _location.text.trim(),
    'description': _description.text.trim(),
    'start': _start == null ? null : formatApiDate(_start!),
    'end': _end == null ? null : formatApiDate(_end!),
    'current': _current,
    'technologies': _technologies,
  });

  Future<void> _onPop() async {
    if (_saving) return;
    if (_snapshot() == _initialState || await confirmDiscard(context)) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  bool _validateDates() {
    setState(() {
      _startError = _start == null ? 'Date de début obligatoire' : null;
      _endError = !_current && _start != null && _end != null && _end!.isBefore(_start!)
          ? 'La fin doit être après le début'
          : null;
    });
    return _startError == null && _endError == null;
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final fieldsOk = _formKey.currentState!.validate();
    if (!_validateDates() || !fieldsOk) return;
    setState(() => _saving = true);
    final input = ExperienceInput(
      companyName: _company.text,
      jobTitle: _jobTitle.text,
      location: _location.text,
      startDate: _start!,
      endDate: _current ? null : _end,
      isCurrent: _current,
      description: _description.text,
      technologies: _technologies,
    );
    final notifier = ref.read(experiencesProvider.notifier);
    try {
      _editing ? await notifier.edit(widget.experience!.id, input) : await notifier.create(input);
      showToast(_editing ? 'Expérience mise à jour' : 'Expérience ajoutée', kind: ToastKind.success);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      showError(error);
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await confirmDialog(
      context,
      title: 'Supprimer cette expérience ?',
      message: '${widget.experience!.jobTitle} · ${widget.experience!.companyName}',
      confirmLabel: 'Supprimer',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(experiencesProvider.notifier).remove(widget.experience!.id);
      showToast('Expérience supprimée', kind: ToastKind.success);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      showError(error);
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final skills = ref.watch(profileSkillsProvider).value ?? const <ProfileSkill>[];
    final now = DateTime.now();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onPop();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Fermer',
            icon: const Icon(Icons.close_rounded),
            onPressed: _onPop,
          ),
          title: Text(_editing ? 'Modifier l\'expérience' : 'Nouvelle expérience'),
          actions: [
            if (_editing)
              IconButton(
                tooltip: 'Supprimer',
                onPressed: _saving ? null : _delete,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            const Gap(8),
          ],
        ),
        bottomNavigationBar: BottomActionBar(
          children: [
            PrimaryButton(
              label: _editing ? 'Enregistrer' : 'Ajouter l\'expérience',
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
            padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.xxl),
            child: PageBody(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppTextField(
                    label: 'Poste',
                    controller: _jobTitle,
                    hint: 'Développeur Full Stack',
                    autofocus: !_editing,
                    textInputAction: TextInputAction.next,
                    inputFormatters: [LengthLimitingTextInputFormatter(200)],
                    validator: Validators.required,
                  ),
                  formGap,
                  AppTextField(
                    label: 'Entreprise',
                    controller: _company,
                    textInputAction: TextInputAction.next,
                    inputFormatters: [LengthLimitingTextInputFormatter(200)],
                    validator: Validators.required,
                  ),
                  formGap,
                  AppTextField(
                    label: 'Lieu',
                    controller: _location,
                    optional: true,
                    hint: 'Antananarivo, Madagascar',
                    prefixIcon: Icons.place_outlined,
                    textInputAction: TextInputAction.next,
                    inputFormatters: [LengthLimitingTextInputFormatter(200)],
                  ),
                  const SectionHeader('Période'),
                  DateField(
                    label: 'Début',
                    value: _start,
                    clearable: false,
                    lastDate: DateTime(now.year + 1, 12, 31),
                    onChanged: (date) => setState(() {
                      _start = date;
                      _startError = null;
                    }),
                  ),
                  if (_startError != null) _FieldError(_startError!),
                  const Gap(6),
                  SwitchRow(
                    title: 'Poste actuel',
                    subtitle: 'J\'occupe toujours ce poste.',
                    value: _current,
                    onChanged: (value) => setState(() {
                      _current = value;
                      _endError = null;
                    }),
                  ),
                  if (!_current) ...[
                    const Gap(6),
                    DateField(
                      label: 'Fin',
                      optional: true,
                      value: _end,
                      lastDate: DateTime(now.year + 1, 12, 31),
                      onChanged: (date) => setState(() {
                        _end = date;
                        _endError = null;
                      }),
                    ),
                    if (_endError != null) _FieldError(_endError!),
                  ],
                  if (_start != null) ...[
                    const Gap(10),
                    Text(
                      'Durée : ${durationLabel(_start!, _current ? null : _end)}',
                      style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
                    ),
                  ],
                  const SectionHeader('Détails'),
                  AppTextField(
                    label: 'Description',
                    controller: _description,
                    optional: true,
                    hint: 'Missions, réalisations, taille de l\'équipe…',
                    minLines: 4,
                    maxLines: 12,
                    keyboardType: TextInputType.multiline,
                    inputFormatters: [LengthLimitingTextInputFormatter(5000)],
                  ),
                  formGap,
                  TagInput(
                    label: 'Technologies utilisées',
                    optional: true,
                    hint: 'Python, Django… puis Entrée',
                    values: _technologies,
                    suggestions: [for (final skill in skills) skill.name],
                    onChanged: (values) => setState(() => _technologies = values),
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

class _FieldError extends StatelessWidget {
  const _FieldError(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6, left: 4),
    child: Text(
      message,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.danger),
    ),
  );
}
