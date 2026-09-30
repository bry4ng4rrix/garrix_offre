import '../../../core/models/enums.dart';
import '../../../core/utils/json.dart';

/// Document de l'utilisateur (`DocumentRead`) : CV, lettre, photo...
class UserDocument {
  const UserDocument({
    required this.id,
    required this.type,
    required this.title,
    required this.originalFilename,
    required this.mimeType,
    required this.extension,
    required this.sizeBytes,
    required this.isActive,
    required this.isPrimary,
    required this.createdAt,
    this.language,
    this.targetJobTitle,
  });

  final String id;
  final DocumentType type;
  final String title;
  final String originalFilename;
  final String mimeType;
  final String extension;
  final int sizeBytes;
  final String? language;
  final String? targetJobTitle;
  final bool isActive;
  final bool isPrimary;
  final DateTime createdAt;

  factory UserDocument.fromJson(Map<String, dynamic> json) {
    final filename = json['original_filename']?.toString() ?? 'document';
    return UserDocument(
      id: json['id'].toString(),
      type: DocumentType.fromApi(json['document_type']) ?? DocumentType.other,
      title: _text(json['title']) ?? filename,
      originalFilename: filename,
      mimeType: json['mime_type']?.toString() ?? 'application/octet-stream',
      extension: (json['extension']?.toString() ?? _extensionOf(filename)).toLowerCase(),
      sizeBytes: parseInt(json['size_bytes']) ?? 0,
      language: _text(json['language']),
      targetJobTitle: _text(json['target_job_title']),
      isActive: json['is_active'] as bool? ?? true,
      isPrimary: json['is_primary'] as bool? ?? false,
      createdAt: parseDate(json['created_at']) ?? DateTime.now(),
    );
  }

  /// Chemin de téléchargement (sans `/api/v1`).
  String get downloadPath => '/documents/$id/download';

  bool get isImage => type == DocumentType.photo || const {'png', 'jpg', 'jpeg', 'webp'}.contains(extension);

  /// Nom de fichier sûr pour l'enregistrement local.
  String get safeFilename {
    final cleaned = originalFilename.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_').trim();
    return cleaned.isEmpty ? 'document.$extension' : cleaned;
  }
}

/// Extensions acceptées par le serveur pour chaque type
/// (`backend/app/modules/documents/validation.py`).
const kAllowedExtensions = <DocumentType, List<String>>{
  DocumentType.cv: ['pdf', 'doc', 'docx', 'odt'],
  DocumentType.coverLetter: ['pdf', 'doc', 'docx', 'odt', 'txt'],
  DocumentType.photo: ['jpg', 'jpeg', 'png', 'webp'],
  DocumentType.other: ['pdf', 'doc', 'docx', 'odt', 'txt', 'png', 'jpg', 'jpeg', 'webp'],
};

/// L'extension de [filename] est-elle acceptée pour ce type de document ?
bool isExtensionAllowed(DocumentType type, String filename) =>
    kAllowedExtensions[type]!.contains(_extensionOf(filename));

/// Langues proposées pour un document (code ISO 639-1 accepté par l'API).
const kDocumentLanguages = <String, String>{
  'fr': 'Français',
  'en': 'Anglais',
  'mg': 'Malgache',
};

String languageLabel(String code) => kDocumentLanguages[code] ?? code.toUpperCase();

/// `PATCH /documents/{id}` — seules les clés présentes sont envoyées.
class DocumentUpdate {
  const DocumentUpdate(this.fields);

  final Map<String, Object?> fields;

  /// Titre, langue et poste ciblé (null efface la langue / le poste).
  factory DocumentUpdate.details({
    required String title,
    required String? language,
    required String? targetJobTitle,
  }) {
    final target = targetJobTitle?.trim();
    return DocumentUpdate({
      'title': title.trim(),
      'language': language,
      'target_job_title': (target == null || target.isEmpty) ? null : target,
    });
  }

  factory DocumentUpdate.primary() => const DocumentUpdate({'is_primary': true});

  factory DocumentUpdate.active(bool active) => DocumentUpdate({'is_active': active});

  Map<String, dynamic> toJson() => Map<String, dynamic>.of(fields);
}

String _extensionOf(String filename) {
  final dot = filename.lastIndexOf('.');
  return dot < 0 || dot == filename.length - 1 ? '' : filename.substring(dot + 1).toLowerCase();
}

String? _text(Object? value) {
  if (value == null) return null;
  final text = value.toString();
  return text.trim().isEmpty ? null : text;
}
