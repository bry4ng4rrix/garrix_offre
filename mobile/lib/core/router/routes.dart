/// Chemins de navigation de l'application (`context.push(Routes.job(id))`).
abstract final class Routes {
  static const splash = '/splash';
  static const login = '/login';

  // Onglets principaux (barre de navigation).
  static const home = '/home';
  static const jobs = '/jobs';
  static const applications = '/applications';
  static const notifications = '/notifications';
  static const profile = '/profile';

  // Offres.
  static const jobNew = '/jobs/new';
  static String job(String id) => '/jobs/$id';

  // Candidatures.
  static const recruiterResponses = '/applications/responses';
  static String application(String id) => '/applications/$id';

  // Notifications.
  static const notificationSettings = '/notifications/settings';

  // Profil.
  static const profileEdit = '/profile/edit';
  static const skills = '/profile/skills';
  static const experiences = '/profile/experiences';
  static const technologies = '/profile/technologies';
  static const jobTitles = '/profile/job-titles';
  static const preferences = '/profile/preferences';
  static const matchingSettings = '/profile/matching';
  static const documents = '/profile/documents';

  // Réglages.
  static const settings = '/settings';
  static const changePassword = '/settings/password';

  // Administration.
  static const admin = '/admin';
  static const adminUsers = '/admin/users';
  static const adminSources = '/admin/sources';
  static String adminSource(String id) => '/admin/sources/$id';
  static const adminRuns = '/admin/runs';
  static const adminSystem = '/admin/system';
  static const adminAudit = '/admin/audit';
  static const adminCompanies = '/admin/companies';
  static const adminRecruiters = '/admin/recruiters';
  static const adminReference = '/admin/reference';
}
