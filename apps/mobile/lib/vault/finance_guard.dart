import 'package:dio/dio.dart';

/// What a [FinanceGuard] does with a finance call.
enum FinanceVerdict {
  /// The account is `plain`: the call goes on.
  plain,

  /// The account is `preview` and its vault is not open: 423 `vault_locked`.
  locked,

  /// The mode could not be learned: refused as an offline request fails.
  unknown,
}

/// Holds the `/v1` finance calls of a session whose account is not known to be `plain` (a
/// `preview` account, or one whose mode is still loading or failed): none of them reaches the
/// network, so no finance field ever leaves the phone in clear. The vault's interceptor, in front
/// of it once the vault is open, answers them first; what it passes on stops here too.
///
/// The paths are the API's `FINANCE_PATHS` (apps/api/src/http/preview.ts), which a `preview`
/// account is refused anyway (403 `encrypted_account`). `GET /v1/me`, `/auth` and `/v2` go on.
///
/// While the mode is loading, a call waits for it ([verdict]): `plain` lets it go on; a known
/// `preview` account (its vault not open) is refused with a 423 `vault_locked` problem, so the
/// screens show an error; a mode that could not be learned (no network, a 5xx, another session by
/// then) is refused exactly as an offline request fails, a `connectionError` without a response, so
/// the screens take their offline path (a plain account's home cache on an offline first start).
class FinanceGuard extends Interceptor {
  FinanceGuard(this.verdict);

  /// What the session's account allows, once known.
  final Future<FinanceVerdict> Function() verdict;

  static final List<RegExp> financePaths = [
    RegExp(r'^/v1/transactions(/|$)'),
    RegExp(r'^/v1/categories(/|$)'),
    RegExp(r'^/v1/recurrences(/|$)'),
    RegExp(r'^/v1/summary$'),
    RegExp(r'^/v1/reports/'),
    RegExp(r'^/v1/captures(/|$)'),
    RegExp(r'^/v1/imports(/|$)'),
    RegExp(r'^/v1/me/export$'),
  ];

  /// The path after the client's base (`<server>/api`), as the API matches it.
  static String _path(RequestOptions options) {
    final base = Uri.parse(options.baseUrl).path.replaceFirst(RegExp(r'/+$'), '');
    final path = options.uri.path;
    return path.startsWith(base) ? path.substring(base.length) : path;
  }

  static bool isFinance(RequestOptions options) {
    final path = _path(options);
    return financePaths.any((p) => p.hasMatch(path));
  }

  /// The refusal: a 423 problem with the code `vault_locked`.
  static DioException locked(RequestOptions options) => DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    message: 'vault_locked',
    response: Response<Object?>(
      requestOptions: options,
      statusCode: 423,
      statusMessage: 'Locked',
      headers: Headers.fromMap({
        Headers.contentTypeHeader: ['application/problem+json'],
      }),
      data: <String, Object?>{
        'type': 'about:blank',
        'title': 'Locked',
        'status': 423,
        'code': 'vault_locked',
        'detail': 'This account keeps its finances in the vault on this phone, which is not open.',
      },
    ),
  );

  /// The refusal of an unknown mode: what Dio gives a request without network.
  static DioException unknown(RequestOptions options) =>
      DioException.connectionError(requestOptions: options, reason: 'vault_mode_unknown');

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (!isFinance(options)) return handler.next(options);
    FinanceVerdict outcome;
    try {
      outcome = await verdict();
    } on Object {
      outcome = FinanceVerdict.unknown;
    }
    switch (outcome) {
      case FinanceVerdict.plain:
        handler.next(options);
      case FinanceVerdict.locked:
        handler.reject(locked(options));
      case FinanceVerdict.unknown:
        handler.reject(unknown(options));
    }
  }
}
