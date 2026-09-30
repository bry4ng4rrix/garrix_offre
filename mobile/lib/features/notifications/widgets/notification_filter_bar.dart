import 'package:flutter/material.dart';

import '../../../core/models/enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/ui.dart';

/// Filtres de la liste des alertes : non lues uniquement et/ou un type.
@immutable
class NotificationFilter {
  const NotificationFilter({this.unreadOnly = false, this.type});

  final bool unreadOnly;
  final NotificationType? type;

  bool get isEmpty => !unreadOnly && type == null;

  @override
  bool operator ==(Object other) =>
      other is NotificationFilter && other.unreadOnly == unreadOnly && other.type == type;

  @override
  int get hashCode => Object.hash(unreadOnly, type);
}

/// Types proposés en filtre (erreurs de collecte et monitoring : administrateurs seulement).
List<NotificationType> filterableTypes({required bool isAdmin}) => [
  for (final type in NotificationType.values)
    if (isAdmin || (type != NotificationType.scrapingError && type != NotificationType.monitoring))
      type,
];

/// Rangée de pastilles défilante : Toutes · Non lues · types.
class NotificationFilterBar extends StatelessWidget {
  const NotificationFilterBar({
    super.key,
    required this.filter,
    required this.onChanged,
    required this.isAdmin,
    this.unread = 0,
  });

  final NotificationFilter filter;
  final ValueChanged<NotificationFilter> onChanged;
  final bool isAdmin;
  final int unread;

  @override
  Widget build(BuildContext context) {
    return PageBody(
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: 52,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, 4, AppSpacing.page, 8),
          children: [
            _chip(
              context,
              label: 'Toutes',
              selected: filter.isEmpty,
              onTap: () => onChanged(const NotificationFilter()),
            ),
            _chip(
              context,
              label: unread > 0 ? 'Non lues · $unread' : 'Non lues',
              selected: filter.unreadOnly,
              onTap: () =>
                  onChanged(NotificationFilter(unreadOnly: !filter.unreadOnly, type: filter.type)),
            ),
            for (final type in filterableTypes(isAdmin: isAdmin))
              _chip(
                context,
                label: type.label,
                icon: type.icon,
                iconColor: type.color,
                selected: filter.type == type,
                onTap: () => onChanged(
                  NotificationFilter(
                    unreadOnly: filter.unreadOnly,
                    type: filter.type == type ? null : type,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _chip(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
    Color? iconColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        avatar: icon == null
            ? null
            : Icon(icon, size: 16, color: selected ? AppColors.onAccent : iconColor),
        labelStyle: TextStyle(
          color: selected ? AppColors.onAccent : AppColors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
        side: BorderSide(color: selected ? AppColors.accent : AppColors.borderStrong),
        materialTapTargetSize: MaterialTapTargetSize.padded,
      ),
    );
  }
}
