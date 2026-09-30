import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/enums.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/ui.dart';
import '../data/application_models.dart';
import '../data/applications_repository.dart';
import 'common.dart';
import 'generated_text_sheet.dart';

/// Éditeurs des brouillons d'une candidature (`PUT /applications/{id}`).
/// Chaque feuille renvoie la candidature mise à jour.

/// Base commune : enregistrement, erreur, bouton « Générer ».
abstract class _DraftState<W extends ConsumerStatefulWidget> extends ConsumerState<W> {
  bool saving = false;
  String? error;

  Application get application;

  ApplicationUpdate buildUpdate();

  Future<void> save() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final result = await ref
          .read(applicationsRepositoryProvider)
          .update(application.id, buildUpdate());
      if (mounted) Navigator.of(context).pop(result);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = ApiException.describe(e);
        });
      }
    }
  }

  /// Génère un texte ; renvoie le texte si l'utilisateur choisit de l'utiliser.
  Future<GeneratedText?> generate(GenerationKind kind) =>
      generateAndPreview(context, ref, applicationId: application.id, kind: kind);

  Widget saveButton() => PrimaryButton(label: 'Enregistrer', loading: saving, onPressed: save);

  List<Widget> errorBanner() => [
    if (error != null) ...[
      const Gap(12),
      NoticeBanner(message: error!, color: AppColors.danger, icon: Icons.error_outline_rounded),
    ],
  ];
}

/// Bouton « Générer » d'un éditeur.
class _GenerateButton extends StatelessWidget {
  const _GenerateButton({required this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: onPressed,
    icon: const Icon(Icons.auto_awesome_rounded, size: 18),
    label: const Text('Générer'),
  );
}

// ---------------------------------------------------------------------------

class CoverLetterSheet extends ConsumerStatefulWidget {
  const CoverLetterSheet({super.key, required this.application});
  final Application application;

  @override
  ConsumerState<CoverLetterSheet> createState() => _CoverLetterSheetState();
}

class _CoverLetterSheetState extends _DraftState<CoverLetterSheet> {
  late final TextEditingController _text;

  @override
  Application get application => widget.application;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: application.coverLetterText);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  ApplicationUpdate buildUpdate() => ApplicationUpdate.coverLetter(_text.text);

  Future<void> _generate() async {
    final text = await generate(GenerationKind.coverLetter);
    if (text != null && mounted) setState(() => _text.text = text.content);
  }

  @override
  Widget build(BuildContext context) => SheetLayout(
    title: 'Lettre de motivation',
    expand: true,
    trailing: _GenerateButton(onPressed: saving ? null : _generate),
    footer: saveButton(),
    children: [
      AppTextField(
        controller: _text,
        hint: 'Madame, Monsieur, ...',
        maxLines: null,
        minLines: 14,
        maxLength: 20000,
        keyboardType: TextInputType.multiline,
      ),
      ...errorBanner(),
    ],
  );
}

// ---------------------------------------------------------------------------

class EmailDraftSheet extends ConsumerStatefulWidget {
  const EmailDraftSheet({super.key, required this.application});
  final Application application;

  @override
  ConsumerState<EmailDraftSheet> createState() => _EmailDraftSheetState();
}

class _EmailDraftSheetState extends _DraftState<EmailDraftSheet> {
  late final TextEditingController _subject;
  late final TextEditingController _body;

  @override
  Application get application => widget.application;

  @override
  void initState() {
    super.initState();
    _subject = TextEditingController(text: application.emailSubject);
    _body = TextEditingController(text: application.emailBody);
  }

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  ApplicationUpdate buildUpdate() =>
      ApplicationUpdate.email(subject: _subject.text, body: _body.text);

  Future<void> _generate() async {
    final text = await generate(GenerationKind.applicationEmail);
    if (text == null || !mounted) return;
    setState(() {
      if (text.subject != null) _subject.text = text.subject!;
      _body.text = text.content;
    });
  }

  @override
  Widget build(BuildContext context) => SheetLayout(
    title: 'Email de candidature',
    expand: true,
    trailing: _GenerateButton(onPressed: saving ? null : _generate),
    footer: saveButton(),
    children: [
      AppTextField(
        label: 'Objet',
        controller: _subject,
        hint: 'Candidature : ...',
        maxLength: 255,
      ),
      formGap,
      AppTextField(
        label: 'Message',
        controller: _body,
        hint: 'Bonjour, ...',
        maxLines: null,
        minLines: 10,
        maxLength: 20000,
        keyboardType: TextInputType.multiline,
      ),
      const Gap(4),
      Text(
        'Le CV sélectionné est joint automatiquement lors d\'un envoi par email.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
      ),
      ...errorBanner(),
    ],
  );
}

// ---------------------------------------------------------------------------

class NotesSheet extends ConsumerStatefulWidget {
  const NotesSheet({super.key, required this.application});
  final Application application;

  @override
  ConsumerState<NotesSheet> createState() => _NotesSheetState();
}

class _NotesSheetState extends _DraftState<NotesSheet> {
  late final TextEditingController _notes;
  DateTime? _followUp;

  @override
  Application get application => widget.application;

  @override
  void initState() {
    super.initState();
    _notes = TextEditingController(text: application.notes);
    _followUp = application.followUpAt;
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  ApplicationUpdate buildUpdate() {
    // La date choisie est un jour : on garde l'heure éventuelle d'origine, sinon 9 h.
    final day = _followUp;
    final original = application.followUpAt;
    final followUp = day == null
        ? null
        : (original != null && _sameDay(original, day))
        ? original
        : DateTime(day.year, day.month, day.day, 9);
    return ApplicationUpdate.notes(notes: _notes.text, followUpAt: followUp);
  }

  @override
  Widget build(BuildContext context) => SheetLayout(
    title: 'Notes et relance',
    footer: saveButton(),
    children: [
      DateField(
        label: 'Relance prévue',
        optional: true,
        value: _followUp,
        firstDate: DateTime.now().subtract(const Duration(days: 365)),
        onChanged: (value) => setState(() => _followUp = value),
      ),
      formGap,
      AppTextField(
        label: 'Notes',
        optional: true,
        controller: _notes,
        hint: 'Contact, points à préparer, impressions...',
        maxLines: null,
        minLines: 5,
        maxLength: 10000,
        keyboardType: TextInputType.multiline,
      ),
      ...errorBanner(),
    ],
  );
}

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

// ---------------------------------------------------------------------------

/// Intitulé et entreprise (candidature créée sans offre).
class DetailsSheet extends ConsumerStatefulWidget {
  const DetailsSheet({super.key, required this.application});
  final Application application;

  @override
  ConsumerState<DetailsSheet> createState() => _DetailsSheetState();
}

class _DetailsSheetState extends _DraftState<DetailsSheet> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _company;

  @override
  Application get application => widget.application;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: application.jobTitle);
    _company = TextEditingController(text: application.companyName);
  }

  @override
  void dispose() {
    _title.dispose();
    _company.dispose();
    super.dispose();
  }

  @override
  ApplicationUpdate buildUpdate() =>
      ApplicationUpdate.details(jobTitle: _title.text, companyName: _company.text);

  @override
  Future<void> save() async {
    if (!_form.currentState!.validate()) return;
    await super.save();
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: SheetLayout(
      title: 'Intitulé',
      footer: saveButton(),
      children: [
        AppTextField(
          label: 'Poste',
          controller: _title,
          validator: Validators.required,
          maxLength: 500,
          textInputAction: TextInputAction.next,
        ),
        formGap,
        AppTextField(label: 'Entreprise', optional: true, controller: _company, maxLength: 255),
        ...errorBanner(),
      ],
    ),
  );
}
