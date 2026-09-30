import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/enums.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/ui.dart';
import '../../applications/widgets/common.dart';
import '../data/document_models.dart';
import '../data/documents_repository.dart';

/// Ajout d'un document (multipart `POST /documents`). Renvoie le document créé.
class UploadDocumentSheet extends ConsumerStatefulWidget {
  const UploadDocumentSheet({super.key, this.initialType});

  final DocumentType? initialType;

  @override
  ConsumerState<UploadDocumentSheet> createState() => _UploadDocumentSheetState();
}

class _UploadDocumentSheetState extends ConsumerState<UploadDocumentSheet> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _target = TextEditingController();
  late DocumentType _type = widget.initialType ?? DocumentType.cv;
  PlatformFile? _file;
  int? _size;
  String? _language;
  bool _primary = false;
  bool _loading = false;
  double? _progress;
  String? _error;

  bool get _hasTarget => _type == DocumentType.cv || _type == DocumentType.coverLetter;

  List<String> get _extensions => kAllowedExtensions[_type]!;

  @override
  void dispose() {
    _title.dispose();
    _target.dispose();
    super.dispose();
  }

  void _setType(DocumentType type) => setState(() {
    _type = type;
    _error = null;
    // Le fichier choisi n'est peut-être plus accepté pour ce type.
    if (_file != null && !isExtensionAllowed(type, _file!.name)) {
      _file = null;
      _size = null;
    }
  });

  Future<void> _pick() async {
    PlatformFile? file;
    try {
      file = await FilePicker.pickFile(
        dialogTitle: 'Choisir un fichier',
        type: FileType.custom,
        allowedExtensions: _extensions,
      );
    } catch (_) {
      setState(() => _error = 'Impossible d\'ouvrir le sélecteur de fichiers.');
      return;
    }
    if (file == null || !mounted) return;
    if (!isExtensionAllowed(_type, file.name)) {
      setState(() => _error = 'Format non accepté pour ce type : ${_extensions.join(', ')}.');
      return;
    }
    final size = file.lengthSync() ?? await file.length();
    if (!mounted) return;
    setState(() {
      _file = file;
      _size = size;
      _error = null;
      if (_title.text.trim().isEmpty) {
        final dot = file!.name.lastIndexOf('.');
        _title.text = dot > 0 ? file.name.substring(0, dot) : file.name;
      }
    });
  }

  Future<void> _upload() async {
    final file = _file;
    if (file == null) {
      setState(() => _error = 'Choisissez d\'abord un fichier.');
      return;
    }
    if (!_form.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _progress = null;
      _error = null;
    });
    final repository = ref.read(documentsRepositoryProvider);
    final fields = DocumentUploadFields(
      type: _type,
      title: _title.text,
      language: _language,
      targetJobTitle: _hasTarget ? _target.text : null,
      isPrimary: _primary,
    );
    try {
      final path = file.path;
      final created = path != null
          ? await repository.uploadFile(
              filePath: path,
              filename: file.name,
              fields: fields,
              onProgress: (sent, total) {
                if (mounted && total > 0) setState(() => _progress = sent / total);
              },
            )
          // Pas de chemin local (ex. contenu Android) : envoi des octets.
          : await repository.uploadBytes(
              bytes: await file.readAsBytes(),
              filename: file.name,
              fields: fields,
            );
      if (mounted) Navigator.of(context).pop(created);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ApiException.describe(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final file = _file;
    return Form(
      key: _form,
      child: SheetLayout(
        title: 'Ajouter un document',
        expand: true,
        footer: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_loading && _progress != null) ...[ThinProgress(value: _progress!), const Gap(10)],
            PrimaryButton(
              label: _loading && _progress != null
                  ? 'Envoi... ${(_progress! * 100).round()} %'
                  : 'Envoyer',
              icon: Icons.upload_rounded,
              loading: _loading && _progress == null,
              onPressed: _loading ? null : _upload,
            ),
          ],
        ),
        children: [
          const FieldLabel('Type'),
          ChoiceChips<DocumentType>(
            values: DocumentType.values,
            selected: _type,
            labelOf: (type) => type.label,
            onSelected: (type) {
              if (type != null && !_loading) _setType(type);
            },
          ),
          formGap,
          const FieldLabel('Fichier'),
          SelectableOption(
            title: file?.name ?? 'Choisir un fichier',
            subtitle: file == null
                ? 'Formats : ${_extensions.map((e) => e.toUpperCase()).join(', ')}'
                : '${Fmt.fileSize(_size)} · touchez pour changer',
            icon: file == null ? Icons.upload_file_rounded : Icons.insert_drive_file_outlined,
            selected: file != null,
            onTap: _loading ? null : _pick,
          ),
          formGap,
          AppTextField(
            label: 'Titre',
            controller: _title,
            hint: 'CV développeur 2026',
            validator: Validators.required,
            maxLength: 200,
          ),
          formGap,
          const FieldLabel('Langue', optional: true),
          ChoiceChips<String?>(
            values: [null, ...kDocumentLanguages.keys],
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
              hint: 'Développeur Flutter',
              helper: 'Aide à choisir le bon CV pour chaque offre.',
              maxLength: 200,
            ),
          ],
          const Gap(8),
          SwitchRow(
            title: 'Document principal',
            subtitle: 'Proposé par défaut pour ce type de document',
            value: _primary,
            onChanged: _loading ? null : (value) => setState(() => _primary = value),
          ),
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
            'Le contenu du fichier est vérifié par le serveur. Vos documents sont privés.',
            style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}
