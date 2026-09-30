import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/realtime/realtime_service.dart';
import '../../core/router/routes.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/paged_list_view.dart';
import '../../core/widgets/ui.dart';
import 'data/notification_models.dart';
import 'data/notifications_repository.dart';
import 'widgets/notification_detail_sheet.dart';
import 'widgets/notification_filter_bar.dart';
import 'widgets/notification_tile.dart';

/// Onglet « Alertes » : notifications filtrables, lecture, suppression par balayage.
class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  final _controller = PagedListController();
  NotificationFilter _filter = const NotificationFilter();
  Timer? _realtimeDebounce;

  NotificationsRepository get _repository => ref.read(notificationsRepositoryProvider);

  @override
  void dispose() {
    _realtimeDebounce?.cancel();
    super.dispose();
  }

  /// Nouvelle notification reçue en temps réel : on recharge (regroupe les rafales).
  void _onRealtime(RealtimeEvent? event) {
    if (event?.type != 'notification') return;
    _realtimeDebounce?.cancel();
    _realtimeDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) unawaited(_controller.refresh());
    });
  }

  Future<void> _markRead(AppNotification notification) async {
    if (notification.isRead) return;
    final counter = ref.read(unreadCountProvider.notifier);
    _controller.updateWhere<AppNotification>(
      (item) => item.id == notification.id,
      (item) => item.markedRead(),
    );
    counter.decrement();
    try {
      await _repository.markRead(notification.id);
    } catch (_) {
      // Échec discret : on resynchronise simplement le compteur.
      await counter.refresh();
    }
  }

  Future<void> _markAllRead() async {
    final updated = await runAction(_repository.markAllRead);
    if (updated == null || !mounted) return;
    ref.read(unreadCountProvider.notifier).reset();
    if (_filter.unreadOnly) {
      unawaited(_controller.refresh());
    } else {
      _controller.updateWhere<AppNotification>((item) => !item.isRead, (item) => item.markedRead());
    }
    showToast(switch (updated) {
      0 => 'Tout est déjà lu',
      1 => '1 alerte marquée comme lue',
      _ => '$updated alertes marquées comme lues',
    }, kind: ToastKind.success);
  }

  /// Supprime côté serveur. Renvoie false (et affiche l'erreur) en cas d'échec.
  Future<bool> _delete(AppNotification notification) async {
    try {
      await _repository.delete(notification.id);
    } on ApiException catch (error) {
      // Déjà supprimée ailleurs : on la retire quand même de la liste.
      if (!error.isNotFound) {
        showError(error);
        return false;
      }
    } catch (error) {
      showError(error);
      return false;
    }
    if (!notification.isRead) ref.read(unreadCountProvider.notifier).decrement();
    return true;
  }

  void _remove(AppNotification notification) =>
      _controller.removeWhere<AppNotification>((item) => item.id == notification.id);

  void _navigate(NotificationLink link) {
    if (link.switchTab) {
      context.go(link.location);
    } else {
      unawaited(context.push(link.location));
    }
  }

  /// Ouvre la page liée (offre, candidature...) ; sans destination, affiche le détail.
  void _open(AppNotification notification) {
    final link = notificationLink(notification, isAdmin: ref.read(isAdminProvider));
    if (link == null) {
      unawaited(_showDetails(notification));
      return;
    }
    unawaited(_markRead(notification));
    _navigate(link);
  }

  Future<void> _showDetails(AppNotification notification) async {
    unawaited(_markRead(notification));
    final link = notificationLink(notification, isAdmin: ref.read(isAdminProvider));
    final action = await showAppSheet<NotificationSheetAction>(
      context,
      builder: (_) => NotificationDetailSheet(notification: notification, link: link),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case NotificationSheetAction.open:
        if (link != null) _navigate(link);
      case NotificationSheetAction.delete:
        final confirmed = await confirmDialog(
          context,
          title: 'Supprimer cette alerte ?',
          message: 'Elle disparaîtra de la liste. Cette action est définitive.',
          confirmLabel: 'Supprimer',
          destructive: true,
        );
        if (!confirmed || !mounted) return;
        if (await _delete(notification)) {
          _remove(notification);
          showToast('Alerte supprimée', kind: ToastKind.success);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(realtimeEventsProvider, (_, next) => _onRealtime(next.value));
    final unread = ref.watch(unreadCountProvider);
    final isAdmin = ref.watch(isAdminProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alertes'),
        actions: [
          TextButton.icon(
            onPressed: unread == 0 ? null : _markAllRead,
            icon: const Icon(Icons.done_all_rounded, size: 18),
            label: const Text('Tout lire'),
          ),
          IconButton(
            tooltip: 'Préférences de notification',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => context.push(Routes.notificationSettings),
          ),
          const Gap(8),
        ],
      ),
      body: Column(
        children: [
          NotificationFilterBar(
            filter: _filter,
            unread: unread,
            isAdmin: isAdmin,
            onChanged: (filter) => setState(() => _filter = filter),
          ),
          Expanded(
            child: PagedListView<AppNotification>(
              key: ValueKey(_filter),
              controller: _controller,
              fetch: (page) =>
                  _repository.list(page: page, unreadOnly: _filter.unreadOnly, type: _filter.type),
              // Chaque rechargement de la liste resynchronise aussi le badge de l'onglet.
              onTotal: (_) => unawaited(ref.read(unreadCountProvider.notifier).refresh()),
              emptyBuilder: (_) => _emptyState(),
              itemBuilder: (context, notification) => Dismissible(
                key: ValueKey('notification-${notification.id}'),
                direction: DismissDirection.endToStart,
                background: const NotificationDismissBackground(),
                confirmDismiss: (_) => _delete(notification),
                onDismissed: (_) => _remove(notification),
                child: NotificationTile(
                  notification: notification,
                  onTap: () => _open(notification),
                  onLongPress: () => _showDetails(notification),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    void showAll() => setState(() => _filter = const NotificationFilter());
    if (_filter.type != null) {
      return EmptyState(
        icon: _filter.type!.icon,
        title: _filter.unreadOnly
            ? 'Aucune alerte non lue de ce type'
            : 'Aucune alerte « ${_filter.type!.label} »',
        actionLabel: 'Voir toutes les alertes',
        onAction: showAll,
      );
    }
    if (_filter.unreadOnly) {
      return EmptyState(
        icon: Icons.done_all_rounded,
        title: 'Vous êtes à jour',
        message: 'Aucune alerte non lue.',
        actionLabel: 'Voir toutes les alertes',
        onAction: showAll,
      );
    }
    return EmptyState(
      icon: Icons.notifications_none_rounded,
      title: 'Aucune alerte pour l\'instant',
      message:
          'Les offres très compatibles, le suivi de vos candidatures et les réponses '
          'des recruteurs apparaîtront ici.',
      actionLabel: 'Régler mes alertes',
      onAction: () => context.push(Routes.notificationSettings),
    );
  }
}
