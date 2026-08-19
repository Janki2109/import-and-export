import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/app_constants.dart';
import 'device_identity.dart';

/// Thrown on any non-2xx response, carries the backend's error message so screens
/// can show it directly (backend already returns {"success": false, "error": "..."}).
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  /// Set by AuthProvider so ApiClient can force a logout when a refresh attempt fails
  /// (refresh token itself expired/revoked) — avoids a circular import between the two.
  static void Function()? onSessionExpired;

  late final Dio dio;
  final _storage = const FlutterSecureStorage();
  Future<bool>? _refreshInFlight;

  ApiClient._internal() {
    dio = Dio(BaseOptions(
      baseUrl: AppConstants.baseUrl,
      // Render's free-tier backend routinely takes 10-15s+ to respond (and 30-60s on a cold
      // start after idle) — the previous 15s timeout was right at that edge, so slow-but-valid
      // responses were being cut off and surfacing as a generic "Something went wrong" instead
      // of actually completing.
      connectTimeout: const Duration(seconds: 45),
      receiveTimeout: const Duration(seconds: 45),
      headers: {'Content-Type': 'application/json'},
    ));

    if (kDebugMode) debugPrint('[ApiClient] baseUrl = ${AppConstants.baseUrl}');

    if (kDebugMode) {
      dio.interceptors.add(LogInterceptor(
        requestHeader: false,
        responseHeader: false,
        request: true,
        requestBody: false,
        responseBody: true,
        logPrint: (obj) => debugPrint('[Dio] $obj'),
      ));
    }

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.read(key: AppConstants.tokenKey);
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        options.headers['X-Device-Id'] = await DeviceIdentity.get();
        handler.next(options);
      },
      onError: (DioException e, handler) async {
        final isAuthEndpoint = e.requestOptions.path.contains('/auth/');
        final alreadyRetried = e.requestOptions.extra['__retried'] == true;
        if (e.response?.statusCode == 401 && !isAuthEndpoint && !alreadyRetried) {
          final refreshed = await _refreshAccessToken();
          if (refreshed) {
            try {
              e.requestOptions.extra['__retried'] = true;
              final retryResponse = await _retry(e.requestOptions);
              handler.resolve(retryResponse);
              return;
            } catch (_) {
              // fall through to normal error handling below
            }
          } else {
            onSessionExpired?.call();
          }
        } else if (e.response?.statusCode == 401 && alreadyRetried) {
          onSessionExpired?.call();
        }

        if (kDebugMode) {
          debugPrint('[ApiClient] ${e.requestOptions.method} ${e.requestOptions.uri} failed: '
              '${e.type} — ${e.error ?? e.message}');
          final st = e.stackTrace;
          debugPrint('[ApiClient] stack trace:\n$st');
        }

        handler.reject(DioException(
          requestOptions: e.requestOptions,
          error: ApiException(_describeError(e), statusCode: e.response?.statusCode),
          response: e.response,
          type: e.type,
        ));
      },
    ));
  }

  /// Turns a raw DioException into a specific, actionable message instead of one generic
  /// "cannot reach server" string — so the real cause (server down vs. timeout vs. DNS vs.
  /// a genuine 404/500) is visible to both the user and (in debug logs) the developer.
  String _describeError(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['error'] != null) {
      return data['error'].toString();
    }

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return 'Connection timed out while reaching the server. Check your network and try again.';
      case DioExceptionType.sendTimeout:
        return 'Timed out sending the request. Check your network and try again.';
      case DioExceptionType.receiveTimeout:
        return 'Server took too long to respond. Please try again.';
      case DioExceptionType.transformTimeout:
        return 'Timed out processing the server response. Please try again.';
      case DioExceptionType.badCertificate:
        return 'Could not verify the server\'s security certificate.';
      case DioExceptionType.connectionError:
        final inner = e.error;
        if (inner is SocketException) {
          if (inner.osError?.errorCode == 111 || inner.message.toLowerCase().contains('refused')) {
            return 'Connection refused — the server isn\'t running or isn\'t listening on this address.';
          }
          if (inner.message.toLowerCase().contains('failed host lookup') ||
              inner.message.toLowerCase().contains('nodename nor servname')) {
            return 'Could not resolve the server address (DNS failure). Check the configured server address.';
          }
          if (inner.message.toLowerCase().contains('network is unreachable')) {
            return 'No internet connection available on this device.';
          }
        }
        return 'Cannot reach the server. Check that it is running and reachable on the network.';
      case DioExceptionType.badResponse:
        final status = e.response?.statusCode;
        if (status == 404) return 'The requested resource was not found (404).';
        if (status != null && status >= 500) return 'Server error ($status). Please try again later.';
        if (status == 401) return 'Authentication failed. Please log in again.';
        return 'Unexpected server response${status != null ? ' ($status)' : ''}.';
      case DioExceptionType.cancel:
        return 'Request was cancelled.';
      case DioExceptionType.unknown:
        return 'Something went wrong. Please try again.';
    }
  }

  /// Ensures only one refresh call is in flight even if several requests 401 at once.
  Future<bool> _refreshAccessToken() {
    return _refreshInFlight ??= _doRefresh().whenComplete(() => _refreshInFlight = null);
  }

  Future<bool> _doRefresh() async {
    final refreshToken = await _storage.read(key: AppConstants.refreshTokenKey);
    if (refreshToken == null) return false;

    try {
      final res = await Dio(BaseOptions(baseUrl: AppConstants.baseUrl)).post(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );
      final data = res.data['data'];
      await _storage.write(key: AppConstants.tokenKey, value: data['access_token']);
      await _storage.write(key: AppConstants.refreshTokenKey, value: data['refresh_token']);
      return true;
    } catch (_) {
      await _storage.delete(key: AppConstants.tokenKey);
      await _storage.delete(key: AppConstants.refreshTokenKey);
      return false;
    }
  }

  Future<Response> _retry(RequestOptions requestOptions) async {
    final token = await _storage.read(key: AppConstants.tokenKey);
    final headers = {...requestOptions.headers};
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    } else {
      headers.remove('Authorization');
    }
    final options = Options(method: requestOptions.method, headers: headers);
    // BUG FIX (M-10): requestOptions.data for a FormData/multipart body (file uploads) is a
    // single-use stream — it was already consumed by the original request that got the 401, so
    // replaying it as-is here sent an empty/broken body. Any upload that happened to hit a 401
    // and trigger this refresh-and-retry path failed on the replay. FormData.clone() produces a
    // fresh, unconsumed copy; every other request type is unaffected.
    final data = requestOptions.data is FormData ? (requestOptions.data as FormData).clone() : requestOptions.data;
    return dio.request(
      requestOptions.path,
      data: data,
      queryParameters: requestOptions.queryParameters,
      options: options,
    );
  }

  Future<Response> get(String path, {Map<String, dynamic>? query}) =>
      dio.get(path, queryParameters: query).catchError(_rethrow);

  Future<Response> post(String path, {dynamic data}) =>
      dio.post(path, data: data).catchError(_rethrow);

  Future<Response> put(String path, {dynamic data}) =>
      dio.put(path, data: data).catchError(_rethrow);

  Future<Response> delete(String path, {dynamic data}) =>
      dio.delete(path, data: data).catchError(_rethrow);

  Never _rethrow(Object e) {
    if (e is DioException && e.error is ApiException) {
      throw e.error as ApiException;
    }
    throw ApiException(e.toString());
  }
}
