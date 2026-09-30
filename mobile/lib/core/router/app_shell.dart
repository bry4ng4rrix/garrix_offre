import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/enums.dart';
import '../realtime/realtime_service.dart';
import '../theme/app_colors.dart';
import '../widgets/feedback.dart';
import 'routes.dart';

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _destinations = [
  _Destination('Accueil', Icons.space_dashboard_outlined, Icons.space_dashboard_rounded),
  _Destination('Offres', Icons.work_outline_rounded, Icons.work_rounded),
  _Destination('Candidatures', Icons.send_outlined, Icons.send_rounded),
  _Destination('Alertes', Icons.notifications_none_rounded, Icons.notifications_rounded),
  _Destination('Profil', Icons.person_outline_rounded, Icons.person_rounded),
];

/// Coquille de navigation : barre du bas (mobile) ou rail latéral (écran large, Linux).
/// Affiche aussi les événements temps réel importants.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const wideBreakpoint = 840.0;

  void _go(int index) => navigationShell.goBranch(
    index,
    initialLocation: index == navigationShell.currentIndex,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider);
    ref.listen(realtimeEventsProvider, (_, next) {
      final event = next.value;
      if (event != null) _announce(context, event);
    });

    final wide = MediaQuery.sizeOf(context).width >= wideBreakpoint;
    Widget icon(int index, {required bool selected}) {
      final destination = _destinations[index];
      final widget = Icon(selected ? destination.selectedIcon : destination.icon);
      if (index != 3 || unread == 0) return widget;
      return Badge.count(count: unread, child: widget);
    }

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            SafeArea(
              child: NavigationRail(
                selectedIndex: navigationShell.currentIndex,
                onDestinationSelected: _go,
                labelType: NavigationRailLabelType.all,
                groupAlignment: -0.9,
                leading: const Padding(
                  padding: EdgeInsets.only(top: 8, bottom: 24),
                  child: _Logo(),
                ),
                destinations: [
                  for (var i = 0; i < _destinations.length; i++)
                    NavigationRailDestination(
                      icon: icon(i, selected: false),
                      selectedIcon: icon(i, selected: true),
                      label: Text(_destinations[i].label),
                    ),
                ],
              ),
            ),
            const VerticalDivider(width: 1, thickness: 1, color: AppColors.border),
            Expanded(child: navigationShell),
          ],
        ),
      );
    }

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: NavigationBar(
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: _go,
          destinations: [
            for (var i = 0; i < _destinations.length; i++)
              NavigationDestination(
                icon: icon(i, selected: false),
                selectedIcon: icon(i, selected: true),
                label: _destinations[i].label,
              ),
          ],
        ),
      ),
    );
  }

  /// Message discret pour les notifications reçues en temps réel.
  void _announce(BuildContext context, RealtimeEvent event) {
    if (event.type != 'notification') return;
    final type = NotificationType.fromApi(event.data['type']);
    final title = event.data['title']?.toString() ?? type?.label ?? 'Nouvelle notification';
    showToast(
      title,
      action: SnackBarAction(
        label: 'Voir',
        onPressed: () => GoRouter.of(context).go(Routes.notifications),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(
      color: AppColors.textPrimary,
      borderRadius: BorderRadius.circular(12),
    ),
    alignment: Alignment.center,
    child: const Text(
      'G',
      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.onAccent),
    ),
  );
}
