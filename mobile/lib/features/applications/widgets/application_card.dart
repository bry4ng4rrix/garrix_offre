import 'package:flutter/material.dart';

import '../../../core/models/enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/ui.dart';
import '../data/application_models.dart';
import 'common.dart';

/// Carte d'une candidature dans la liste.
class ApplicationCard extends StatelessWidget {
  const ApplicationCard({super.key, required this.application, this.onTap});

  final Application application;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final (icon, label, color) = keyDate(application);
    final hint = shortNextStep(application.status);
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      application.displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.titleMedium,
                    ),
                    const Gap(2),
                    Text(
                      application.companyName ?? 'Entreprise non précisée',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const Gap(12),
              ApplicationStatusPill(application.status, dense: true),
            ],
          ),
          const Gap(14),
          Row(
            children: [
              Icon(icon, size: 15, color: color),
              const Gap(6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.bodySmall?.copyWith(color: color),
                ),
              ),
              if (hint != null) ...[
                const Gap(8),
                Text(hint, style: theme.labelSmall?.copyWith(color: AppColors.textTertiary)),
                const Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.textTertiary),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Date clé d'une candidature : relance, envoi ou dernière mise à jour.
(IconData, String, Color) keyDate(Application application) {
  final status = application.status;
  final followUp = application.followUpAt;
  if (application.isFollowUpDue()) {
    return (
      Icons.notification_important_outlined,
      'Relance à faire · prévue le ${Fmt.date(followUp)}',
      AppColors.warning,
    );
  }
  if (followUp != null &&
      (status == ApplicationStatus.submitted || status == ApplicationStatus.followUp)) {
    return (
      Icons.schedule_rounded,
      'Relance prévue le ${Fmt.date(followUp)}',
      AppColors.textSecondary,
    );
  }
  if (application.submittedAt != null) {
    return (
      Icons.send_outlined,
      'Envoyée ${relativeDate(application.submittedAt)}',
      AppColors.textSecondary,
    );
  }
  return (
    Icons.update_rounded,
    'Mise à jour ${relativeDate(application.updatedAt)}',
    AppColors.textTertiary,
  );
}
