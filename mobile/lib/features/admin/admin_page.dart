import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/realtime/realtime_service.dart';
import '../../core/router/routes.dart';
import '../../core/widgets/ui.dart';
import 'data/admin_providers.dart';
import 'data/monitoring_models.dart';
import 'widgets/admin_ui.dart';
import 'widgets/system_widgets.dart';

/// Hub d'administration : résumé de l'état du système puis accès aux écrans de gestion.
class AdminPage extends ConsumerWidget {
  const AdminPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(realtimeEventsProvider, (_, next) {
      if (next.value?.type == 'monitoring') ref.invalidate(systemStatusProvider);
    });
    final status = ref.watch(systemStatusProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Administration'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(systemStatusProvider),
          ),
          const Gap(8),
        ],
      ),
      body: PageListView(
        onRefresh: () async {
          ref.invalidate(systemStatusProvider);
          await ref.read(systemStatusProvider.future).catchError((_) => const SystemStatus());
        },
        children: [
          const SectionHeader('État du système'),
          // Le menu reste utilisable même si le monitoring ne répond pas.
          if (status.hasValue)
            _SystemSummary(status: status.value!)
          else if (status.hasError)
            InlineError(error: status.error!, onRetry: () => ref.invalidate(systemStatusProvider))
          else
            const LoadingView(padding: EdgeInsets.symmetric(vertical: 40)),
          const SectionHeader('Comptes et collecte'),
          MenuGroup(
            children: [
              MenuTile(
                icon: Icons.people_outline_rounded,
                title: 'Utilisateurs',
                subtitle: 'Créer des comptes, activer, gérer les droits',
                onTap: () => context.push(Routes.adminUsers),
              ),
              MenuTile(
                icon: Icons.rss_feed_rounded,
                title: 'Sources',
                subtitle: 'Sites, API et flux d\'offres',
                onTap: () => context.push(Routes.adminSources),
              ),
              MenuTile(
                icon: Icons.cloud_sync_outlined,
                title: 'Collectes',
                subtitle: 'Historique et suivi des récupérations',
                onTap: () => context.push(Routes.adminRuns),
              ),
              MenuTile(
                icon: Icons.monitor_heart_outlined,
                title: 'Système & maintenance',
                subtitle: 'Services, statistiques, tâches de maintenance',
                onTap: () => context.push(Routes.adminSystem),
              ),
              MenuTile(
                icon: Icons.history_rounded,
                title: 'Journal d\'audit',
                subtitle: 'Opérations sensibles tracées par le serveur',
                onTap: () => context.push(Routes.adminAudit),
              ),
            ],
          ),
          const SectionHeader('Données'),
          MenuGroup(
            children: [
              MenuTile(
                icon: Icons.business_outlined,
                title: 'Entreprises',
                subtitle: 'Fiches entreprises et provenance des informations',
                onTap: () => context.push(Routes.adminCompanies),
              ),
              MenuTile(
                icon: Icons.badge_outlined,
                title: 'Recruteurs',
                subtitle: 'Contacts publics et leur provenance',
                onTap: () => context.push(Routes.adminRecruiters),
              ),
              MenuTile(
                icon: Icons.category_outlined,
                title: 'Référentiels',
                subtitle: 'Contrats, niveaux, catégories et compétences',
                onTap: () => context.push(Routes.adminReference),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SystemSummary extends StatelessWidget {
  const _SystemSummary({required this.status});

  final SystemStatus status;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SystemSummaryCard(status: status, onTap: () => context.push(Routes.adminSystem)),
      const Gap(10),
      ServicesGrid(services: status.services),
      const Gap(10),
      SystemMetricsGrid(status: status, onUsersTap: () => context.push(Routes.adminUsers)),
    ],
  );
}
