import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/enums.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/ui.dart';
import '../../applications/widgets/common.dart';
import '../data/document_models.dart';
import '../data/documents_repository.dart';

/// Modifier le titre, la langue et le poste ciblé d'un document. Renvoie le document modifié.
class EditDocumentSheet extends ConsumerStatefulWidget {
  const EditDocumentSheet({super.key, required this.document});

  final UserDocument document;

  @override
  ConsumerState<EditDocumentSheet> createState() => _EditDocumentSheetState();
}

class _EditDocumentSheetState extends ConsumerState<EditDocumentSheet> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _target;
  late String? _language = widget.document.language;
  bool _loading = false;
  String? _error;

  UserDocument get _doc => widget.document;

  bool get _hasTarget => _doc.type == DocumentType.cv || _doc.type == DocumentType.coverLetter;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: _doc.title);
    _target = TextEditingController(text: _doc.targetJobTitle);
  }

  @override
  void dispose() {
    _title.dispose();
    _target.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final updated = await ref
          .read(documentsRepositoryProvider)
          .update(
            _doc.id,
            DocumentUpdate.details(
              title: _title.text,
              language: _language,
              targetJobTitle: _hasTarget ? _target.text : _doc.targetJobTitle,
            ),
          );
      if (mounted) Navigator.of(context).pop(updated);
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
    final languages = <String?>[
      null,
      ...kDocumentLanguages.keys,
      if (_doc.language != null && !kDocumentLanguages.containsKey(_doc.language)) _doc.language,
    ];
    return Form(
      key: _form,
      child: SheetLayout(
        title: 'Modifier le document',
        subtitle: _doc.originalFilename,
        footer: PrimaryButton(label: 'Enregistrer', loading: _loading, onPressed: _save),
        children: [
          AppTextField(
            label: 'Titre',
            controller: _title,
            validator: Validators.required,
            maxLength: 200,
          ),
          formGap,
          const FieldLabel('Langue', optional: true),
          ChoiceChips<String?>(
            values: languages,
            selected: _language,
            labelOf: (code) => code == null ? 'Non précisée' : languageLabel(code),
            onSelected: (code) => setState(() => _language = code),
          ),
          if (_hasTarget) ...[
            formGap,
            AppTextField(
              label: 'Poste ciblé',
              optional: true,
              controller: _target,
              maxLength: 200,
            ),
          ],
          if (_error != null) ...[
            const Gap(12),
            NoticeBanner(message: _error!, color: AppColors.danger, icon: Icons.error_outline_rounded),
          ],
        ],
      ),
    );
  }
}
