import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/enums.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/paginated.dart';
import '../../../core/utils/json.dart';
import 'notification_models.dart';

/// Accès à l'API des notifications (`/notifications`).
class NotificationsRepository {
  const NotificationsRepository(this._api);

  final ApiClient _api;

  /// Les plus récentes d'abord. [unreadOnly] : seulement les non lues ; [type] : un seul type.
  Future<Paginated<AppNotification>> list({
    required int page,
    bool unreadOnly = false,
    NotificationType? type,
    int pageSize = 20,
  }) => _api.getPage(
    '/notifications',
    AppNotification.fromJson,
    page: page,
    pageSize: pageSize,
    query: {'is_read': unreadOnly ? false : null, 'type': type?.apiValue},
  );

  Future<AppNotification> markRead(String id) async =>
      AppNotification.fromJson(asJsonMap(await _api.patch('/notifications/$id/read')));

  /// Renvoie le nombre de notifications marquées comme lues.
  Future<int> markAllRead() async =>
      parseInt(asJsonMap(await _api.patch('/notifications/read-all'))['updated']) ?? 0;

  Future<void> delete(String id) => _api.delete('/notifications/$id');

  Future<NotificationSettings> settings() =>
      _api.getObject('/notifications/settings', NotificationSettings.fromJson);

  Future<NotificationSettings> updateSettings(NotificationSettings settings) async =>
      NotificationSettings.fromJson(
        asJsonMap(await _api.put('/notifications/settings', body: settings.toUpdateJson())),
      );

  /// Seuil de score des offres « très compatibles » (`GET /preferences`, 0-100).
  Future<int?> matchingThreshold() async =>
      parseInt(asJsonMap(await _api.get('/preferences'))['matching_threshold']);

  /// Mise à jour partielle des préférences : seul le seuil est envoyé.
  Future<void> updateMatchingThreshold(int value) =>
      _api.put('/preferences', body: {'matching_threshold': value.clamp(0, 100)});
}

final notificationsRepositoryProvider = Provider<NotificationsRepository>(
  (ref) => NotificationsRepository(ref.watch(apiClientProvider)),
);

/// Préférences de notification de l'utilisateur connecté.
final notificationSettingsProvider = FutureProvider.autoDispose<NotificationSettings>(
  (ref) => ref.watch(notificationsRepositoryProvider).settings(),
);

/// Seuil de compatibilité (null si les préférences sont indisponibles : section masquée).
final matchingThresholdProvider = FutureProvider.autoDispose<int?>((ref) async {
  try {
    return await ref.watch(notificationsRepositoryProvider).matchingThreshold();
  } catch (_) {
    return null;
  }
});
