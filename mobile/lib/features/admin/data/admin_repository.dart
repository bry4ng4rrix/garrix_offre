import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/app_user.dart';
import '../../../core/models/enums.dart';
import '../../../core/models/reference.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/paginated.dart';
import 'audit_models.dart';
import 'directory_models.dart';
import 'monitoring_models.dart';
import 'source_models.dart';

/// Accès aux endpoints d'administration (réservés aux superutilisateurs).
///
/// Les énumérations sont toujours passées via `apiValue` (le client convertit sinon avec
/// `Enum.name`, qui diffère pour `partial_success` par exemple).
class AdminRepository {
  AdminRepository(this._api);

  final ApiClient _api;

  // --- Utilisateurs ---------------------------------------------------------

  Future<Paginated<AppUser>> users({int page = 1, int pageSize = 20}) =>
      _api.getPage('/users', AppUser.fromJson, page: page, pageSize: pageSize);

  Future<AppUser> createUser({
    required String email,
    required String password,
    bool isSuperuser = false,
  }) async => AppUser.fromJson(
    asJsonMap(
      await _api.post(
        '/users',
        body: {'email': email.trim(), 'password': password, 'is_superuser': isSuperuser},
      ),
    ),
  );

  Future<AppUser> updateUser(String id, {bool? isActive, bool? isSuperuser}) async =>
      AppUser.fromJson(
        asJsonMap(
          await _api.patch(
            '/users/$id',
            body: {'is_active': ?isActive, 'is_superuser': ?isSuperuser},
          ),
        ),
      );

  // --- Sources --------------------------------------------------------------

  Future<Paginated<Source>> sources({
    int page = 1,
    int pageSize = 20,
    SourceCategory? category,
    SourceType? type,
    bool? enabled,
  }) => _api.getPage(
    '/sources',
    Source.fromJson,
    page: page,
    pageSize: pageSize,
    query: {'category': category?.apiValue, 'type': type?.apiValue, 'enabled': enabled},
  );

  Future<Source> source(String id) => _api.getObject('/sources/$id', Source.fromJson);

  Future<Source> createSource(SourceInput input) async =>
      Source.fromJson(asJsonMap(await _api.post('/sources', body: input.toJson())));

  Future<Source> updateSource(String id, Map<String, dynamic> body) async =>
      Source.fromJson(asJsonMap(await _api.put('/sources/$id', body: body)));

  Future<void> deleteSource(String id) => _api.delete('/sources/$id');

  Future<SourceTestResult> testSource(String id) async =>
      SourceTestResult.fromJson(asJsonMap(await _api.post('/sources/$id/test')));

  Future<RunRequestResult> runSource(String id) async =>
      RunRequestResult.fromJson(asJsonMap(await _api.post('/sources/$id/run')));

  Future<List<AdapterInfo>> adapters() => _api.getList('/scraping/adapters', AdapterInfo.fromJson);

  // --- Collectes ------------------------------------------------------------

  Future<Paginated<ScrapingRun>> runs({
    int page = 1,
    int pageSize = 20,
    String? sourceId,
    ScrapingRunStatus? status,
  }) => _api.getPage(
    '/scraping/runs',
    ScrapingRun.fromJson,
    page: page,
    pageSize: pageSize,
    query: {'source_id': sourceId, 'status_filter': status?.apiValue},
  );

  Future<ScrapingRun> run(String id) => _api.getObject('/scraping/runs/$id', ScrapingRun.fromJson);

  Future<ScrapingRun> cancelRun(String id) async =>
      ScrapingRun.fromJson(asJsonMap(await _api.post('/scraping/runs/$id/cancel')));

  // --- Monitoring et maintenance ---------------------------------------------

  Future<SystemStatus> system() => _api.getObject('/monitoring/system', SystemStatus.fromJson);

  Future<ScrapingOverview> scrapingOverview() =>
      _api.getObject('/monitoring/scraping', ScrapingOverview.fromJson);

  Future<MaintenanceResult> expireJobs() async =>
      MaintenanceResult.fromJson(asJsonMap(await _api.post('/jobs/maintenance/expire')));

  Future<RecalculateResult> recalculateMatching() async =>
      RecalculateResult.fromJson(asJsonMap(await _api.post('/matching/recalculate')));

  // --- Journal d'audit --------------------------------------------------------

  Future<Paginated<AuditLog>> auditLogs({
    int page = 1,
    int pageSize = 30,
    String? action,
    String? entityType,
  }) => _api.getPage(
    '/audit-logs',
    AuditLog.fromJson,
    page: page,
    pageSize: pageSize,
    query: {'action': action, 'entity_type': entityType},
  );

  // --- Entreprises ------------------------------------------------------------

  Future<Paginated<Company>> companies({
    int page = 1,
    int pageSize = 20,
    String? search,
    String? city,
    String? country,
    String? industry,
  }) => _api.getPage(
    '/companies',
    Company.fromJson,
    page: page,
    pageSize: pageSize,
    query: {'search': search, 'city': city, 'country': country, 'industry': industry},
  );

  Future<Company> company(String id) => _api.getObject('/companies/$id', Company.fromJson);

  Future<Company> createCompany(Map<String, dynamic> body) async =>
      Company.fromJson(asJsonMap(await _api.post('/companies', body: body)));

  Future<Company> updateCompany(String id, Map<String, dynamic> body) async =>
      Company.fromJson(asJsonMap(await _api.put('/companies/$id', body: body)));

  Future<void> deleteCompany(String id) => _api.delete('/companies/$id');

  // --- Recruteurs -------------------------------------------------------------

  Future<Paginated<Recruiter>> recruiters({
    int page = 1,
    int pageSize = 20,
    String? search,
    String? companyId,
  }) => _api.getPage(
    '/recruiters',
    Recruiter.fromJson,
    page: page,
    pageSize: pageSize,
    query: {'search': search, 'company_id': companyId},
  );

  Future<Recruiter> createRecruiter(Map<String, dynamic> body) async =>
      Recruiter.fromJson(asJsonMap(await _api.post('/recruiters', body: body)));

  Future<Recruiter> updateRecruiter(String id, Map<String, dynamic> body) async =>
      Recruiter.fromJson(asJsonMap(await _api.put('/recruiters/$id', body: body)));

  Future<void> deleteRecruiter(String id) => _api.delete('/recruiters/$id');

  // --- Référentiels -------------------------------------------------------------

  Future<List<ContractType>> contractTypes({bool includeInactive = true}) async {
    final items = await _api.getList(
      '/contract-types',
      ContractType.fromJson,
      query: {'include_inactive': includeInactive},
    );
    return items..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  Future<void> createContractType(Map<String, dynamic> body) =>
      _api.post('/contract-types', body: body);

  Future<void> updateContractType(String id, Map<String, dynamic> body) =>
      _api.put('/contract-types/$id', body: body);

  Future<void> deleteContractType(String id) => _api.delete('/contract-types/$id');

  Future<void> createExperienceLevel(Map<String, dynamic> body) =>
      _api.post('/experience-levels', body: body);

  Future<void> updateExperienceLevel(String id, Map<String, dynamic> body) =>
      _api.put('/experience-levels/$id', body: body);

  Future<void> deleteExperienceLevel(String id) => _api.delete('/experience-levels/$id');

  Future<void> createSkillCategory(Map<String, dynamic> body) =>
      _api.post('/skills/categories', body: body);

  Future<void> updateSkillCategory(String id, Map<String, dynamic> body) =>
      _api.put('/skills/categories/$id', body: body);

  Future<void> deleteSkillCategory(String id) => _api.delete('/skills/categories/$id');

  Future<Paginated<CatalogSkill>> catalog({
    int page = 1,
    int pageSize = 30,
    String? search,
    String? category,
  }) => _api.getPage(
    '/skills/catalog',
    CatalogSkill.fromJson,
    page: page,
    pageSize: pageSize,
    query: {'search': search, 'category': category},
  );

  Future<CatalogSkill> updateCatalogSkill(
    String id, {
    required String? category,
    required List<String> aliases,
  }) async => CatalogSkill.fromJson(
    asJsonMap(
      await _api.patch('/skills/catalog/$id', body: {'category': category, 'aliases': aliases}),
    ),
  );
}

final adminRepositoryProvider = Provider<AdminRepository>(
  (ref) => AdminRepository(ref.watch(apiClientProvider)),
);
