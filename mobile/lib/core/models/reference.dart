import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_client.dart';
import '../utils/json.dart';

/// Données de référence partagées par plusieurs écrans (types de contrat, niveaux,
/// catégories de compétences, état de l'IA). Chargées une fois puis gardées en cache.

class ContractType {
  const ContractType({
    required this.id,
    required this.code,
    required this.name,
    this.description,
    this.aliases = const [],
    this.isActive = true,
    this.sortOrder = 0,
  });

  final String id;
  final String code;
  final String name;
  final String? description;
  final List<String> aliases;
  final bool isActive;
  final int sortOrder;

  factory ContractType.fromJson(Map<String, dynamic> json) => ContractType(
    id: json['id'] as String,
    code: json['code'] as String,
    name: json['name'] as String,
    description: json['description'] as String?,
    aliases: parseStringList(json['aliases']),
    isActive: json['is_active'] as bool? ?? true,
    sortOrder: parseInt(json['sort_order']) ?? 0,
  );
}

class ExperienceLevel {
  const ExperienceLevel({
    required this.id,
    required this.code,
    required this.name,
    required this.rank,
    required this.minYears,
    this.aliases = const [],
    this.description,
  });

  final String id;
  final String code;
  final String name;
  final int rank;
  final int minYears;
  final List<String> aliases;
  final String? description;

  factory ExperienceLevel.fromJson(Map<String, dynamic> json) => ExperienceLevel(
    id: json['id'] as String,
    code: json['code'] as String,
    name: json['name'] as String,
    rank: parseInt(json['rank']) ?? 0,
    minYears: parseInt(json['min_years']) ?? 0,
    aliases: parseStringList(json['aliases']),
    description: json['description'] as String?,
  );
}

class SkillCategory {
  const SkillCategory({required this.id, required this.code, required this.name, this.description});

  final String id;
  final String code;
  final String name;
  final String? description;

  factory SkillCategory.fromJson(Map<String, dynamic> json) => SkillCategory(
    id: json['id'] as String,
    code: json['code'] as String,
    name: json['name'] as String,
    description: json['description'] as String?,
  );
}

/// Compétence du catalogue (`CatalogSkillRead`).
class CatalogSkill {
  const CatalogSkill({required this.id, required this.name, this.category, this.aliases = const []});

  final String id;
  final String name;
  final String? category;
  final List<String> aliases;

  factory CatalogSkill.fromJson(Map<String, dynamic> json) => CatalogSkill(
    id: json['id'] as String,
    name: json['name'] as String,
    category: json['category'] as String?,
    aliases: parseStringList(json['aliases']),
  );
}

class AiStatus {
  const AiStatus({required this.enabled, required this.provider, this.model});

  final bool enabled;
  final String provider;
  final String? model;

  factory AiStatus.fromJson(Map<String, dynamic> json) => AiStatus(
    enabled: json['enabled'] as bool? ?? false,
    provider: json['provider']?.toString() ?? 'none',
    model: json['model'] as String?,
  );
}

/// Types de contrat actifs, triés.
final contractTypesProvider = FutureProvider<List<ContractType>>((ref) async {
  final items = await ref.watch(apiClientProvider).getList('/contract-types', ContractType.fromJson);
  return items..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
});

/// Niveaux d'expérience, triés par rang.
final experienceLevelsProvider = FutureProvider<List<ExperienceLevel>>((ref) async {
  final items = await ref
      .watch(apiClientProvider)
      .getList('/experience-levels', ExperienceLevel.fromJson);
  return items..sort((a, b) => a.rank.compareTo(b.rank));
});

final skillCategoriesProvider = FutureProvider<List<SkillCategory>>(
  (ref) => ref.watch(apiClientProvider).getList('/skills/categories', SkillCategory.fromJson),
);

/// État de l'IA côté serveur (fonctions « Analyser » / « Générer »).
final aiStatusProvider = FutureProvider<AiStatus>(
  (ref) => ref.watch(apiClientProvider).getObject('/ai/status', AiStatus.fromJson),
);
