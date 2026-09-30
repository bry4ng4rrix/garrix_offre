import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/reference.dart';
import 'admin_repository.dart';
import 'directory_models.dart';
import 'monitoring_models.dart';
import 'source_models.dart';

/// État du système (hub Administration, page Système).
final systemStatusProvider = FutureProvider.autoDispose<SystemStatus>(
  (ref) => ref.watch(adminRepositoryProvider).system(),
);

/// Vue d'ensemble des collectes (page Système).
final scrapingOverviewProvider = FutureProvider.autoDispose<ScrapingOverview>(
  (ref) => ref.watch(adminRepositoryProvider).scrapingOverview(),
);

/// Adapters disponibles (change rarement : gardé en cache).
final adaptersProvider = FutureProvider<List<AdapterInfo>>(
  (ref) => ref.watch(adminRepositoryProvider).adapters(),
);

/// Détail d'une source.
final sourceDetailProvider = FutureProvider.autoDispose.family<Source, String>(
  (ref, id) => ref.watch(adminRepositoryProvider).source(id),
);

/// Dernières collectes d'une source.
final sourceRunsProvider = FutureProvider.autoDispose.family<List<ScrapingRun>, String>((
  ref,
  id,
) async {
  final page = await ref.watch(adminRepositoryProvider).runs(sourceId: id, pageSize: 10);
  return page.items;
});

/// Détail d'une collecte.
final runDetailProvider = FutureProvider.autoDispose.family<ScrapingRun, String>(
  (ref, id) => ref.watch(adminRepositoryProvider).run(id),
);

/// Entreprise par identifiant (nom affiché sur les fiches recruteurs, gardé en cache).
final companyByIdProvider = FutureProvider.family<Company, String>(
  (ref, id) => ref.watch(adminRepositoryProvider).company(id),
);

/// Emails des utilisateurs par identifiant (acteurs du journal d'audit).
final userEmailsProvider = FutureProvider.autoDispose<Map<String, String>>((ref) async {
  final page = await ref.watch(adminRepositoryProvider).users(pageSize: 100);
  return {for (final user in page.items) user.id: user.email};
});

/// Tous les types de contrat, y compris inactifs (référentiels).
final adminContractTypesProvider = FutureProvider.autoDispose<List<ContractType>>(
  (ref) => ref.watch(adminRepositoryProvider).contractTypes(),
);
