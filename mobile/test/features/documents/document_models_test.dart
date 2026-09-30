import 'package:flutter_test/flutter_test.dart';
import 'package:garrix_offre/core/models/enums.dart';
import 'package:garrix_offre/features/documents/data/document_models.dart';
import 'package:garrix_offre/features/documents/data/documents_repository.dart';

void main() {
  group('UserDocument', () {
    test('lit un document (réponse réelle de POST /documents)', () {
      final doc = UserDocument.fromJson(const {
        'id': '393ece78-2f9b-4deb-8362-8e6782d220a7',
        'document_type': 'cv',
        'title': 'CV test',
        'original_filename': 'test_cv.pdf',
        'mime_type': 'application/pdf',
        'extension': 'pdf',
        'size_bytes': 45,
        'language': 'fr',
        'target_job_title': null,
        'is_active': true,
        'is_primary': true,
        'created_at': '2026-09-30T08:43:41.719552Z',
        'download_url': '/api/v1/documents/393ece78-2f9b-4deb-8362-8e6782d220a7/download',
      });
      expect(doc.type, DocumentType.cv);
      expect(doc.title, 'CV test');
      expect(doc.sizeBytes, 45);
      expect(doc.language, 'fr');
      expect(doc.targetJobTitle, isNull);
      expect(doc.isPrimary, isTrue);
      expect(doc.isImage, isFalse);
      expect(doc.downloadPath, '/documents/393ece78-2f9b-4deb-8362-8e6782d220a7/download');
    });

    test('valeurs de repli et nom de fichier sûr', () {
      final doc = UserDocument.fromJson(const {
        'id': 'd2',
        'document_type': 'inconnu',
        'title': '',
        'original_filename': 'Mon CV (v2)/final.PNG',
      });
      expect(doc.type, DocumentType.other);
      expect(doc.title, 'Mon CV (v2)/final.PNG');
      expect(doc.extension, 'png');
      expect(doc.isImage, isTrue);
      expect(doc.isActive, isTrue);
      expect(doc.safeFilename, 'Mon CV _v2__final.PNG');
    });
  });

  group('Extensions autorisées (validation.py)', () {
    test('par type de document', () {
      expect(isExtensionAllowed(DocumentType.cv, 'cv.PDF'), isTrue);
      expect(isExtensionAllowed(DocumentType.cv, 'cv.txt'), isFalse);
      expect(isExtensionAllowed(DocumentType.coverLetter, 'lettre.txt'), isTrue);
      expect(isExtensionAllowed(DocumentType.photo, 'moi.webp'), isTrue);
      expect(isExtensionAllowed(DocumentType.photo, 'moi.pdf'), isFalse);
      expect(isExtensionAllowed(DocumentType.other, 'sans_extension'), isFalse);
      expect(kAllowedExtensions.keys, containsAll(DocumentType.values));
    });
  });

  group('Écritures', () {
    test('modification : les valeurs vides effacent langue et poste', () {
      expect(
        DocumentUpdate.details(title: ' CV 2026 ', language: null, targetJobTitle: '  ').toJson(),
        {'title': 'CV 2026', 'language': null, 'target_job_title': null},
      );
      expect(DocumentUpdate.primary().toJson(), {'is_primary': true});
      expect(DocumentUpdate.active(false).toJson(), {'is_active': false});
    });

    test('champs du formulaire d\'envoi', () {
      expect(
        const DocumentUploadFields(
          type: DocumentType.coverLetter,
          title: ' Lettre ',
          language: 'en',
          isPrimary: true,
        ).toFields(),
        {
          'document_type': 'cover_letter',
          'title': 'Lettre',
          'language': 'en',
          'target_job_title': null,
          'is_primary': 'true',
        },
      );
    });
  });
}
