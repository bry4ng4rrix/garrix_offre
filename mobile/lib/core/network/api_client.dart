// ignore_for_file: prefer_initializing_formals (paramètres publics, champs privés)
import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../auth/token_storage.dart';
import '../config/app_config.dart';
import 'api_exception.dart';
import 'paginated.dart';

typedef JsonMap = Map<String, dynamic>;

/// Client HTTP de l'API Garrix Offre.
///
/// - préfixe `/api/v1` automatique : on écrit `api.get('/jobs')` ;
/// - déballe l'enveloppe `{"success": true, "data": ...}` et renvoie directement `data` ;
/// - lève [ApiException] (message en français dans `userMessage`) en cas d'erreur ;
/// - ajoute le token et le renouvelle automatiquement (une seule fois) sur une réponse 401.
class ApiClient {
  ApiClient({
    required this.serverUrl,
    required TokenStorage tokens,
    required void Function() onSessionExpired,
  }) : _tokens = tokens,
       _onSessionExpired = onSessionExpired {
    final options = BaseOptions(
      baseUrl: '$serverUrl$kApiPrefix',
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 60),
      // Large : la rédaction par une IA locale (Ollama sans GPU) peut prendre plusieurs minutes.
      receiveTimeout: const Duration(minutes: 10),
      headers: {'Accept': 'application/json'},
      listFormat: ListFormat.multi,
    );
    _dio = Dio(options);
    _refreshDio = Dio(options);
    _dio.interceptors.add(InterceptorsWrapper(onRequest: _onRequest, onError: _onError));
  }

  final String serverUrl;
  final TokenStorage _tokens;
  final void Function() _onSessionExpired;
  late final Dio _dio;
  late final Dio _refreshDio;
  Future<bool>? _refreshing;

  // ---------------------------------------------------------------------------
  // Requêtes : renvoient le champ `data` de l'enveloppe (null pour une réponse 204).
  // ---------------------------------------------------------------------------

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send(() => _dio.get<dynamic>(path, queryParameters: _clean(query)));

  Future<dynamic> post(String path, {Object? body, Map<String, dynamic>? query}) =>
      _send(() => _dio.post<dynamic>(path, data: body, queryParameters: _clean(query)));

  Future<dynamic> put(String path, {Object? body, Map<String, dynamic>? query}) =>
      _send(() => _dio.put<dynamic>(path, data: body, queryParameters: _clean(query)));

  Future<dynamic> patch(String path, {Object? body, Map<String, dynamic>? query}) =>
      _send(() => _dio.patch<dynamic>(path, data: body, queryParameters: _clean(query)));

  Future<void> delete(String path, {Map<String, dynamic>? query}) =>
      _send(() => _dio.delete<dynamic>(path, queryParameters: _clean(query)));

  /// Objet unique : `api.getObject('/profile', Profile.fromJson)`.
  Future<T> getObject<T>(
    String path,
    T Function(JsonMap json) fromJson, {
    Map<String, dynamic>? query,
  }) async => fromJson(asJsonMap(await get(path, query: query)));

  /// Liste simple (non paginée).
  Future<List<T>> getList<T>(
    String path,
    T Function(JsonMap json) fromJson, {
    Map<String, dynamic>? query,
  }) async => asJsonList(await get(path, query: query)).map(fromJson).toList();

  /// Liste paginée (`page` commence à 1, `pageSize` max 100).
  Future<Paginated<T>> getPage<T>(
    String path,
    T Function(JsonMap json) fromJson, {
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? query,
  }) async {
    final data = await get(path, query: {...?query, 'page': page, 'page_size': pageSize});
    return Paginated.fromJson(data, fromJson);
  }

  /// Envoi de fichier en multipart (`file` + champs de formulaire).
  Future<dynamic> upload(
    String path, {
    required String filePath,
    String? filename,
    String field = 'file',
    Map<String, dynamic>? fields,
    void Function(int sent, int total)? onProgress,
  }) async {
    final form = FormData.fromMap({
      ...?_clean(fields),
      field: await MultipartFile.fromFile(filePath, filename: filename),
    });
    return _send(() => _dio.post<dynamic>(path, data: form, onSendProgress: onProgress));
  }

  /// Envoi de fichier depuis des octets (quand aucun chemin n'est disponible).
  Future<dynamic> uploadBytes(
    String path, {
    required Uint8List bytes,
    required String filename,
    String field = 'file',
    Map<String, dynamic>? fields,
  }) async {
    final form = FormData.fromMap({
      ...?_clean(fields),
      field: MultipartFile.fromBytes(bytes, filename: filename),
    });
    return _send(() => _dio.post<dynamic>(path, data: form));
  }

  /// Téléchargement brut (photo, document).
  Future<Uint8List> download(String path, {Map<String, dynamic>? query}) async {
    try {
      final response = await _dio.get<List<int>>(
        path,
        queryParameters: _clean(query),
        options: Options(responseType: ResponseType.bytes),
      );
      return Uint8List.fromList(response.data ?? const []);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// URL absolue d'un chemin de l'API (ex. pour `Image.network`).
  String url(String path) => '$serverUrl$kApiPrefix$path';

  /// En-têtes d'authentification (ex. pour `Image.network(headers: ...)`).
  Map<String, String> get authHeaders {
    final token = _tokens.accessToken;
    return token == null ? const {} : {'Authorization': 'Bearer $token'};
  }

  /// URL du WebSocket temps réel.
  Uri websocketUri() {
    final base = Uri.parse(serverUrl);
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '$kApiPrefix/ws',
      queryParameters: {'token': _tokens.accessToken ?? ''},
    );
  }

  /// Santé du serveur (hors `/api/v1`).
  Future<Map<String, dynamic>> health() async {
    try {
      final response = await _refreshDio.get<dynamic>('$serverUrl/ready');
      return asJsonMap(response.data);
    } on DioException catch (error) {
      final data = error.response?.data;
      if (data is Map) return data.cast<String, dynamic>();
      throw ApiException.fromDio(error);
    }
  }

  // ---------------------------------------------------------------------------
  // Authentification (utilisé par AuthController)
  // ---------------------------------------------------------------------------

  /// Renouvelle les tokens. Renvoie false si la session ne peut pas être prolongée.
  Future<bool> refreshTokens() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<bool> _doRefresh() async {
    final refreshToken = _tokens.refreshToken;
    if (refreshToken == null) return false;
    try {
      final response = await _refreshDio.post<dynamic>(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );
      final data = asJsonMap(_unwrap(response));
      await _tokens.save(
        accessToken: data['access_token'] as String,
        refreshToken: data['refresh_token'] as String,
      );
      return true;
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      // Erreur réseau : on garde la session (l'utilisateur est peut-être hors ligne).
      if (status == null) throw ApiException.fromDio(error);
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Interne
  // ---------------------------------------------------------------------------

  static const _publicPaths = {'/auth/login', '/auth/register', '/auth/refresh'};

  void _onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = _tokens.accessToken;
    if (token != null && !_publicPaths.contains(options.path)) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  Future<void> _onError(DioException error, ErrorInterceptorHandler handler) async {
    final request = error.requestOptions;
    final unauthorized = error.response?.statusCode == 401;
    if (!unauthorized || _publicPaths.contains(request.path) || request.extra['retried'] == true) {
      return handler.next(error);
    }
    bool refreshed;
    try {
      refreshed = await refreshTokens();
    } catch (_) {
      return handler.next(error);
    }
    if (!refreshed) {
      await _tokens.clear();
      _onSessionExpired();
      return handler.next(error);
    }
    try {
      request.extra['retried'] = true;
      request.headers['Authorization'] = 'Bearer ${_tokens.accessToken}';
      final response = await _dio.fetch<dynamic>(request);
      return handler.resolve(response);
    } on DioException catch (retryError) {
      return handler.next(retryError);
    }
  }

  Future<dynamic> _send(Future<Response<dynamic>> Function() request) async {
    try {
      return _unwrap(await request());
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  static dynamic _unwrap(Response<dynamic> response) {
    final data = response.data;
    if (data is Map && data.containsKey('success')) return data['data'];
    return data;
  }

  /// Retire les valeurs nulles / vides et convertit dates et énumérations.
  static Map<String, dynamic>? _clean(Map<String, dynamic>? values) {
    if (values == null) return null;
    final result = <String, dynamic>{};
    values.forEach((key, value) {
      if (value == null) return;
      if (value is String && value.trim().isEmpty) return;
      if (value is Iterable && value.isEmpty) return;
      if (value is DateTime) {
        result[key] = value.toUtc().toIso8601String();
      } else if (value is Enum) {
        result[key] = value.name;
      } else {
        result[key] = value;
      }
    });
    return result;
  }
}

/// Convertit une valeur JSON en `Map<String, dynamic>`.
JsonMap asJsonMap(Object? value) =>
    value is Map ? value.cast<String, dynamic>() : <String, dynamic>{};

/// Convertit une valeur JSON en liste de `Map<String, dynamic>`.
List<JsonMap> asJsonList(Object? value) =>
    value is List ? value.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() : [];

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    serverUrl: ref.watch(serverUrlProvider),
    tokens: ref.watch(tokenStorageProvider),
    // Lu au moment de l'appel : pas de dépendance circulaire entre providers.
    onSessionExpired: () => ref.read(authControllerProvider.notifier).onSessionExpired(),
  );
});
