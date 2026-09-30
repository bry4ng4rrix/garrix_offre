import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/enums.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/ui.dart';
import '../../documents/data/documents_repository.dart';
import '../data/application_models.dart';
import '../data/applications_repository.dart';
import 'common.dart';
import 'cv_picker_sheet.dart';

/// Nouvelle candidature sans offre (candidature spontanée, offre vue ailleurs...).
/// Renvoie la candidature créée.
class CreateApplicationSheet extends ConsumerStatefulWidget {
  const CreateApplicationSheet({super.key});

  @override
  ConsumerState<CreateApplicationSheet> createState() => _CreateApplicationSheetState();
}

class _CreateApplicationSheetState extends ConsumerState<CreateApplicationSheet> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _company = TextEditingController();
  final _notes = TextEditingController();
  ApplicationStatus _status = ApplicationStatus.preparing;
  String? _cvId;
  DateTime? _followUp;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _company.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickCv() async {
    final picked = await showAppSheet<({String? id})>(
      context,
      builder: (_) => CvPickerSheet(
        selectedId: _cvId,
        noneLabel: 'Plus tard',
        noneSubtitle: 'Le CV le plus adapté sera proposé lors de la préparation',
      ),
    );
    if (picked != null && mounted) setState(() => _cvId = picked.id);
  }

  Future<void> _create() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final created = await ref
          .read(applicationsRepositoryProvider)
          .create(
            ApplicationCreate(
              jobTitle: _title.text.trim(),
              companyName: _company.text,
              status: _status,
              cvDocumentId: _cvId,
              notes: _notes.text,
              followUpAt: _followUp == null
                  ? null
                  : DateTime(_followUp!.year, _followUp!.month, _followUp!.day, 9),
            ),
          );
      if (mounted) Navigator.of(context).pop(created);
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = ApiException.describe(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cvs = ref.watch(cvDocumentsProvider).value ?? const [];
    final cv = cvs.where((d) => d.id == _cvId).firstOrNull;
    return Form(
      key: _form,
      child: SheetLayout(
        title: 'Nouvelle candidature',
        subtitle:
            'Pour une offre vue ailleurs ou une candidature spontanée. '
            'Depuis une offre, utilisez plutôt « Postuler ».',
        expand: true,
        footer: PrimaryButton(label: 'Créer', loading: _loading, onPressed: _create),
        children: [
          AppTextField(
            label: 'Poste',
            controller: _title,
            hint: 'Développeur Flutter',
            validator: Validators.required,
            maxLength: 500,
            textInputAction: TextInputAction.next,
            autofocus: true,
          ),
          formGap,
          AppTextField(
            label: 'Entreprise',
            optional: true,
            controller: _company,
            hint: 'Nom de l\'entreprise',
            maxLength: 255,
            textInputAction: TextInputAction.next,
          ),
          formGap,
          const FieldLabel('Statut'),
          ChoiceChips<ApplicationStatus>(
            values: const [ApplicationStatus.notApplied, ApplicationStatus.preparing],
            selected: _status,
            labelOf: (status) => status.label,
            onSelected: (status) => setState(() => _status = status ?? _status),
          ),
          formGap,
          const FieldLabel('CV', optional: true),
          SelectableOption(
            title: cv?.title ?? (_cvId == null ? 'Choisir plus tard' : 'CV sélectionné'),
            subtitle: cv?.originalFilename ?? 'Touchez pour choisir un CV',
            icon: Icons.description_outlined,
            badge: cv?.isPrimary == true ? 'Principal' : null,
            selected: _cvId != null,
            onTap: _loading ? null : _pickCv,
          ),
          formGap,
          DateField(
            label: 'Relance prévue',
            optional: true,
            value: _followUp,
            firstDate: DateTime.now().subtract(const Duration(days: 30)),
            onChanged: (value) => setState(() => _followUp = value),
          ),
          formGap,
          AppTextField(
            label: 'Notes',
            optional: true,
            controller: _notes,
            hint: 'Lien de l\'annonce, contact, source...',
            maxLines: null,
            minLines: 3,
            maxLength: 10000,
            keyboardType: TextInputType.multiline,
          ),
          if (_error != null) ...[
            const Gap(8),
            NoticeBanner(
              message: _error!,
              color: AppColors.danger,
              icon: Icons.error_outline_rounded,
            ),
          ],
        ],
      ),
    );
  }
}
