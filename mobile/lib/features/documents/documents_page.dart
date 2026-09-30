import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/enums.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/paged_list_view.dart';
import '../../core/widgets/ui.dart';
import '../applications/widgets/common.dart';
import 'data/document_models.dart';
import 'data/documents_repository.dart';
import 'document_files.dart';
import 'widgets/document_card.dart';
import 'widgets/edit_document_sheet.dart';
import 'widgets/upload_document_sheet.dart';

enum _DocAction { open, save, edit, primary, toggleActive, delete }

/// Mes documents : CV, lettres, photos. Le document principal de chaque type est proposé par défaut.
class DocumentsPage extends ConsumerStatefulWidget {
  const DocumentsPage({super.key});

  @override
  ConsumerState<DocumentsPage> createState() => _DocumentsPageState();
}

class _DocumentsPageState extends ConsumerState<DocumentsPage> {
  final _list = PagedListController();
  DocumentType? _filter;

  DocumentsRepository get _repository => ref.read(documentsRepositoryProvider);

  /// Les listes de CV (choix du CV d'une candidature) suivent les changements.
  void _changed() {
    if (mounted) ref.invalidate(cvDocumentsProvider);
  }

  void _replace(UserDocument updated) {
    if (!mounted) return;
    _list.updateWhere<UserDocument>((d) => d.id == updated.id, (_) => updated);
    ref.invalidate(documentProvider(updated.id));
    _changed();
  }

  Future<void> _upload() async {
    final created = await showAppSheet<UserDocument>(
      context,
      expand: true,
      builder: (_) => UploadDocumentSheet(initialType: _filter),
    );
    if (created == null || !mounted) return;
    showToast('Document ajouté', kind: ToastKind.success);
    _changed();
    await _list.refresh();
  }

  Future<void> _open(UserDocument document) => runWithProgress(
    context,
    () => ref.read(documentFilesProvider).open(document),
    message: 'Téléchargement...',
  );

  Future<void> _actions(UserDocument document) async {
    final action = await showAppSheet<_DocAction>(
      context,
      builder: (_) => _ActionsSheet(document: document),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _DocAction.open:
        await _open(document);
      case _DocAction.save:
        final path = await runWithProgress(
          context,
          () => ref.read(documentFilesProvider).saveCopy(document),
          message: 'Téléchargement...',
        );
        if (path != null) showToast('Enregistré : $path', kind: ToastKind.success);
      case _DocAction.edit:
        final updated = await showAppSheet<UserDocument>(
          context,
          builder: (_) => EditDocumentSheet(document: document),
        );
        if (updated != null) {
          _replace(updated);
          showToast('Document modifié', kind: ToastKind.success);
        }
      case _DocAction.primary:
        final updated = await runAction(
          () => _repository.update(document.id, DocumentUpdate.primary()),
          success: 'Document principal : ${document.title}',
        );
        if (updated != null) {
          // Le serveur retire le statut « principal » aux autres documents du même type.
          _changed();
          await _list.refresh();
        }
      case _DocAction.toggleActive:
        final updated = await runAction(
          () => _repository.update(document.id, DocumentUpdate.active(!document.isActive)),
          success: document.isActive ? 'Document désactivé' : 'Document réactivé',
        );
        if (updated != null) _replace(updated);
      case _DocAction.delete:
        await _delete(document);
    }
  }

  Future<void> _delete(UserDocument document) async {
    final ok = await confirmDialog(
      context,
      title: 'Supprimer « ${document.title} » ?',
      message:
          'Le fichier sera définitivement supprimé. Les candidatures qui l\'utilisent '
          'n\'auront plus ce document.',
      confirmLabel: 'Supprimer',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final done = await runAction(() async {
      await _repository.delete(document.id);
      return true;
    }, success: 'Document supprimé');
    if (done == true) {
      _list.removeWhere<UserDocument>((d) => d.id == document.id);
      _changed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(documentsRepositoryProvider);
    final theme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Documents')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _upload,
        icon: const Icon(Icons.upload_file_rounded),
        label: const Text('Ajouter'),
      ),
      body: PagedListView<UserDocument>(
        key: ValueKey(_filter),
        controller: _list,
        fetch: (page) => repository.list(page: page, type: _filter),
        header: [
          Text(
            'Vos CV et lettres servent à préparer vos candidatures. Le document principal '
            'de chaque type est proposé par défaut.',
            style: theme.bodyMedium?.copyWith(color: AppColors.textSecondary),
          ),
          const Gap(16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final type in <DocumentType?>[null, ...DocumentType.values])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(type == null ? 'Tous' : _pluralLabel(type)),
                      selected: type == _filter,
                      labelStyle: TextStyle(
                        color: type == _filter ? AppColors.onAccent : AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                      onSelected: (_) => setState(() => _filter = type),
                    ),
                  ),
              ],
            ),
          ),
          const Gap(14),
        ],
        itemBuilder: (context, document) => DocumentCard(
          document: document,
          showType: _filter == null,
          onTap: () => _open(document),
          onMore: () => _actions(document),
        ),
        emptyBuilder: (context) => EmptyState(
          icon: _filter?.icon ?? Icons.folder_open_outlined,
          title: _filter == null ? 'Aucun document' : 'Aucun document de ce type',
          message: 'Ajoutez votre CV pour préparer vos candidatures plus vite.',
          actionLabel: 'Ajouter un document',
          onAction: _upload,
        ),
      ),
    );
  }
}

String _pluralLabel(DocumentType type) => switch (type) {
  DocumentType.cv => 'CV',
  DocumentType.coverLetter => 'Lettres',
  DocumentType.photo => 'Photos',
  DocumentType.other => 'Autres',
};

/// Actions sur un document (renvoie l'action choisie).
class _ActionsSheet extends StatelessWidget {
  const _ActionsSheet({required this.document});
  final UserDocument document;

  @override
  Widget build(BuildContext context) {
    void pick(_DocAction action) => Navigator.of(context).pop(action);
    return SheetLayout(
      title: document.title,
      subtitle: document.originalFilename,
      children: [
        MenuGroup(
          children: [
            MenuTile(
              icon: Icons.open_in_new_rounded,
              title: 'Ouvrir',
              onTap: () => pick(_DocAction.open),
            ),
            if (DocumentFiles.canSaveCopy)
              MenuTile(
                icon: Icons.download_rounded,
                title: 'Enregistrer une copie',
                subtitle: 'Dans le dossier Téléchargements',
                onTap: () => pick(_DocAction.save),
              ),
            MenuTile(
              icon: Icons.edit_outlined,
              title: 'Modifier',
              subtitle: 'Titre, langue, poste ciblé',
              onTap: () => pick(_DocAction.edit),
            ),
            if (!document.isPrimary && document.isActive)
              MenuTile(
                icon: Icons.star_outline_rounded,
                title: 'Définir comme principal',
                subtitle: 'Proposé par défaut pour ce type',
                onTap: () => pick(_DocAction.primary),
              ),
            MenuTile(
              icon: document.isActive ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              title: document.isActive ? 'Désactiver' : 'Réactiver',
              subtitle: document.isActive
                  ? 'Il ne sera plus proposé pour les candidatures'
                  : 'Il sera de nouveau proposé',
              onTap: () => pick(_DocAction.toggleActive),
            ),
          ],
        ),
        const Gap(12),
        MenuGroup(
          children: [
            MenuTile(
              icon: Icons.delete_outline_rounded,
              title: 'Supprimer',
              destructive: true,
              onTap: () => pick(_DocAction.delete),
            ),
          ],
        ),
      ],
    );
  }
}
