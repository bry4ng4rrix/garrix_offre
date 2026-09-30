import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/enums.dart';
import 'data/job_filters.dart';
import 'data/job_models.dart';
import 'data/jobs_repository.dart';

/// Filtres d'un sous-onglet (offres d'emploi ou missions freelance), gardés en mémoire
/// entre les changements d'onglet.
class JobFiltersNotifier extends Notifier<JobFilters> {
  JobFiltersNotifier(this.scope);

  final JobScope scope;

  @override
  JobFilters build() => JobFilters(scope: scope);

  void set(JobFilters filters) => state = filters.copyWith(scope: scope);

  void setSearch(String? value) => state = state.copyWith(search: value);

  /// Réinitialise tous les filtres (la recherche texte et le tri sont conservés).
  void resetFilters() => state = JobFilters(
    scope: scope,
    search: state.search,
    sortBy: state.sortBy,
    sortDesc: state.sortDesc,
  );

  /// Affiche les meilleures offres (score minimum = seuil de l'utilisateur, tri par score).
  void showBestMatches(int threshold) => state = JobFilters(
    scope: scope,
    minScore: threshold,
    sortBy: JobSortField.score,
    sortDesc: true,
  );
}

final jobFiltersProvider = NotifierProvider.family<JobFiltersNotifier, JobFilters, JobScope>(
  JobFiltersNotifier.new,
);

/// Sous-onglet affiché dans la page Offres (modifiable depuis l'accueil ou les alertes).
class SelectedJobScopeNotifier extends Notifier<JobScope> {
  @override
  JobScope build() => JobScope.offers;

  void select(JobScope scope) => state = scope;
}

final selectedJobScopeProvider = NotifierProvider<SelectedJobScopeNotifier, JobScope>(
  SelectedJobScopeNotifier.new,
);

/// Pays disponibles (avec leur nombre d'offres) pour les autres filtres du sous-onglet.
final jobCountriesProvider = FutureProvider.autoDispose.family<List<CountryCount>, JobFilters>(
  (ref, filters) => ref.watch(jobsRepositoryProvider).countries(filters.copyWith(countries: [])),
);

/// Modification d'une offre faite ailleurs (détail, formulaire) à répercuter sur les listes.
class JobChange {
  const JobChange.updated(Job this.job) : jobId = null, created = false;
  const JobChange.created(Job this.job) : jobId = null, created = true;
  const JobChange.deleted(String this.jobId) : job = null, created = false;

  final Job? job;
  final String? jobId;
  final bool created;

  String get id => job?.id ?? jobId!;
  bool get deleted => job == null;
}

class JobChangesNotifier extends Notifier<JobChange?> {
  @override
  JobChange? build() => null;

  void emit(JobChange change) => state = change;
}

/// Flux des modifications d'offres (à écouter avec `ref.listen`).
final jobChangesProvider = NotifierProvider<JobChangesNotifier, JobChange?>(JobChangesNotifier.new);

/// Détail d'une offre, modifiable sur place (sauvegarde, ignorer, score).
class JobDetailNotifier extends AsyncNotifier<Job> {
  JobDetailNotifier(this.jobId);

  final String jobId;

  JobsRepository get _repo => ref.read(jobsRepositoryProvider);

  @override
  Future<Job> build() async {
    final job = await ref.watch(jobsRepositoryProvider).get(jobId);
    // L'ouverture marque l'offre comme vue : les listes en tiennent compte.
    Future.microtask(() {
      if (ref.mounted) ref.read(jobChangesProvider.notifier).emit(JobChange.updated(job));
    });
    return job;
  }

  Future<void> reload() async {
    state = await AsyncValue.guard(() => _repo.get(jobId));
  }

  /// Modifie l'état (sauvegardée / ignorée / vue) et renvoie l'offre à jour.
  Future<Job> updateState(JobStateUpdate update) async {
    final updated = await _repo.updateState(jobId, update);
    final previous = state.value;
    final merged = previous == null ? updated : updated.mergeDetails(previous);
    if (ref.mounted) state = AsyncData(merged);
    ref.read(jobChangesProvider.notifier).emit(JobChange.updated(merged));
    return merged;
  }

  /// Reporte un nouveau résultat de matching sur l'offre affichée.
  void applyMatch(MatchResult result) {
    final previous = state.value;
    if (previous == null) return;
    final updated = previous.copyWith(matching: result.toMatching());
    state = AsyncData(updated);
    ref.read(jobChangesProvider.notifier).emit(JobChange.updated(updated));
  }

  void setApplication(String applicationId) {
    final previous = state.value;
    if (previous == null) return;
    final status = previous.status;
    final updated = previous.copyWith(
      status: JobUserState(
        state: status.state,
        isNew: false,
        isExpired: status.isExpired,
        isSaved: status.isSaved,
        isIgnored: status.isIgnored,
        applicationStatus: status.applicationStatus == ApplicationStatus.notApplied
            ? ApplicationStatus.preparing
            : status.applicationStatus,
        applicationId: applicationId,
      ),
    );
    state = AsyncData(updated);
    ref.read(jobChangesProvider.notifier).emit(JobChange.updated(updated));
  }
}

final jobDetailProvider = AsyncNotifierProvider.autoDispose.family<JobDetailNotifier, Job, String>(
  JobDetailNotifier.new,
);

/// Détail du matching par critère (`POST /jobs/{id}/match` : recalcule puis renvoie le détail).
final jobMatchProvider = FutureProvider.autoDispose.family<MatchResult, String>(
  (ref, jobId) => ref.watch(jobsRepositoryProvider).match(jobId),
);

/// Analyse de l'offre (IA ou règles).
final jobAnalysisProvider = FutureProvider.autoDispose.family<JobAnalysis, String>(
  (ref, jobId) => ref.watch(jobsRepositoryProvider).analyze(jobId),
);

/// Données brutes (admin).
final jobRawProvider = FutureProvider.autoDispose.family<JobRaw, String>(
  (ref, jobId) => ref.watch(jobsRepositoryProvider).raw(jobId),
);
