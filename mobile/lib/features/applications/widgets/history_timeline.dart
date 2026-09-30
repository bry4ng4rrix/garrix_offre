import 'package:flutter/material.dart';

import '../../../core/models/enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/ui.dart';
import '../data/application_models.dart';

/// Historique des statuts, le plus récent en haut.
class HistoryTimeline extends StatelessWidget {
  const HistoryTimeline({super.key, required this.entries});

  final List<StatusHistoryEntry> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final items = entries.reversed.toList();
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 16,
                    child: Column(
                      children: [
                        const Gap(4),
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: i == 0 ? items[i].toStatus.color : Colors.transparent,
                            shape: BoxShape.circle,
                            border: Border.all(color: items[i].toStatus.color, width: 1.5),
                          ),
                        ),
                        if (i < items.length - 1)
                          Expanded(
                            child: Container(
                              width: 1.5,
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              color: AppColors.border,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Gap(14),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            items[i].toStatus.label,
                            style: theme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: i == 0 ? AppColors.textPrimary : AppColors.textSecondary,
                            ),
                          ),
                          if (items[i].note != null) ...[
                            const Gap(2),
                            Text(
                              items[i].note!,
                              style: theme.bodySmall?.copyWith(color: AppColors.textSecondary),
                            ),
                          ],
                          const Gap(2),
                          Text(
                            [
                              Fmt.dateTime(items[i].changedAt),
                              if (items[i].actorType != null &&
                                  items[i].actorType != ActorType.user)
                                items[i].actorType!.label,
                            ].join(' · '),
                            style: theme.labelSmall?.copyWith(color: AppColors.textTertiary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
