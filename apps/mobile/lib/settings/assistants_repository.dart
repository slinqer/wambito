// What "Conecta tu asistente" asks of the server (spec §6.2): the assistants the person let in
// through the MCP's OAuth (`GET /v1/me/assistants`), and revoking one
// (`DELETE /v1/me/assistants/{clientId}`). Connecting happens in the assistant and on the web's
// consent screen; the app only reads and revokes. An encrypted (`preview`) account's calls go to the
// server too (the vault does not serve them) and name the account they mean (`x-wambito-user`), so
// a session that changed hands gets 409 `session_changed` rather than another account's assistant
// revoked.
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/gen/wambito_api.dart';
import '../api/session.dart';
import '../home/home_repository.dart';
import '../vault/encryption_mode.dart';

/// The MCP's address for the server the app talks to: `<server>/mcp`, the same origin as the web
/// (Caddy sends `/mcp` to the MCP service). A path on [server] is kept, as the API client keeps it;
/// a query or fragment is dropped. It is the same for everyone: OAuth tells who is asking.
Uri mcpUrl(Uri server) {
  final path = server.path.replaceFirst(RegExp(r'/+$'), '');
  return Uri(
    scheme: server.scheme,
    userInfo: server.userInfo.isEmpty ? null : server.userInfo,
    host: server.host,
    port: server.hasPort ? server.port : null,
    path: '$path/mcp',
  );
}

/// One connected assistant, as the list shows it.
class ConnectedAssistant {
  const ConnectedAssistant({
    required this.clientId,
    required this.name,
    this.domain,
    required this.connectedAt,
    this.lastUsedAt,
  });

  /// What the server knows it by, and what revoking names.
  final String clientId;
  final String name;

  /// The host it comes from (its client_id's, else its website's): what tells a real Claude from a
  /// copy. Null when the server could not tell.
  final String? domain;
  final DateTime connectedAt;

  /// When it last got a token; null when it never used the connection.
  final DateTime? lastUsedAt;
}

/// The assistants' endpoints. Every failure is a [HomeFailure].
abstract interface class AssistantsRepository {
  /// The connected assistants, newest first.
  Future<List<ConnectedAssistant>> list();

  /// Revokes one: it loses access within 15 minutes at most. One the server no longer knows (404:
  /// revoked meanwhile, from the web or another phone) counts as revoked.
  Future<void> revoke(String clientId);
}

/// [AssistantsRepository] over the generated client.
class ApiAssistantsRepository implements AssistantsRepository {
  ApiAssistantsRepository(this._api, {this.userId});

  final DefaultApi _api;

  /// The encrypted account the calls mean (`x-wambito-user`); null for a `plain` account.
  final String? userId;

  Map<String, dynamic>? get _headers => switch (userId) {
    final id? => {'x-wambito-user': id},
    null => null,
  };

  @override
  Future<List<ConnectedAssistant>> list() async {
    final AssistantList? data;
    try {
      data = (await _api.listAssistants(headers: _headers)).data;
    } on DioException catch (error) {
      throw HomeFailure.fromDio(error);
    }
    if (data == null) throw const HomeFailure(500);
    return [
      for (final item in data.items)
        ConnectedAssistant(
          clientId: item.clientId,
          name: item.name,
          domain: item.domain,
          connectedAt: DateTime.parse(item.connectedAt),
          lastUsedAt: switch (item.lastUsedAt) {
            final at? => DateTime.parse(at),
            null => null,
          },
        ),
    ];
  }

  @override
  Future<void> revoke(String clientId) async {
    try {
      // The generated client puts the id in the path as it is, and a Client ID Metadata Document's
      // id is a URL: encoded, its slashes stay one segment (the API decodes it).
      await _api.revokeAssistant(clientId: Uri.encodeComponent(clientId), headers: _headers);
    } on DioException catch (error) {
      final failure = HomeFailure.fromDio(error);
      if (failure.status == 404) return;
      throw failure;
    }
  }
}

/// The assistants' endpoints for the signed-in session (rebuilt when the token changes), naming
/// the account when it is `preview`.
final assistantsRepositoryProvider = Provider<AssistantsRepository>((ref) {
  final account = ref.watch(currentVaultAccountProvider);
  return ApiAssistantsRepository(
    ref.watch(apiClientProvider).api.getDefaultApi(),
    userId: account?.mode == EncryptionMode.preview ? account?.profile.id : null,
  );
});
