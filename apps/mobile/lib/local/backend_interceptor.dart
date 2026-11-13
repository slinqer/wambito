import 'package:dio/dio.dart';

import 'backend.dart';

/// Answers the `/v1` finance routes from a [LocalBackend] instead of the server, for an account
/// whose records live in the vault. Everything else (auth, `/v2/*`, `GET` and `DELETE` of
/// `/v1/me`, routes the backend does not serve) goes on to the network adapter.
class LocalBackendInterceptor extends Interceptor {
  LocalBackendInterceptor(this.backend, {this.afterWrite});

  final LocalBackend backend;

  /// Called after a local 2xx POST, PATCH, PUT or DELETE, e.g. to start a sync.
  final void Function()? afterWrite;

  static const _writes = {'POST', 'PATCH', 'PUT', 'DELETE'};

  /// The account itself comes from the server (the profile and its `encryption`), and deleting it
  /// is the server's.
  static bool _network(String method, String path) =>
      path == '/v1/me' && (method == 'GET' || method == 'DELETE');

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final uri = options.uri;
    // The base URL ends in `/api` (maybe under a sub-path): the backend's paths start at `/v1`.
    final at = uri.path.indexOf('/v1/');
    final method = options.method.toUpperCase();
    if (at < 0) return handler.next(options);
    final path = uri.path.substring(at);
    if (_network(method, path)) return handler.next(options);
    LocalResponse? answer;
    try {
      answer = await backend.handle(
        method,
        path,
        {for (final e in uri.queryParametersAll.entries) e.key: e.value},
        options.data,
        headers: {
          for (final h in options.headers.entries)
            if (h.value != null) h.key: '${h.value}',
        },
      );
    } on Object catch (error, stack) {
      return handler.reject(DioException(requestOptions: options, error: error, stackTrace: stack));
    }
    if (answer == null) return handler.next(options);
    final response = Response<Object?>(
      requestOptions: options,
      statusCode: answer.status,
      data: answer.body,
      headers: Headers.fromMap({
        if (answer.body != null)
          Headers.contentTypeHeader: [
            answer.status >= 400 ? 'application/problem+json' : 'application/json',
          ],
      }),
    );
    if (answer.status >= 400) {
      return handler.reject(
        DioException.badResponse(
          statusCode: answer.status,
          requestOptions: options,
          response: response,
        ),
      );
    }
    if (_writes.contains(method)) afterWrite?.call();
    handler.resolve(response);
  }
}
