import '../../../core/models/enums.dart';
import '../../../core/utils/json.dart';

/// Entreprise (`CompanyRead`).
class Company {
  const Company({
    required this.id,
    required this.name,
    this.website,
    this.logoUrl,
    this.description,
    this.industry,
    this.employeeCount,
    this.address,
    this.postalCode,
    this.city,
    this.country,
    this.email,
    this.phone,
    this.linkedinUrl,
    this.facebookUrl,
    this.instagramUrl,
    this.dataSourceValue,
    this.sourceId,
    this.sourceUrl,
    this.fieldSources = const {},
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String? website;
  final String? logoUrl;
  final String? description;
  final String? industry;
  final String? employeeCount;
  final String? address;
  final String? postalCode;
  final String? city;
  final String? country;
  final String? email;
  final String? phone;
  final String? linkedinUrl;
  final String? facebookUrl;
  final String? instagramUrl;
  final String? dataSourceValue;
  final String? sourceId;
  final String? sourceUrl;

  /// Provenance de chaque champ collecté : `{"email": "https://exemple.com/contact"}`.
  final Map<String, dynamic> fieldSources;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  DataOrigin? get dataSource => DataOrigin.fromApi(dataSourceValue);

  /// `Paris, France`
  String? get locationLabel {
    final parts = [city, country].whereType<String>().where((e) => e.trim().isNotEmpty);
    return parts.isEmpty ? null : parts.join(', ');
  }

  /// `Logiciel · Paris, France`
  String? get subtitle {
    final parts = [industry, locationLabel].whereType<String>().where((e) => e.trim().isNotEmpty);
    return parts.isEmpty ? null : parts.join(' · ');
  }

  factory Company.fromJson(Map<String, dynamic> json) => Company(
    id: json['id'] as String,
    name: json['name']?.toString() ?? '',
    website: json['website'] as String?,
    logoUrl: json['logo_url'] as String?,
    description: json['description'] as String?,
    industry: json['industry'] as String?,
    employeeCount: json['employee_count'] as String?,
    address: json['address'] as String?,
    postalCode: json['postal_code'] as String?,
    city: json['city'] as String?,
    country: json['country'] as String?,
    email: json['email'] as String?,
    phone: json['phone'] as String?,
    linkedinUrl: json['linkedin_url'] as String?,
    facebookUrl: json['facebook_url'] as String?,
    instagramUrl: json['instagram_url'] as String?,
    dataSourceValue: json['data_source']?.toString(),
    sourceId: json['source_id']?.toString(),
    sourceUrl: json['source_url'] as String?,
    fieldSources: parseMap(json['field_sources']),
    createdAt: parseDate(json['created_at']),
    updatedAt: parseDate(json['updated_at']),
  );

  /// Valeurs modifiables, par nom de champ API (pour construire les mises à jour).
  Map<String, String?> get editableValues => {
    'name': name,
    'website': website,
    'logo_url': logoUrl,
    'description': description,
    'industry': industry,
    'employee_count': employeeCount,
    'address': address,
    'postal_code': postalCode,
    'city': city,
    'country': country,
    'email': email,
    'phone': phone,
    'linkedin_url': linkedinUrl,
    'facebook_url': facebookUrl,
    'instagram_url': instagramUrl,
    'source_url': sourceUrl,
  };
}

/// Recruteur (`RecruiterRead`).
class Recruiter {
  const Recruiter({
    required this.id,
    this.name,
    this.firstName,
    this.lastName,
    this.jobTitle,
    this.email,
    this.phone,
    this.linkedinUrl,
    this.website,
    this.companyId,
    this.contactSourceValue,
    this.sourceUrl,
    this.notes,
    this.createdAt,
    this.updatedAt,
  });

  final String id;

  /// Nom affiché calculé par le serveur.
  final String? name;
  final String? firstName;
  final String? lastName;
  final String? jobTitle;
  final String? email;
  final String? phone;
  final String? linkedinUrl;
  final String? website;
  final String? companyId;
  final String? contactSourceValue;
  final String? sourceUrl;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  ContactSource? get contactSource => ContactSource.fromApi(contactSourceValue);

  bool get hasContact => (email?.isNotEmpty ?? false) || (phone?.isNotEmpty ?? false);

  String get displayName {
    if (name != null && name!.trim().isNotEmpty) return name!.trim();
    final full = [firstName, lastName].whereType<String>().where((e) => e.trim().isNotEmpty);
    if (full.isNotEmpty) return full.join(' ');
    if (email != null && email!.isNotEmpty) return email!;
    return 'Recruteur sans nom';
  }

  factory Recruiter.fromJson(Map<String, dynamic> json) => Recruiter(
    id: json['id'] as String,
    name: json['name'] as String?,
    firstName: json['first_name'] as String?,
    lastName: json['last_name'] as String?,
    jobTitle: json['job_title'] as String?,
    email: json['email'] as String?,
    phone: json['phone'] as String?,
    linkedinUrl: json['linkedin_url'] as String?,
    website: json['website'] as String?,
    companyId: json['company_id']?.toString(),
    contactSourceValue: json['contact_source']?.toString(),
    sourceUrl: json['source_url'] as String?,
    notes: json['notes'] as String?,
    createdAt: parseDate(json['created_at']),
    updatedAt: parseDate(json['updated_at']),
  );

  /// Valeurs modifiables, par nom de champ API. `name` n'est pas renvoyé tel quel par le
  /// serveur (nom affiché calculé) : il n'est repris que s'il n'y a ni prénom ni nom.
  Map<String, String?> get editableValues => {
    'name': (firstName == null && lastName == null) ? name : null,
    'first_name': firstName,
    'last_name': lastName,
    'job_title': jobTitle,
    'email': email,
    'phone': phone,
    'linkedin_url': linkedinUrl,
    'website': website,
    'company_id': companyId,
    'contact_source': contactSourceValue,
    'source_url': sourceUrl,
    'notes': notes,
  };
}

/// Provenances qui exigent l'URL de la page publique (règle serveur RG-07).
const sourcesRequiringUrl = {ContactSource.companyWebsite, ContactSource.publicProfile};

/// Vérifie la règle de provenance des coordonnées avant l'envoi. Renvoie un message ou null.
String? checkContactProvenance({
  String? email,
  String? phone,
  ContactSource? contactSource,
  String? sourceUrl,
}) {
  final hasContact = (email?.trim().isNotEmpty ?? false) || (phone?.trim().isNotEmpty ?? false);
  if (hasContact && contactSource == null) {
    return 'Indiquez la provenance du contact (email ou téléphone renseigné).';
  }
  if (sourcesRequiringUrl.contains(contactSource) && (sourceUrl?.trim().isEmpty ?? true)) {
    return 'L\'URL source est obligatoire pour la provenance « ${contactSource!.label} ».';
  }
  return null;
}

/// Construit le corps d'une mise à jour partielle : seuls les champs modifiés sont envoyés
/// (une chaîne vide efface la valeur). Côté entreprises, cela préserve la provenance des
/// champs collectés non modifiés.
Map<String, dynamic> changedFields(Map<String, String?> original, Map<String, String?> edited) {
  final result = <String, dynamic>{};
  edited.forEach((key, value) {
    final next = _clean(value);
    if (next != _clean(original[key])) result[key] = next;
  });
  return result;
}

/// Corps d'une création : champs renseignés uniquement.
Map<String, dynamic> filledFields(Map<String, String?> values) => {
  for (final entry in values.entries)
    if (_clean(entry.value) != null) entry.key: _clean(entry.value),
};

String? _clean(String? value) {
  final text = value?.trim();
  return (text == null || text.isEmpty) ? null : text;
}
