import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/reference.dart';
import '../../../core/network/api_client.dart';
import 'profile_models.dart';

/// Accès à l'API pour le profil, les compétences, les expériences, les technologies
/// et postes recherchés, les préférences de recherche et les réglages du matching.
class ProfileRepository {
  const ProfileRepository(this._api);

  final ApiClient _api;

  // --- Profil ---

  Future<Profile> getProfile() => _api.getObject('/profile', Profile.fromJson);

  Future<Profile> updateProfile(Map<String, dynamic> body) async =>
      Profile.fromJson(asJsonMap(await _api.put('/profile', body: body)));

  /// Envoie la photo depuis un chemin local, ou depuis ses octets si aucun chemin n'existe.
  Future<Profile> uploadPhoto({
    required String filename,
    String? path,
    Uint8List? bytes,
  }) async {
    final data = path != null
        ? await _api.upload('/profile/photo', filePath: path, filename: filename)
        : await _api.uploadBytes('/profile/photo', bytes: bytes ?? Uint8List(0), filename: filename);
    return Profile.fromJson(asJsonMap(data));
  }

  Future<void> deletePhoto() => _api.delete('/profile/photo');

  // --- Compétences ---

  Future<List<ProfileSkill>> listSkills() => _api.getList('/skills', ProfileSkill.fromJson);

  Future<ProfileSkill> addSkill(Map<String, dynamic> body) async =>
      ProfileSkill.fromJson(asJsonMap(await _api.post('/skills', body: body)));

  Future<ProfileSkill> updateSkill(String id, Map<String, dynamic> body) async =>
      ProfileSkill.fromJson(asJsonMap(await _api.put('/skills/$id', body: body)));

  Future<void> deleteSkill(String id) => _api.delete('/skills/$id');

  /// Autocomplétion dans le catalogue global de compétences.
  Future<List<CatalogSkill>> searchCatalog(String query, {int limit = 12}) async {
    final page = await _api.getPage(
      '/skills/catalog',
      CatalogSkill.fromJson,
      pageSize: limit,
      query: {'search': query.trim()},
    );
    return page.items;
  }

  // --- Expériences ---

  Future<List<Experience>> listExperiences() =>
      _api.getList('/experiences', Experience.fromJson);

  Future<Experience> createExperience(ExperienceInput input) async =>
      Experience.fromJson(asJsonMap(await _api.post('/experiences', body: input.toJson())));

  Future<Experience> updateExperience(String id, ExperienceInput input) async =>
      Experience.fromJson(asJsonMap(await _api.put('/experiences/$id', body: input.toJson())));

  Future<void> deleteExperience(String id) => _api.delete('/experiences/$id');

  // --- Technologies recherchées ---

  Future<Map<String, List<TechnologyPreference>>> groupedTechnologies() async =>
      TechnologyPreference.groupedFromJson(await _api.get('/experience-preferences/grouped'));

  Future<TechnologyPreference> addTechnology(Map<String, dynamic> body) async =>
      TechnologyPreference.fromJson(
        asJsonMap(await _api.post('/experience-preferences', body: body)),
      );

  Future<TechnologyPreference> updateTechnology(String id, Map<String, dynamic> body) async =>
      TechnologyPreference.fromJson(
        asJsonMap(await _api.put('/experience-preferences/$id', body: body)),
      );

  Future<void> deleteTechnology(String id) => _api.delete('/experience-preferences/$id');

  // --- Postes recherchés ---

  Future<List<JobTitle>> listJobTitles() => _api.getList('/job-titles', JobTitle.fromJson);

  Future<JobTitle> addJobTitle(Map<String, dynamic> body) async =>
      JobTitle.fromJson(asJsonMap(await _api.post('/job-titles', body: body)));

  Future<JobTitle> updateJobTitle(String id, Map<String, dynamic> body) async =>
      JobTitle.fromJson(asJsonMap(await _api.put('/job-titles/$id', body: body)));

  Future<void> deleteJobTitle(String id) => _api.delete('/job-titles/$id');

  // --- Préférences de recherche ---

  Future<SearchPreferences> getPreferences() =>
      _api.getObject('/preferences', SearchPreferences.fromJson);

  Future<SearchPreferences> updatePreferences(SearchPreferences preferences) async =>
      SearchPreferences.fromJson(
        asJsonMap(await _api.put('/preferences', body: preferences.toUpdateJson())),
      );

  // --- Matching ---

  Future<MatchingSettings> getMatchingSettings() =>
      _api.getObject('/matching/settings', MatchingSettings.fromJson);

  Future<MatchingSettings> updateMatchingSettings(MatchingSettings settings) async =>
      MatchingSettings.fromJson(
        asJsonMap(await _api.put('/matching/settings', body: settings.toJson())),
      );

  Future<MatchingSettings> resetMatchingSettings() async =>
      MatchingSettings.fromJson(asJsonMap(await _api.post('/matching/settings/reset')));

  Future<RecalculateResult> recalculateScores() async =>
      RecalculateResult.fromJson(asJsonMap(await _api.post('/matching/recalculate')));
}

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(ref.watch(apiClientProvider)),
);
