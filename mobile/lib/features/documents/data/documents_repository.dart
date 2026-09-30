import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/enums.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/paginated.dart';
import 'document_models.dart';

/// Métadonnées d'un envoi de document (`POST /documents`, multipart).
class DocumentUploadFields {
  const DocumentUploadFields({
    required this.type,
    this.title,
    this.language,
    this.targetJobTitle,
    this.isPrimary = false,
  });

  final DocumentType type;
  final String? title;
  final String? language;
  final String? targetJobTitle;
  final bool isPrimary;

  /// Champs du formulaire multipart (les valeurs vides sont retirées par l'ApiClient).
  Map<String, dynamic> toFields() => {
    'document_type': type.apiValue,
    'title': title?.trim(),
    'language': language,
    'target_job_title': targetJobTitle?.trim(),
    'is_primary': isPrimary.toString(),
  };
}

/// Accès à l'API des documents.
class DocumentsRepository {
  DocumentsRepository(this._api);

  final ApiClient _api;

  Future<Paginated<UserDocument>> list({
    int page = 1,
    int pageSize = 20,
    DocumentType? type,
    bool? isActive,
  }) => _api.getPage(
    '/documents',
    UserDocument.fromJson,
    page: page,
    pageSize: pageSize,
    query: {'document_type': type?.apiValue, 'is_active': isActive},
  );

  Future<UserDocument> get(String id) => _api.getObject('/documents/$id', UserDocument.fromJson);

  /// Envoi depuis un chemin local (avec progression).
  Future<UserDocument> uploadFile({
    required String filePath,
    required String filename,
    required DocumentUploadFields fields,
    void Function(int sent, int total)? onProgress,
  }) async => UserDocument.fromJson(
    asJsonMap(
      await _api.upload(
        '/documents',
        filePath: filePath,
        filename: filename,
        fields: fields.toFields(),
        onProgress: onProgress,
      ),
    ),
  );

  /// Envoi depuis des octets (fichier sans chemin local, ex. `content://` sur Android).
  Future<UserDocument> uploadBytes({
    required Uint8List bytes,
    required String filename,
    required DocumentUploadFields fields,
  }) async => UserDocument.fromJson(
    asJsonMap(
      await _api.uploadBytes(
        '/documents',
        bytes: bytes,
        filename: filename,
        fields: fields.toFields(),
      ),
    ),
  );

  Future<UserDocument> update(String id, DocumentUpdate data) async =>
      UserDocument.fromJson(asJsonMap(await _api.patch('/documents/$id', body: data.toJson())));

  Future<void> delete(String id) => _api.delete('/documents/$id');

  Future<Uint8List> download(UserDocument document) => _api.download(document.downloadPath);
}

final documentsRepositoryProvider = Provider<DocumentsRepository>(
  (ref) => DocumentsRepository(ref.watch(apiClientProvider)),
);

/// CV actifs (choix du CV d'une candidature), le principal en premier.
final cvDocumentsProvider = FutureProvider.autoDispose<List<UserDocument>>((ref) async {
  final page = await ref
      .watch(documentsRepositoryProvider)
      .list(type: DocumentType.cv, isActive: true, pageSize: 100);
  return page.items;
});

/// Un document par identifiant (ex. CV rattaché à une candidature).
final documentProvider = FutureProvider.autoDispose.family<UserDocument, String>(
  (ref, id) => ref.watch(documentsRepositoryProvider).get(id),
);
