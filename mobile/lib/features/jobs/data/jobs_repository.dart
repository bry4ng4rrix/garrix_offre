import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/enums.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/paginated.dart';
import 'job_draft.dart';
import 'job_filters.dart';
import 'job_models.dart';

/// Accès à l'API des offres, du matching et de l'analyse IA.
class JobsRepository {
  const JobsRepository(this._api);

  final ApiClient _api;

  Future<Paginated<Job>> search(JobFilters filters, {int page = 1, int pageSize = 20}) =>
      _api.getPage('/jobs', Job.fromJson, page: page, pageSize: pageSize, query: filters.toQuery());

  /// Détail complet (le serveur marque l'offre comme vue).
  Future<Job> get(String id) => _api.getObject('/jobs/$id', Job.fromJson);

  Future<Job> updateState(String id, JobStateUpdate update) async =>
      Job.fromJson(asJsonMap(await _api.patch('/jobs/$id/state', body: update.toJson())));

  Future<Job> create(JobDraft draft) async =>
      Job.fromJson(asJsonMap(await _api.post('/jobs', body: draft.toJson())));

  Future<void> delete(String id) => _api.delete('/jobs/$id');

  Future<JobRaw> raw(String id) => _api.getObject('/jobs/$id/raw', JobRaw.fromJson);

  /// Recalcule le score de l'offre et renvoie le détail par critère.
  Future<MatchResult> match(String id) async =>
      MatchResult.fromJson(asJsonMap(await _api.post('/jobs/$id/match')));

  /// Recalcule tous les scores de l'utilisateur (en tâche de fond par défaut).
  Future<RecalculateResult> recalculateAll() async =>
      RecalculateResult.fromJson(asJsonMap(await _api.post('/matching/recalculate')));

  Future<JobAnalysis> analyze(String id) async =>
      JobAnalysis.fromJson(asJsonMap(await _api.post('/ai/jobs/$id/analyze')));

  /// Crée une candidature « en préparation » pour l'offre et renvoie son identifiant.
  Future<String> createApplication(String jobId) async {
    final data = asJsonMap(
      await _api.post(
        '/applications',
        body: {'job_id': jobId, 'status': ApplicationStatus.preparing.apiValue},
      ),
    );
    return data['id'].toString();
  }

  /// Candidature en cours pour cette offre (la plus récente), ou null.
  Future<String?> findApplication(String jobId) async {
    final page = await _api.getPage(
      '/applications',
      (json) => json,
      pageSize: 5,
      query: {'job_id': jobId},
    );
    for (final item in page.items) {
      final status = ApplicationStatus.fromApi(item['status']);
      if (status != null && !status.isFinal) return item['id'].toString();
    }
    return page.items.isEmpty ? null : page.items.first['id'].toString();
  }
}

final jobsRepositoryProvider = Provider<JobsRepository>(
  (ref) => JobsRepository(ref.watch(apiClientProvider)),
);
