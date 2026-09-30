import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../network/api_client.dart';
import '../network/api_exception.dart';
import 'app_user.dart';
import 'token_storage.dart';

enum AuthStatus { unknown, signedOut, signedIn }

class AuthState {
  const AuthState._(this.status, {this.user, this.message});

  const AuthState.unknown() : this._(AuthStatus.unknown);
  const AuthState.signedOut({String? message}) : this._(AuthStatus.signedOut, message: message);
  const AuthState.signedIn(AppUser user) : this._(AuthStatus.signedIn, user: user);

  final AuthStatus status;
  final AppUser? user;

  /// Message à afficher sur l'écran de connexion (ex. session expirée).
  final String? message;

  bool get isSignedIn => status == AuthStatus.signedIn;
}

/// Session de l'utilisateur : restauration au démarrage, connexion, inscription, déconnexion.
class AuthController extends Notifier<AuthState> {
  static const _cachedUserKey = 'garrix_cached_user';

  @override
  AuthState build() {
    Future.microtask(_restore);
    return const AuthState.unknown();
  }

  ApiClient get _api => ref.read(apiClientProvider);
  TokenStorage get _tokens => ref.read(tokenStorageProvider);

  Future<void> _restore() async {
    await _tokens.load();
    if (!_tokens.hasSession) {
      state = const AuthState.signedOut();
      return;
    }
    try {
      state = AuthState.signedIn(await _fetchMe());
    } on ApiException catch (error) {
      if (error.isNetwork) {
        // Hors ligne : on garde la session avec l'utilisateur mémorisé.
        final cached = _cachedUser();
        state = cached != null ? AuthState.signedIn(cached) : const AuthState.signedOut();
      } else {
        await _tokens.clear();
        state = const AuthState.signedOut();
      }
    }
  }

  Future<void> login({required String email, required String password}) async {
    final data = asJsonMap(
      await _api.post('/auth/login', body: {'email': email.trim(), 'password': password}),
    );
    await _tokens.save(
      accessToken: data['access_token'] as String,
      refreshToken: data['refresh_token'] as String,
    );
    state = AuthState.signedIn(await _fetchMe());
  }

  Future<void> register({required String email, required String password}) async {
    await _api.post('/auth/register', body: {'email': email.trim(), 'password': password});
    await login(email: email, password: password);
  }

  Future<void> logout({bool allDevices = false}) async {
    final refreshToken = _tokens.refreshToken;
    try {
      await _api.post(
        '/auth/logout',
        body: {'refresh_token': refreshToken, 'all_devices': allDevices},
      );
    } catch (_) {
      // Déconnexion locale même si le serveur est injoignable.
    }
    await _signOut();
  }

  /// Appelé par [ApiClient] quand le token ne peut plus être renouvelé.
  void onSessionExpired() {
    if (state.status == AuthStatus.signedIn) {
      unawaited(_signOut(message: 'Session expirée. Reconnectez-vous.'));
    }
  }

  /// Relit l'utilisateur (après un changement de rôle, par exemple).
  Future<void> refreshUser() async {
    if (!state.isSignedIn) return;
    state = AuthState.signedIn(await _fetchMe());
  }

  Future<AppUser> _fetchMe() async {
    final user = AppUser.fromJson(asJsonMap(await _api.get('/auth/me')));
    await ref.read(sharedPreferencesProvider).setString(_cachedUserKey, jsonEncode(user.toJson()));
    return user;
  }

  AppUser? _cachedUser() {
    final raw = ref.read(sharedPreferencesProvider).getString(_cachedUserKey);
    if (raw == null) return null;
    try {
      return AppUser.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  Future<void> _signOut({String? message}) async {
    await _tokens.clear();
    await ref.read(sharedPreferencesProvider).remove(_cachedUserKey);
    state = AuthState.signedOut(message: message);
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);

/// Utilisateur connecté (null si déconnecté).
final currentUserProvider = Provider<AppUser?>((ref) => ref.watch(authControllerProvider).user);

/// Vrai si l'utilisateur connecté est administrateur.
final isAdminProvider = Provider<bool>(
  (ref) => ref.watch(currentUserProvider)?.isSuperuser ?? false,
);
