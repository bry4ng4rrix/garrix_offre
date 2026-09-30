import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/application_models.dart';
import 'data/applications_repository.dart';

/// Statistiques (bandeau de la liste des candidatures).
final applicationStatsProvider = FutureProvider.autoDispose<ApplicationStats>(
  (ref) => ref.watch(applicationsRepositoryProvider).stats(),
);

/// Détail d'une candidature. `set()` remplace la valeur par celle renvoyée par une action
/// (préparation, envoi, changement de statut...) sans recharger.
class ApplicationController extends AsyncNotifier<Application> {
  ApplicationController(this.applicationId);

  final String applicationId;

  @override
  Future<Application> build() => ref.watch(applicationsRepositoryProvider).get(applicationId);

  void set(Application application) => state = AsyncData(application);
}

final applicationControllerProvider = AsyncNotifierProvider.autoDispose
    .family<ApplicationController, Application, String>(ApplicationController.new);

/// Historique des statuts d'une candidature.
final applicationHistoryProvider = FutureProvider.autoDispose
    .family<List<StatusHistoryEntry>, String>(
      (ref, id) => ref.watch(applicationsRepositoryProvider).history(id),
    );

/// Réponses de recruteurs liées à une candidature (les plus récentes d'abord).
final applicationResponsesProvider = FutureProvider.autoDispose
    .family<List<RecruiterResponse>, String>((ref, id) async {
      final page = await ref
          .watch(applicationsRepositoryProvider)
          .responses(applicationId: id, pageSize: 50);
      return page.items;
    });

/// Nombre de réponses non lues parmi les plus récentes (badge de la liste).
final unreadResponsesCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final page = await ref.watch(applicationsRepositoryProvider).responses(pageSize: 100);
  return page.items.where((response) => !response.isRead).length;
});

/// Candidatures récentes, pour associer une réponse à une candidature.
final applicationChoicesProvider = FutureProvider.autoDispose<List<Application>>((ref) async {
  final page = await ref.watch(applicationsRepositoryProvider).list(pageSize: 100);
  return page.items;
});
