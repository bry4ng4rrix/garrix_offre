import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/enums.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/paginated.dart';
import 'application_models.dart';

/// Accès à l'API des candidatures et des réponses de recruteurs.
class ApplicationsRepository {
  ApplicationsRepository(this._api);

  final ApiClient _api;

  // --- Candidatures ---

  Future<Paginated<Application>> list({
    int page = 1,
    int pageSize = 20,
    ApplicationStatus? status,
    String? jobId,
  }) => _api.getPage(
    '/applications',
    Application.fromJson,
    page: page,
    pageSize: pageSize,
    query: {'status_filter': status?.apiValue, 'job_id': jobId},
  );

  Future<Application> get(String id) => _api.getObject('/applications/$id', Application.fromJson);

  Future<Application> create(ApplicationCreate data) async =>
      Application.fromJson(asJsonMap(await _api.post('/applications', body: data.toJson())));

  Future<Application> update(String id, ApplicationUpdate data) async =>
      Application.fromJson(asJsonMap(await _api.put('/applications/$id', body: data.toJson())));

  Future<void> delete(String id) => _api.delete('/applications/$id');

  Future<Application> changeStatus(String id, StatusChange change) async => Application.fromJson(
    asJsonMap(await _api.patch('/applications/$id/status', body: change.toJson())),
  );

  /// Génère les brouillons, choisit le CV et passe la candidature à « Prête ». Rien n'est envoyé.
  Future<Application> prepare(String id, PrepareRequest request) async => Application.fromJson(
    asJsonMap(await _api.post('/applications/$id/prepare', body: request.toJson())),
  );

  Future<GeneratedText> generate(String id, GenerateRequest request) async =>
      GeneratedText.fromJson(
        asJsonMap(await _api.post('/applications/$id/generate', body: request.toJson())),
      );

  /// Envoi validé explicitement par l'utilisateur (`confirm: true`).
  Future<Application> submit(String id, SubmitRequest request) async => Application.fromJson(
    asJsonMap(await _api.post('/applications/$id/submit', body: request.toJson())),
  );

  Future<List<StatusHistoryEntry>> history(String id) =>
      _api.getList('/applications/$id/history', StatusHistoryEntry.fromJson);

  Future<ApplicationStats> stats() =>
      _api.getObject('/monitoring/applications', ApplicationStats.fromJson);

  // --- Réponses des recruteurs ---

  Future<Paginated<RecruiterResponse>> responses({
    int page = 1,
    int pageSize = 20,
    String? applicationId,
  }) => _api.getPage(
    '/applications/responses',
    RecruiterResponse.fromJson,
    page: page,
    pageSize: pageSize,
    query: {'application_id': applicationId},
  );

  Future<RecruiterResponse> createResponse(RecruiterResponseCreate data) async =>
      RecruiterResponse.fromJson(
        asJsonMap(await _api.post('/applications/responses', body: data.toJson())),
      );

  Future<RecruiterResponse> updateResponse(String id, RecruiterResponseUpdate data) async =>
      RecruiterResponse.fromJson(
        asJsonMap(await _api.patch('/applications/responses/$id', body: data.toJson())),
      );
}

final applicationsRepositoryProvider = Provider<ApplicationsRepository>(
  (ref) => ApplicationsRepository(ref.watch(apiClientProvider)),
);
