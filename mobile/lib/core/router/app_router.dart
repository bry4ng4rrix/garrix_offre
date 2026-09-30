import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/admin_page.dart';
import '../../features/admin/audit_logs_page.dart';
import '../../features/admin/companies_page.dart';
import '../../features/admin/recruiters_page.dart';
import '../../features/admin/reference_data_page.dart';
import '../../features/admin/scraping_runs_page.dart';
import '../../features/admin/source_detail_page.dart';
import '../../features/admin/sources_page.dart';
import '../../features/admin/system_page.dart';
import '../../features/admin/users_page.dart';
import '../../features/applications/application_detail_page.dart';
import '../../features/applications/applications_page.dart';
import '../../features/applications/recruiter_responses_page.dart';
import '../../features/auth/login_page.dart';
import '../../features/auth/splash_page.dart';
import '../../features/dashboard/dashboard_page.dart';
import '../../features/documents/documents_page.dart';
import '../../features/jobs/job_detail_page.dart';
import '../../features/jobs/job_form_page.dart';
import '../../features/jobs/jobs_page.dart';
import '../../features/notifications/notification_settings_page.dart';
import '../../features/notifications/notifications_page.dart';
import '../../features/profile/edit_profile_page.dart';
import '../../features/profile/experiences_page.dart';
import '../../features/profile/job_titles_page.dart';
import '../../features/profile/matching_settings_page.dart';
import '../../features/profile/preferences_page.dart';
import '../../features/profile/profile_page.dart';
import '../../features/profile/skills_page.dart';
import '../../features/profile/technologies_page.dart';
import '../../features/settings/change_password_page.dart';
import '../../features/settings/settings_page.dart';
import '../auth/auth_controller.dart';
import 'app_shell.dart';
import 'routes.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Prévient le routeur quand l'état de connexion change (redirections).
class _AuthRefresh extends ChangeNotifier {
  void notify() => notifyListeners();
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefresh();
  ref.listen(authControllerProvider, (_, _) => refresh.notify());
  ref.onDispose(refresh.dispose);

  GoRoute page(String path, Widget Function(GoRouterState state) builder) => GoRoute(
    path: path,
    parentNavigatorKey: rootNavigatorKey,
    builder: (context, state) => builder(state),
  );

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final location = state.matchedLocation;
      if (auth.status == AuthStatus.unknown) {
        return location == Routes.splash ? null : Routes.splash;
      }
      if (!auth.isSignedIn) return location == Routes.login ? null : Routes.login;
      if (location == Routes.splash || location == Routes.login) return Routes.home;
      if (location.startsWith(Routes.admin) && !(auth.user?.isSuperuser ?? false)) {
        return Routes.profile;
      }
      return null;
    },
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashPage()),
      GoRoute(path: Routes.login, builder: (_, _) => const LoginPage()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.home, builder: (_, _) => const DashboardPage())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.jobs,
                builder: (_, _) => const JobsPage(),
                routes: [
                  page('new', (_) => const JobFormPage()),
                  page(':jobId', (s) => JobDetailPage(jobId: s.pathParameters['jobId']!)),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.applications,
                builder: (_, _) => const ApplicationsPage(),
                routes: [
                  page('responses', (_) => const RecruiterResponsesPage()),
                  page(
                    ':applicationId',
                    (s) => ApplicationDetailPage(applicationId: s.pathParameters['applicationId']!),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.notifications,
                builder: (_, _) => const NotificationsPage(),
                routes: [page('settings', (_) => const NotificationSettingsPage())],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.profile,
                builder: (_, _) => const ProfilePage(),
                routes: [
                  page('edit', (_) => const EditProfilePage()),
                  page('skills', (_) => const SkillsPage()),
                  page('experiences', (_) => const ExperiencesPage()),
                  page('technologies', (_) => const TechnologiesPage()),
                  page('job-titles', (_) => const JobTitlesPage()),
                  page('preferences', (_) => const PreferencesPage()),
                  page('matching', (_) => const MatchingSettingsPage()),
                  page('documents', (_) => const DocumentsPage()),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: Routes.settings,
        builder: (_, _) => const SettingsPage(),
        routes: [GoRoute(path: 'password', builder: (_, _) => const ChangePasswordPage())],
      ),
      GoRoute(
        path: Routes.admin,
        builder: (_, _) => const AdminPage(),
        routes: [
          GoRoute(path: 'users', builder: (_, _) => const UsersPage()),
          GoRoute(
            path: 'sources',
            builder: (_, _) => const SourcesPage(),
            routes: [
              GoRoute(
                path: ':sourceId',
                builder: (_, s) => SourceDetailPage(sourceId: s.pathParameters['sourceId']!),
              ),
            ],
          ),
          GoRoute(path: 'runs', builder: (_, _) => const ScrapingRunsPage()),
          GoRoute(path: 'system', builder: (_, _) => const SystemPage()),
          GoRoute(path: 'audit', builder: (_, _) => const AuditLogsPage()),
          GoRoute(path: 'companies', builder: (_, _) => const CompaniesPage()),
          GoRoute(path: 'recruiters', builder: (_, _) => const RecruitersPage()),
          GoRoute(path: 'reference', builder: (_, _) => const ReferenceDataPage()),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
