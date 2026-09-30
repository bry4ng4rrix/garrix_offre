import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/reference.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/ui.dart';
import '../../documents/data/document_models.dart';
import '../../documents/data/documents_repository.dart';
import '../data/application_models.dart';
import '../data/applications_repository.dart';
import 'common.dart';
import 'cv_picker_sheet.dart';

/// « Préparer » : choix du CV + rédaction des brouillons, puis statut « Prête ».
/// Rien n'est envoyé. Renvoie la candidature mise à jour.
class PrepareSheet extends ConsumerStatefulWidget {
  const PrepareSheet({super.key, required this.application});

  final Application application;

  @override
  ConsumerState<PrepareSheet> createState() => _PrepareSheetState();
}

class _PrepareSheetState extends ConsumerState<PrepareSheet> {
  String? _cvId;
  String? _language;
  late bool _letter;
  late bool _email;
  bool _loading = false;
  String? _error;

  Application get _app => widget.application;

  @override
  void initState() {
    super.initState();
    _cvId = _app.cvDocumentId;
    _letter = true;
    _email = true;
  }

  Future<void> _pickCv() async {
    final picked = await showAppSheet<({String? id})>(
      context,
      builder: (_) => CvPickerSheet(
        selectedId: _cvId,
        noneLabel: 'Choix automatique',
        noneSubtitle: 'Le CV le plus adapté : langue, poste ciblé, puis CV principal',
      ),
    );
    if (picked != null && mounted) setState(() => _cvId = picked.id);
  }

  Future<void> _prepare() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final repository = ref.read(applicationsRepositoryProvider);
    try {
      // Le CV choisi est enregistré d'abord ; sans CV, le serveur choisit le plus adapté.
      if (_cvId != _app.cvDocumentId) {
        await repository.update(_app.id, ApplicationUpdate.cv(_cvId));
      }
      final result = await repository.prepare(
        _app.id,
        PrepareRequest(
          language: _cvId == null ? _language : null,
          generateCoverLetter: _letter,
          generateEmail: _email,
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(result);
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
    final theme = Theme.of(context).textTheme;
    final ai = ref.watch(aiStatusProvider).value;
    final cvs = ref.watch(cvDocumentsProvider).value ?? const <UserDocument>[];
    UserDocument? selected;
    for (final cv in cvs) {
      if (cv.id == _cvId) selected = cv;
    }

    return SheetLayout(
      title: 'Préparer la candidature',
      subtitle: 'Le CV est choisi et les brouillons sont rédigés. Rien n\'est envoyé : '
          'vous validerez l\'envoi à l\'étape suivante.',
      footer: PrimaryButton(
        label: 'Préparer',
        icon: Icons.auto_awesome_rounded,
        loading: _loading,
        onPressed: _prepare,
      ),
      children: [
        const FieldLabel('CV'),
        SelectableOption(
          title: _cvId == null ? 'Choix automatique' : (selected?.title ?? 'CV sélectionné'),
          subtitle: _cvId == null
              ? 'Le CV le plus adapté à cette offre'
              : selected?.originalFilename,
          icon: Icons.description_outlined,
          badge: selected?.isPrimary == true ? 'Principal' : null,
          selected: true,
          onTap: _loading ? null : _pickCv,
        ),
        if (_cvId == null) ...[
          const Gap(14),
          const FieldLabel('Langue du CV', optional: true),
          ChoiceChips<String?>(
            values: [null, ...kDocumentLanguages.keys],
            selected: _language,
            labelOf: (code) => code == null ? 'Indifférente' : languageLabel(code),
            onSelected: (code) => setState(() => _language = code),
          ),
        ],
        const Gap(20),
        const FieldLabel('Brouillons'),
        SwitchRow(
          title: 'Rédiger la lettre de motivation',
          subtitle: _app.coverLetterText != null ? 'Déjà rédigée : elle sera conservée.' : null,
          value: _letter,
          onChanged: _loading ? null : (value) => setState(() => _letter = value),
        ),
        SwitchRow(
          title: 'Rédiger l\'email de candidature',
          subtitle: _app.emailBody != null ? 'Déjà rédigé : il sera conservé.' : null,
          value: _email,
          onChanged: _loading ? null : (value) => setState(() => _email = value),
        ),
        if (ai != null && !ai.enabled) ...[
          const Gap(12),
          const NoticeBanner(
            message: 'IA non configurée : les textes seront créés à partir de modèles, '
                'à personnaliser ensuite.',
          ),
        ],
        if (_error != null) ...[
          const Gap(12),
          NoticeBanner(
            message: _error!,
            color: AppColors.danger,
            icon: Icons.error_outline_rounded,
          ),
        ],
        const Gap(8),
        Text(
          'Vous pourrez modifier le CV, la lettre et l\'email avant l\'envoi.',
          style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
        ),
      ],
    );
  }
}
