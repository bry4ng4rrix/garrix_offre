import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/ui.dart';
import '../../documents/data/document_models.dart';
import '../../documents/data/documents_repository.dart';
import 'common.dart';

/// Choix d'un CV parmi les documents actifs.
///
/// Renvoie `(id: ...)` : l'identifiant choisi, ou `(id: null)` pour « aucun » / « automatique »
/// selon [noneLabel]. Renvoie null si la feuille est fermée sans choix.
class CvPickerSheet extends ConsumerWidget {
  const CvPickerSheet({super.key, this.selectedId, this.noneLabel = 'Aucun CV', this.noneSubtitle});

  final String? selectedId;
  final String noneLabel;
  final String? noneSubtitle;

  void _manageDocuments(BuildContext context) {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.push(Routes.documents);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cvs = ref.watch(cvDocumentsProvider);
    return SheetLayout(
      title: 'Choisir un CV',
      footer: TextButton.icon(
        onPressed: () => _manageDocuments(context),
        icon: const Icon(Icons.folder_open_outlined, size: 18),
        label: const Text('Gérer mes documents'),
      ),
      children: [
        AsyncValueView<List<UserDocument>>(
          value: cvs,
          onRetry: () => ref.invalidate(cvDocumentsProvider),
          data: (items) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SelectableOption(
                title: noneLabel,
                subtitle: noneSubtitle,
                icon: Icons.block_rounded,
                selected: selectedId == null,
                onTap: () => Navigator.of(context).pop((id: null)),
              ),
              for (final cv in items) ...[
                const Gap(8),
                SelectableOption(
                  title: cv.title,
                  subtitle: [
                    cv.originalFilename,
                    if (cv.language != null) languageLabel(cv.language!),
                    if (cv.targetJobTitle != null) cv.targetJobTitle!,
                    Fmt.fileSize(cv.sizeBytes),
                  ].join(' · '),
                  icon: Icons.description_outlined,
                  badge: cv.isPrimary ? 'Principal' : null,
                  selected: cv.id == selectedId,
                  onTap: () => Navigator.of(context).pop((id: cv.id)),
                ),
              ],
              if (items.isEmpty) ...[
                const Gap(16),
                NoticeBanner(
                  message: 'Vous n\'avez pas encore de CV. Ajoutez-en un depuis vos documents.',
                  actionLabel: 'Ajouter un CV',
                  onAction: () => _manageDocuments(context),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
