import 'package:flutter/material.dart';

import '../../../core/models/enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/ui.dart';
import '../data/admin_labels.dart';
import '../data/monitoring_models.dart';
import 'admin_ui.dart';

/// Blocs d'affichage de l'état du système (hub Administration et page Système).

Color serviceColor(ServiceHealth service) => switch (service.status) {
  'ok' => AppColors.success,
  'error' => AppColors.danger,
  'eager' => AppColors.warning,
  _ => AppColors.textTertiary,
};

String serviceStateLabel(ServiceHealth service) {
  final state = switch (service.status) {
    'ok' => 'Opérationnel',
    'error' => 'En erreur',
    'eager' => 'Mode synchrone',
    _ => 'Inconnu',
  };
  if (service.key == 'worker' && service.workers != null && service.status != 'eager') {
    final n = service.workers!;
    return '$state · $n worker${n > 1 ? 's' : ''}';
  }
  if (service.latencyMs != null) {
    final ms = service.latencyMs!;
    final text = ms < 10 ? ms.toStringAsFixed(1).replaceAll('.', ',') : ms.round().toString();
    return '$state · $text ms';
  }
  return state;
}

/// Résumé global : tous les services sont-ils opérationnels ?
class SystemSummaryCard extends StatelessWidget {
  const SystemSummaryCard({super.key, required this.status, this.onTap});

  final SystemStatus status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final failing = status.failing;
    final ok = failing.isEmpty;
    final color = ok ? AppColors.success : AppColors.danger;
    final title = ok
        ? 'Tous les services sont opérationnels'
        : failing.length == 1
        ? '${serviceLabel(failing.first.key)} est en erreur'
        : '${failing.length} services en erreur';
    final meta = [
      if (status.version != null) 'v${status.version}',
      environmentLabel(status.environment),
      if (status.uptimeSeconds != null) 'démarré il y a ${Fmt.duration(status.uptimeSeconds)}',
    ].join(' · ');

    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: AppColors.tint(color), shape: BoxShape.circle),
            child: Icon(
              ok ? Icons.check_rounded : Icons.priority_high_rounded,
              color: color,
              size: 22,
            ),
          ),
          const Gap(14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.titleSmall),
                const Gap(2),
                Text(meta, style: theme.bodySmall?.copyWith(color: AppColors.textTertiary)),
              ],
            ),
          ),
          if (onTap != null) const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
        ],
      ),
    );
  }
}

/// Grille des services (API, PostgreSQL, Redis, worker, n8n).
class ServicesGrid extends StatelessWidget {
  const ServicesGrid({super.key, required this.services});

  final List<ServiceHealth> services;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return ResponsiveGrid(
      minItemWidth: 140,
      maxColumns: 5,
      children: [
        for (final service in services)
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    StatusDot(color: serviceColor(service)),
                    const Gap(8),
                    Expanded(
                      child: Text(
                        serviceLabel(service.key),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const Gap(4),
                Text(
                  serviceStateLabel(service),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Indicateurs chiffrés (utilisateurs, offres, taille de la base...).
class SystemMetricsGrid extends StatelessWidget {
  const SystemMetricsGrid({super.key, required this.status, this.onUsersTap});

  final SystemStatus status;
  final VoidCallback? onUsersTap;

  @override
  Widget build(BuildContext context) => ResponsiveGrid(
    minItemWidth: 150,
    children: [
      StatTile(
        label: 'Utilisateurs',
        value: Fmt.number(status.users),
        icon: Icons.people_outline_rounded,
        onTap: onUsersTap,
      ),
      StatTile(
        label: 'Offres',
        value: Fmt.number(status.jobsTotal),
        icon: Icons.work_outline_rounded,
      ),
      StatTile(
        label: 'Base de données',
        value: Fmt.fileSize(status.databaseSizeBytes),
        icon: Icons.storage_rounded,
      ),
      StatTile(
        label: 'Fichiers',
        value: Fmt.fileSize(status.storageSizeBytes),
        icon: Icons.folder_outlined,
      ),
      StatTile(
        label: 'Temps réel',
        value: Fmt.number(status.websocketConnections),
        icon: Icons.bolt_rounded,
        caption: 'connexion${status.websocketConnections > 1 ? 's' : ''} active${status.websocketConnections > 1 ? 's' : ''}',
      ),
    ],
  );
}

/// Répartition des offres par statut.
class JobsByStatusRow extends StatelessWidget {
  const JobsByStatusRow({super.key, required this.counts});

  final Map<String, int> counts;

  @override
  Widget build(BuildContext context) {
    if (counts.isEmpty) {
      return Text(
        'Aucune offre en base.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in counts.entries)
          Pill(
            '${JobStatus.fromApi(entry.key)?.label ?? entry.key} · ${Fmt.number(entry.value)}',
            color: JobStatus.fromApi(entry.key)?.color,
          ),
      ],
    );
  }
}

/// Configuration du serveur (IA, notifications, Telegram, email).
class SystemConfigCard extends StatelessWidget {
  const SystemConfigCard({super.key, required this.status});

  final SystemStatus status;

  @override
  Widget build(BuildContext context) {
    Widget row(IconData icon, String label, String value, {bool? ok}) {
      final theme = Theme.of(context).textTheme;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.textTertiary),
            const Gap(12),
            Expanded(child: Text(label, style: theme.bodyMedium)),
            if (ok != null) ...[
              Icon(
                ok ? Icons.check_circle_rounded : Icons.remove_circle_outline_rounded,
                size: 16,
                color: ok ? AppColors.success : AppColors.textTertiary,
              ),
              const Gap(6),
            ],
            Text(value, style: theme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
          ],
        ),
      );
    }

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        children: [
          row(
            Icons.auto_awesome_outlined,
            'Intelligence artificielle',
            aiProviderLabel(status.aiProvider),
            ok: status.aiEnabled,
          ),
          row(
            Icons.notifications_none_rounded,
            'Envoi des notifications',
            deliveryLabel(status.notificationDelivery),
          ),
          row(
            Icons.send_outlined,
            'Telegram',
            status.telegramConfigured ? 'Configuré' : 'Non configuré',
            ok: status.telegramConfigured,
          ),
          row(
            Icons.mail_outline_rounded,
            'Email (SMTP)',
            status.emailConfigured ? 'Configuré' : 'Non configuré',
            ok: status.emailConfigured,
          ),
        ],
      ),
    );
  }
}
