import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/ui.dart';
import '../data/notification_models.dart';

/// Icône du type de notification dans un cercle teinté.
class NotificationTypeIcon extends StatelessWidget {
  const NotificationTypeIcon({super.key, required this.notification, this.size = 40});

  final AppNotification notification;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = notification.type?.color ?? AppColors.textSecondary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: AppColors.tint(color, 0.14), shape: BoxShape.circle),
      child: Icon(
        notification.type?.icon ?? Icons.notifications_none_rounded,
        size: size * 0.5,
        color: color,
      ),
    );
  }
}

/// Élément de la liste des alertes : icône, titre, message (2 lignes), type et date.
/// Les notifications non lues sont mises en avant (fond plus clair, titre blanc, point).
class NotificationTile extends StatelessWidget {
  const NotificationTile({super.key, required this.notification, this.onTap, this.onLongPress});

  final AppNotification notification;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final unread = !notification.isRead;
    final score = notification.score;
    final meta = [
      notification.type?.label ?? 'Notification',
      Fmt.relative(notification.createdAt),
    ].join(' · ');

    return Semantics(
      label: unread ? 'Non lue' : null,
      child: AppCard(
        onTap: onTap,
        onLongPress: onLongPress,
        color: unread ? AppColors.surfaceRaised : AppColors.surface,
        borderColor: unread ? AppColors.borderStrong : AppColors.border,
        padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NotificationTypeIcon(notification: notification),
            const Gap(12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.titleSmall?.copyWith(
                            color: unread ? AppColors.textPrimary : AppColors.textSecondary,
                            fontWeight: unread ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                      ),
                      if (unread) ...[
                        const Gap(10),
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (notification.message.trim().isNotEmpty) ...[
                    const Gap(4),
                    Text(
                      notification.message.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.bodyMedium?.copyWith(
                        color: unread ? AppColors.textSecondary : AppColors.textTertiary,
                      ),
                    ),
                  ],
                  const Gap(10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.labelSmall?.copyWith(color: AppColors.textTertiary),
                        ),
                      ),
                      if (score != null) ...[
                        const Gap(8),
                        Pill(Fmt.score(score), color: AppColors.score(score), dense: true),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fond affiché pendant le balayage de suppression.
class NotificationDismissBackground extends StatelessWidget {
  const NotificationDismissBackground({super.key});

  @override
  Widget build(BuildContext context) => Container(
    alignment: Alignment.centerRight,
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
    decoration: BoxDecoration(
      color: AppColors.tint(AppColors.danger, 0.16),
      borderRadius: AppRadius.card,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Supprimer',
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: AppColors.danger, fontWeight: FontWeight.w600),
        ),
        const Gap(8),
        const Icon(Icons.delete_outline_rounded, color: AppColors.danger, size: 20),
      ],
    ),
  );
}
