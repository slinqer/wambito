// Settings' server card: whether the server the app talks to answers, and which version it runs
// (the API's `GET /health`). Asked when Settings opens and every [serverHealthEvery] while it stays
// open; a green dot that blinks while the server answers, a red one when it does not.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/client.dart';
import '../api/server_url.dart';
import '../l10n/app_localizations.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../ui/lk_theme.dart';

/// What the server said: [online] when `/health` answered `status: ok`, with the [version] its
/// build reports (none from a server that names none).
class ServerHealth {
  const ServerHealth({required this.online, this.version});

  const ServerHealth.offline() : online = false, version = null;

  final bool online;
  final String? version;
}

typedef ServerHealthCheck = Future<ServerHealth> Function(Uri server);

/// Asks [server]'s `/health`, with no session: any failure (no answer, an error, another body)
/// is [ServerHealth.offline].
Future<ServerHealth> checkServerHealth(Uri server) async {
  final dio = ApiClient.forServer(server).dio;
  dio.options
    ..connectTimeout = const Duration(seconds: 5)
    ..receiveTimeout = const Duration(seconds: 5);
  try {
    final body = (await dio.get<Object?>('/health')).data;
    if (body is! Map || body['status'] != 'ok') return const ServerHealth.offline();
    final version = body['version'];
    return ServerHealth(
      online: true,
      version: version is String && version.isNotEmpty ? version : null,
    );
  } on Object {
    return const ServerHealth.offline();
  } finally {
    dio.close();
  }
}

/// How the server is asked (tests answer for it).
final serverHealthCheckProvider = Provider<ServerHealthCheck>((ref) => checkServerHealth);

/// Whether the green dot blinks: always, except in tests that settle the frames.
final serverDotPulsesProvider = Provider<bool>((ref) => true);

/// How often Settings asks again while it is open.
const serverHealthEvery = Duration(seconds: 30);

/// The dot and the line beside it: Comprobando… (grey), En línea · Versión … (green, blinking)
/// or No responde (red). The line is a live region, so a change is read out once.
class ServerStatus extends ConsumerStatefulWidget {
  const ServerStatus({super.key, this.compact = false});

  /// The row's value in Más: "Conectado" for a server that answers (its version stays in what a
  /// screen reader hears), on one line with an ellipsis.
  final bool compact;

  @override
  ConsumerState<ServerStatus> createState() => _ServerStatusState();
}

class _ServerStatusState extends ConsumerState<ServerStatus> {
  ServerHealth? _health;
  Timer? _every;
  late Uri _server;

  @override
  void initState() {
    super.initState();
    _server = ref.read(serverUrlProvider);
    ref.listenManual(serverUrlProvider, (_, next) {
      _server = next;
      setState(() => _health = null);
      unawaited(_check());
    });
    unawaited(_check());
    _every = Timer.periodic(serverHealthEvery, (_) => unawaited(_check()));
  }

  Future<void> _check() async {
    final asked = _server;
    final health = await ref.read(serverHealthCheckProvider)(asked);
    // An answer from a server the app has since left is not this one's.
    if (!mounted || asked != _server) return;
    setState(() => _health = health);
  }

  @override
  void dispose() {
    _every?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    final health = _health;
    final version = health?.version;
    final (color, full) = switch (health) {
      null => (colors.inkMuted, l10n.settingsServerChecking),
      ServerHealth(online: true) => (
        colors.good,
        version == null
            ? l10n.settingsServerOnline
            : '${l10n.settingsServerOnline} · ${l10n.settingsServerVersion(version)}',
      ),
      _ => (colors.over, l10n.settingsServerOffline),
    };
    final label = widget.compact && health?.online == true ? l10n.settingsServerConnected : full;
    final pulses =
        health?.online == true &&
        ref.watch(serverDotPulsesProvider) &&
        !MediaQuery.disableAnimationsOf(context);
    return Row(
      key: const Key('settings.server.status'),
      spacing: WambitoTokens.space2,
      children: [
        ExcludeSemantics(
          child: _Dot(color: color, pulses: pulses),
        ),
        Flexible(
          child: Semantics(
            liveRegion: true,
            label: widget.compact ? full : null,
            child: ExcludeSemantics(
              excluding: widget.compact,
              child: Text(
                label,
                maxLines: widget.compact ? 1 : null,
                overflow: widget.compact ? TextOverflow.ellipsis : null,
                style: LkText.bodySm.copyWith(color: colors.ink),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A 10px dot in [color]; while [pulses] it fades to faint and back, over and over.
class _Dot extends StatefulWidget {
  const _Dot({required this.color, required this.pulses});

  final Color color;
  final bool pulses;

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..value = 1;

  @override
  void initState() {
    super.initState();
    _follow();
  }

  @override
  void didUpdateWidget(_Dot old) {
    super.didUpdateWidget(old);
    if (old.pulses != widget.pulses) _follow();
  }

  void _follow() {
    if (widget.pulses) {
      unawaited(_blink.repeat(reverse: true, min: 0.3, max: 1));
    } else {
      _blink
        ..stop()
        ..value = 1;
    }
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _blink,
      child: SizedBox.square(
        dimension: 10,
        child: DecoratedBox(
          key: const Key('settings.server.dot'),
          decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
