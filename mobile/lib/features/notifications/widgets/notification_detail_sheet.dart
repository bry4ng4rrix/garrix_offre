import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/ui.dart';
import '../data/notification_models.dart';
import 'notification_tile.dart';

/// Action choisie dans la feuille de détail.
enum NotificationSheetAction { open, delete }

/// Détail d'une notification : message complet, date, canaux d'envoi et actions.
class NotificationDetailSheet extends StatelessWidget {
  const NotificationDetailSheet({super.key, required this.notification, this.link});

  final AppNotification notification;
  final NotificationLink? link;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final channels = notification.deliveredLabel;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                NotificationTypeIcon(notification: notification, size: 44),
                const Gap(12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notification.type?.label ?? 'Notification',
                        style: theme.labelMedium?.copyWith(
                          color: notification.type?.color ?? AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Gap(2),
                      Text(
                        Fmt.dateTime(notification.createdAt),
                        style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Gap(20),
            Text(notification.title, style: theme.titleLarge),
            if (notification.message.trim().isNotEmpty) ...[
              const Gap(10),
              SelectableText(
                notification.message.trim(),
                style: theme.bodyLarge?.copyWith(color: AppColors.textSecondary),
              ),
            ],
            if (channels.isNotEmpty) ...[
              const Gap(12),
              InfoRow(icon: Icons.send_outlined, label: 'Envoyée aussi sur', value: channels),
            ],
            const Gap(24),
            if (link != null) ...[
              PrimaryButton(
                label: link!.label,
                icon: Icons.arrow_forward_rounded,
                onPressed: () => Navigator.of(context).pop(NotificationSheetAction.open),
              ),
              const Gap(10),
            ],
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: BorderSide(color: AppColors.tint(AppColors.danger, 0.4)),
                ),
                onPressed: () => Navigator.of(context).pop(NotificationSheetAction.delete),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('Supprimer'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
