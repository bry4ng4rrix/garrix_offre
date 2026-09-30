import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import 'profile_models.dart';
import 'profile_repository.dart';

/// État partagé des écrans du profil.
///
/// Chaque liste est un [AsyncNotifier] : les modifications mettent l'état à jour localement
/// (sans tout recharger) et les écrans restent synchronisés entre eux.

/// Recharge les données quand l'utilisateur connecté change (déconnexion, autre compte).
void _watchUser(Ref ref) => ref.watch(currentUserProvider.select((user) => user?.id));

// ---------------------------------------------------------------------------
// Profil
// ---------------------------------------------------------------------------

class ProfileNotifier extends AsyncNotifier<Profile> {
  @override
  Future<Profile> build() {
    _watchUser(ref);
    return ref.watch(profileRepositoryProvider).getProfile();
  }

  ProfileRepository get _repo => ref.read(profileRepositoryProvider);

  Future<Profile> save(Map<String, dynamic> body) async {
    final profile = await _repo.updateProfile(body);
    if (ref.mounted) {
      state = AsyncData(profile);
      // Salaire, devise et télétravail sont partagés avec les préférences.
      ref.invalidate(searchPreferencesProvider);
    }
    return profile;
  }

  Future<void> uploadPhoto({required String filename, String? path, Uint8List? bytes}) async {
    final profile = await _repo.uploadPhoto(filename: filename, path: path, bytes: bytes);
    if (!ref.mounted) return;
    state = AsyncData(profile);
    ref.read(photoVersionProvider.notifier).bump();
  }

  Future<void> deletePhoto() async {
    await _repo.deletePhoto();
    final profile = await _repo.getProfile();
    if (!ref.mounted) return;
    state = AsyncData(profile);
    ref.read(photoVersionProvider.notifier).bump();
  }
}

final profileProvider = AsyncNotifierProvider<ProfileNotifier, Profile>(ProfileNotifier.new);

/// Compteur incrémenté à chaque changement de photo (évite l'image en cache).
class PhotoVersion extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final photoVersionProvider = NotifierProvider<PhotoVersion, int>(PhotoVersion.new);

// ---------------------------------------------------------------------------
// Listes (compétences, expériences, technologies, postes)
// ---------------------------------------------------------------------------

/// Base commune : liste identifiée par `id`, mise à jour locale après chaque appel.
abstract class _ListNotifier<T> extends AsyncNotifier<List<T>> {
  String idOf(T item);

  ProfileRepository get repo => ref.read(profileRepositoryProvider);

  /// Tri appliqué après chaque modification.
  List<T> sorted(List<T> items) => items;

  void upsert(T item) {
    if (!ref.mounted) return;
    final items = [...?state.value];
    final index = items.indexWhere((e) => idOf(e) == idOf(item));
    index < 0 ? items.add(item) : items[index] = item;
    state = AsyncData(sorted(items));
    onChanged();
  }

  void removeLocal(String id) {
    if (!ref.mounted) return;
    state = AsyncData([...?state.value]..removeWhere((e) => idOf(e) == id));
    onChanged();
  }

  /// Mise à jour optimiste : applique [local] tout de suite, puis l'appel [remote].
  /// En cas d'erreur, l'élément d'origine est rétabli et l'erreur relancée.
  Future<void> optimistic(T original, T local, Future<T> Function() remote) async {
    upsert(local);
    try {
      upsert(await remote());
    } catch (_) {
      upsert(original);
      rethrow;
    }
  }

  /// Appelé après une modification (ex. invalider les préférences agrégées).
  void onChanged() {}
}

class SkillsNotifier extends _ListNotifier<ProfileSkill> {
  @override
  Future<List<ProfileSkill>> build() async {
    _watchUser(ref);
    return sorted(await ref.watch(profileRepositoryProvider).listSkills());
  }

  @override
  String idOf(ProfileSkill item) => item.id;

  @override
  List<ProfileSkill> sorted(List<ProfileSkill> items) =>
      items..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  Future<ProfileSkill> add(Map<String, dynamic> body) async {
    final skill = await repo.addSkill(body);
    upsert(skill);
    return skill;
  }

  Future<void> edit(String id, Map<String, dynamic> body) async =>
      upsert(await repo.updateSkill(id, body));

  Future<void> setEnabled(ProfileSkill skill, bool enabled) => optimistic(
    skill,
    ProfileSkill(
      id: skill.id,
      skillId: skill.skillId,
      name: skill.name,
      category: skill.category,
      level: skill.level,
      yearsExperience: skill.yearsExperience,
      priority: skill.priority,
      enabled: enabled,
    ),
    () => repo.updateSkill(skill.id, {'enabled': enabled}),
  );

  Future<void> remove(String id) async {
    await repo.deleteSkill(id);
    removeLocal(id);
  }
}

final profileSkillsProvider = AsyncNotifierProvider<SkillsNotifier, List<ProfileSkill>>(
  SkillsNotifier.new,
);

class ExperiencesNotifier extends _ListNotifier<Experience> {
  @override
  Future<List<Experience>> build() async {
    _watchUser(ref);
    return sorted(await ref.watch(profileRepositoryProvider).listExperiences());
  }

  @override
  String idOf(Experience item) => item.id;

  /// Poste actuel d'abord, puis du plus récent au plus ancien.
  @override
  List<Experience> sorted(List<Experience> items) => items
    ..sort((a, b) {
      if (a.isCurrent != b.isCurrent) return a.isCurrent ? -1 : 1;
      return b.startDate.compareTo(a.startDate);
    });

  Future<void> create(ExperienceInput input) async => upsert(await repo.createExperience(input));

  Future<void> edit(String id, ExperienceInput input) async =>
      upsert(await repo.updateExperience(id, input));

  Future<void> remove(String id) async {
    await repo.deleteExperience(id);
    removeLocal(id);
  }
}

final experiencesProvider = AsyncNotifierProvider<ExperiencesNotifier, List<Experience>>(
  ExperiencesNotifier.new,
);

class TechnologiesNotifier extends _ListNotifier<TechnologyPreference> {
  /// Chargées via `GET /experience-preferences/grouped`, puis regroupées à l'affichage.
  @override
  Future<List<TechnologyPreference>> build() async {
    _watchUser(ref);
    final grouped = await ref.watch(profileRepositoryProvider).groupedTechnologies();
    return sorted(grouped.values.expand((items) => items).toList());
  }

  @override
  String idOf(TechnologyPreference item) => item.id;

  @override
  List<TechnologyPreference> sorted(List<TechnologyPreference> items) =>
      items..sort((a, b) => a.technology.toLowerCase().compareTo(b.technology.toLowerCase()));

  @override
  void onChanged() => ref.invalidate(searchPreferencesProvider);

  Future<TechnologyPreference> add(Map<String, dynamic> body) async {
    final item = await repo.addTechnology(body);
    upsert(item);
    return item;
  }

  Future<void> edit(String id, Map<String, dynamic> body) async =>
      upsert(await repo.updateTechnology(id, body));

  Future<void> setEnabled(TechnologyPreference item, bool enabled) => optimistic(
    item,
    TechnologyPreference(
      id: item.id,
      skillId: item.skillId,
      technology: item.technology,
      category: item.category,
      level: item.level,
      priority: item.priority,
      minYears: item.minYears,
      isRequired: item.isRequired,
      enabled: enabled,
    ),
    () => repo.updateTechnology(item.id, {'enabled': enabled}),
  );

  Future<void> remove(String id) async {
    await repo.deleteTechnology(id);
    removeLocal(id);
  }
}

final technologiesProvider =
    AsyncNotifierProvider<TechnologiesNotifier, List<TechnologyPreference>>(
      TechnologiesNotifier.new,
    );

class JobTitlesNotifier extends _ListNotifier<JobTitle> {
  @override
  Future<List<JobTitle>> build() async {
    _watchUser(ref);
    return sorted(await ref.watch(profileRepositoryProvider).listJobTitles());
  }

  @override
  String idOf(JobTitle item) => item.id;

  /// Actifs d'abord, puis par priorité décroissante et ordre alphabétique.
  @override
  List<JobTitle> sorted(List<JobTitle> items) => items
    ..sort((a, b) {
      if (a.enabled != b.enabled) return a.enabled ? -1 : 1;
      final byPriority = b.priority.index.compareTo(a.priority.index);
      if (byPriority != 0) return byPriority;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

  @override
  void onChanged() => ref.invalidate(searchPreferencesProvider);

  Future<void> add(Map<String, dynamic> body) async => upsert(await repo.addJobTitle(body));

  Future<void> edit(String id, Map<String, dynamic> body) async =>
      upsert(await repo.updateJobTitle(id, body));

  Future<void> setEnabled(JobTitle item, bool enabled) => optimistic(
    item,
    JobTitle(id: item.id, title: item.title, priority: item.priority, enabled: enabled),
    () => repo.updateJobTitle(item.id, {'enabled': enabled}),
  );

  Future<void> remove(String id) async {
    await repo.deleteJobTitle(id);
    removeLocal(id);
  }
}

final jobTitlesProvider = AsyncNotifierProvider<JobTitlesNotifier, List<JobTitle>>(
  JobTitlesNotifier.new,
);

// ---------------------------------------------------------------------------
// Préférences de recherche et matching
// ---------------------------------------------------------------------------

class SearchPreferencesNotifier extends AsyncNotifier<SearchPreferences> {
  @override
  Future<SearchPreferences> build() {
    _watchUser(ref);
    return ref.watch(profileRepositoryProvider).getPreferences();
  }

  Future<void> save(SearchPreferences preferences) async {
    final saved = await ref.read(profileRepositoryProvider).updatePreferences(preferences);
    if (!ref.mounted) return;
    state = AsyncData(saved);
    ref.invalidate(profileProvider);
  }
}

final searchPreferencesProvider =
    AsyncNotifierProvider<SearchPreferencesNotifier, SearchPreferences>(
      SearchPreferencesNotifier.new,
    );

class MatchingSettingsNotifier extends AsyncNotifier<MatchingSettings> {
  @override
  Future<MatchingSettings> build() {
    _watchUser(ref);
    return ref.watch(profileRepositoryProvider).getMatchingSettings();
  }

  Future<MatchingSettings> save(MatchingSettings settings) async {
    final saved = await ref.read(profileRepositoryProvider).updateMatchingSettings(settings);
    if (ref.mounted) state = AsyncData(saved);
    return saved;
  }

  Future<MatchingSettings> reset() async {
    final saved = await ref.read(profileRepositoryProvider).resetMatchingSettings();
    if (ref.mounted) state = AsyncData(saved);
    return saved;
  }
}

final matchingSettingsProvider =
    AsyncNotifierProvider<MatchingSettingsNotifier, MatchingSettings>(
      MatchingSettingsNotifier.new,
    );
