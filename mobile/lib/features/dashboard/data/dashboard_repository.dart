import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/models/enums.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/paginated.dart';
import '../../jobs/data/job_filters.dart';
import '../../jobs/data/job_models.dart';
import '../../jobs/data/jobs_repository.dart';
import 'dashboard_models.dart';

/// Données du tableau de bord (monitoring, profil).
class DashboardRepository {
  const DashboardRepository(this._api);

  final ApiClient _api;

  Future<DashboardOverview> overview() =>
      _api.getObject('/monitoring/overview', DashboardOverview.fromJson);

  Future<ApplicationStats> applicationStats() =>
      _api.getObject('/monitoring/applications', ApplicationStats.fromJson);

  /// Prénom du profil professionnel (null si non renseigné).
  Future<String?> firstName() async {
    final profile = asJsonMap(await _api.get('/profile'));
    final name = profile['first_name']?.toString().trim();
    return (name == null || name.isEmpty) ? null : name;
  }
}

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => DashboardRepository(ref.watch(apiClientProvider)),
);

/// Indicateurs du jour et état des services.
final dashboardOverviewProvider = FutureProvider<DashboardOverview>(
  (ref) => ref.watch(dashboardRepositoryProvider).overview(),
);

/// Statistiques des candidatures (taux de réponse, entretiens, offres).
final applicationStatsProvider = FutureProvider<ApplicationStats>(
  (ref) => ref.watch(dashboardRepositoryProvider).applicationStats(),
);

/// Nom affiché dans le message d'accueil : prénom du profil, sinon début de l'email.
final greetingNameProvider = FutureProvider<String?>((ref) async {
  final email = ref.watch(currentUserProvider.select((user) => user?.email));
  final fallback = email?.split('@').first;
  try {
    return await ref.watch(dashboardRepositoryProvider).firstName() ?? fallback;
  } catch (_) {
    return fallback;
  }
});

/// Meilleures offres : score ≥ seuil de l'utilisateur, triées par score (5 premières).
final topMatchesProvider = FutureProvider<Paginated<Job>>((ref) async {
  var threshold = 70;
  try {
    threshold = (await ref.watch(dashboardOverviewProvider.future)).matchingThreshold;
  } catch (_) {
    // Seuil par défaut si la vue d'ensemble est indisponible.
  }
  final filters = JobFilters(minScore: threshold, sortBy: JobSortField.score, sortDesc: true);
  return ref.watch(jobsRepositoryProvider).search(filters, pageSize: 5);
});
