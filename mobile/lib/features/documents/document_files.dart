import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/widgets/feedback.dart';
import 'data/document_models.dart';
import 'data/documents_repository.dart';

/// Téléchargement et ouverture des documents (fichiers privés, token requis).
class DocumentFiles {
  DocumentFiles(this._repository);

  final DocumentsRepository _repository;

  /// Enregistrer une copie n'a de sens que sur ordinateur (sur mobile : « Ouvrir » puis partager).
  static bool get canSaveCopy => Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  /// Télécharge le document dans le dossier temporaire puis l'ouvre avec l'application par défaut.
  Future<void> open(UserDocument document) async {
    final directory = Directory('${(await getTemporaryDirectory()).path}/garrix_documents');
    await directory.create(recursive: true);
    final file = File('${directory.path}/${document.id.substring(0, 8)}_${document.safeFilename}');
    await file.writeAsBytes(await _repository.download(document), flush: true);
    final result = await OpenFilex.open(file.path);
    switch (result.type) {
      case ResultType.done:
        break;
      case ResultType.noAppToOpen:
        showToast('Aucune application ne peut ouvrir ce fichier.', kind: ToastKind.error);
      case ResultType.fileNotFound:
        showToast('Fichier introuvable après le téléchargement.', kind: ToastKind.error);
      case ResultType.permissionDenied:
        showToast('Permission refusée pour ouvrir le fichier.', kind: ToastKind.error);
      case ResultType.error:
        showToast('Impossible d\'ouvrir le fichier.', kind: ToastKind.error);
    }
  }

  /// Enregistre une copie dans « Téléchargements » (ou le dossier Documents). Renvoie le chemin.
  Future<String> saveCopy(UserDocument document) async {
    final directory = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    await directory.create(recursive: true);
    final file = _uniqueFile(directory.path, document.safeFilename);
    await file.writeAsBytes(await _repository.download(document), flush: true);
    return file.path;
  }

  /// `cv.pdf`, puis `cv (1).pdf`, `cv (2).pdf`... si le fichier existe déjà.
  static File _uniqueFile(String directory, String filename) {
    final dot = filename.lastIndexOf('.');
    final base = dot > 0 ? filename.substring(0, dot) : filename;
    final extension = dot > 0 ? filename.substring(dot) : '';
    var candidate = File('$directory/$filename');
    for (var i = 1; candidate.existsSync(); i++) {
      candidate = File('$directory/$base ($i)$extension');
    }
    return candidate;
  }
}

final documentFilesProvider = Provider<DocumentFiles>(
  (ref) => DocumentFiles(ref.watch(documentsRepositoryProvider)),
);
