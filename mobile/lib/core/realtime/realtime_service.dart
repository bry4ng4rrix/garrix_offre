import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../auth/auth_controller.dart';
import '../network/api_client.dart';
import '../utils/json.dart';

/// Événement reçu sur `WS /api/v1/ws`.
///
/// Types : connected, notification, new_job, high_match, application_status,
/// recruiter_response, scraping_run, scraping_error, matching_recalculated, monitoring.
class RealtimeEvent {
  const RealtimeEvent({required this.type, required this.data, this.timestamp});

  final String type;
  final Map<String, dynamic> data;
  final DateTime? timestamp;

  factory RealtimeEvent.fromJson(Map<String, dynamic> json) => RealtimeEvent(
    type: json['type']?.toString() ?? 'unknown',
    data: parseMap(json['data']),
    timestamp: parseDate(json['timestamp']),
  );
}

/// Connexion WebSocket avec reconnexion automatique.
///
/// Le serveur ferme la connexion (code 4001) à l'expiration de l'access token :
/// on renouvelle le token puis on se reconnecte.
class RealtimeService {
  RealtimeService(this._ref);

  final Ref _ref;
  final _events = StreamController<RealtimeEvent>.broadcast();
  final connected = ValueNotifier<bool>(false);

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  bool _running = false;
  int _attempt = 0;

  Stream<RealtimeEvent> get events => _events.stream;

  void start() {
    if (_running) return;
    _running = true;
    _attempt = 0;
    unawaited(_connect());
  }

  void stop() {
    _running = false;
    _reconnectTimer?.cancel();
    _closeChannel();
  }

  Future<void> _connect() async {
    if (!_running) return;
    _closeChannel();
    final api = _ref.read(apiClientProvider);
    final channel = WebSocketChannel.connect(api.websocketUri());
    _channel = channel;
    try {
      await channel.ready;
    } catch (error) {
      debugPrint('WebSocket : connexion impossible ($error)');
      _scheduleReconnect();
      return;
    }
    _attempt = 0;
    connected.value = true;
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) => channel.sink.add('ping'));
    _subscription = channel.stream.listen(
      _onMessage,
      onDone: () => _onClosed(channel.closeCode),
      onError: (_) => _onClosed(null),
      cancelOnError: true,
    );
  }

  void _onMessage(dynamic message) {
    if (message is! String) return;
    try {
      final event = RealtimeEvent.fromJson((jsonDecode(message) as Map).cast<String, dynamic>());
      if (event.type != 'pong') _events.add(event);
    } catch (_) {
      // Message inattendu : ignoré.
    }
  }

  Future<void> _onClosed(int? code) async {
    connected.value = false;
    _pingTimer?.cancel();
    if (!_running) return;
    // 4001 : token expiré ; 1008 : token refusé. On tente un renouvellement.
    if (code == 4001 || code == 1008) {
      try {
        final refreshed = await _ref.read(apiClientProvider).refreshTokens();
        if (!refreshed) {
          _ref.read(authControllerProvider.notifier).onSessionExpired();
          return;
        }
        _attempt = 0;
        unawaited(_connect());
        return;
      } catch (_) {
        // Réseau indisponible : reconnexion différée.
      }
    }
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    connected.value = false;
    if (!_running) return;
    _reconnectTimer?.cancel();
    _attempt += 1;
    final seconds = [2, 4, 8, 15, 30, 60][(_attempt - 1).clamp(0, 5)];
    _reconnectTimer = Timer(Duration(seconds: seconds), () => unawaited(_connect()));
  }

  void _closeChannel() {
    _pingTimer?.cancel();
    unawaited(_subscription?.cancel());
    _subscription = null;
    unawaited(_channel?.sink.close());
    _channel = null;
    connected.value = false;
  }

  void dispose() {
    stop();
    unawaited(_events.close());
    connected.dispose();
  }
}

final realtimeServiceProvider = Provider<RealtimeService>((ref) {
  final service = RealtimeService(ref);
  ref.onDispose(service.dispose);
  return service;
});

/// Flux des événements temps réel (à écouter avec `ref.listen`).
final realtimeEventsProvider = StreamProvider<RealtimeEvent>(
  (ref) => ref.watch(realtimeServiceProvider).events,
);

/// Nombre de notifications non lues (REST au démarrage, puis mis à jour en temps réel).
class UnreadCountNotifier extends Notifier<int> {
  @override
  int build() {
    final userId = ref.watch(currentUserProvider.select((user) => user?.id));
    if (userId == null) return 0;
    final subscription = ref.read(realtimeServiceProvider).events.listen((event) {
      if (event.type == 'connected') {
        state = parseInt(event.data['unread_notifications']) ?? state;
      } else if (event.type == 'notification') {
        state = state + 1;
      }
    });
    ref.onDispose(subscription.cancel);
    Future.microtask(refresh);
    return 0;
  }

  Future<void> refresh() async {
    try {
      final data = asJsonMap(await ref.read(apiClientProvider).get('/notifications/unread-count'));
      state = parseInt(data['unread']) ?? 0;
    } catch (_) {
      // Compteur indicatif : une erreur ne doit rien bloquer.
    }
  }

  void decrement([int by = 1]) => state = (state - by).clamp(0, 1 << 30);

  void reset() => state = 0;
}

final unreadCountProvider = NotifierProvider<UnreadCountNotifier, int>(UnreadCountNotifier.new);
