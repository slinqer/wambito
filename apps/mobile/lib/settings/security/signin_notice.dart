// The sign-in notice (phone-first spec 8.3, rulings 16 and the founder's answer 3): the next time the
// phone opens with its vault Ready, it says "A session was opened on {label}" for every device
// wrap that is not this phone's and was not in its last look, with "That wasn't me" (the device's
// removal, whose done step suggests changing the keys) and "OK". Any new device counts, a browser signed in from the web as much as a phone added by
// pairing, and the phone that approved it too (ruling 16's cost: the person may have just done it).
// The last look is the list of device wrap ids, kept per account in `wambito.vault.<userId>.seenDevices`
// (it goes with the account's other vault keys when the phone signs out); the first look records
// silently, and a `plain` account (no vault, so no `/v2/keys`) never looks.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../l10n/app_localizations.dart';
import '../../local/keys.dart' show WrapDto;
import '../../router.dart' show routerProvider;
import '../../security/screen_lock.dart' show confirmSensitive;
import '../../storage/secure_storage.dart';
import '../../theme/text_styles.dart';
import '../../theme/tokens.g.dart';
import '../../ui/lk_theme.dart';
import '../../ui/press_button.dart';
import '../../ui/sheet.dart';
import '../../vault/vault_providers.dart' show vaultSessionProvider;
import 'remove_device_sheet.dart';
import 'security_api.dart';
import 'security_model.dart';

/// The device wraps that are not this phone's and not in [seen], in the server's order. [seen] is
/// null on the first look: nothing is new then.
List<WrapDto> newDevices(List<WrapDto> wraps, {required Set<String>? seen, required String ownId}) {
  if (seen == null) return const [];
  return [
    for (final wrap in wraps)
      if (wrap.kind == 'device' && wrap.id != ownId && !seen.contains(wrap.id)) wrap,
  ];
}

/// The device wrap ids the person last looked at, per account.
abstract interface class SeenDevicesStore {
  /// Null when there was no look yet (or it cannot be read: the next look records silently).
  Future<Set<String>?> read(String userId);
  Future<void> keep(String userId, Set<String> ids);
}

/// [SeenDevicesStore] over `flutter_secure_storage`, key `wambito.vault.<userId>.seenDevices`: a
/// JSON list of ids.
class SecureSeenDevicesStore implements SeenDevicesStore {
  const SecureSeenDevicesStore([this._storage = appSecureStorage]);

  final FlutterSecureStorage _storage;

  static final RegExp _userId = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

  static String keyOf(String userId) {
    if (!_userId.hasMatch(userId)) throw ArgumentError.value(userId, 'userId', 'not a user id');
    return 'wambito.vault.$userId.seenDevices';
  }

  @override
  Future<Set<String>?> read(String userId) async {
    final text = await _storage.read(key: keyOf(userId));
    if (text == null) return null;
    try {
      final list = jsonDecode(text);
      if (list is! List) return null;
      return {
        for (final id in list)
          if (id is String) id,
      };
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> keep(String userId, Set<String> ids) =>
      _storage.write(key: keyOf(userId), value: jsonEncode(ids.toList()..sort()));
}

final seenDevicesStoreProvider = Provider<SeenDevicesStore>(
  (ref) => const SecureSeenDevicesStore(),
);

/// Looks at the account's devices and, when some are new, says so. Returns once the person answered
/// (or nothing was to be said). A `plain` account, a locked vault or a list that cannot be read
/// says nothing and records nothing.
Future<void> showSigninNotice(BuildContext context, WidgetRef ref) async {
  final security = ref.read(securityApiProvider);
  if (security == null) return;
  final store = ref.read(seenDevicesStoreProvider);
  final SecuritySnapshot snapshot;
  final Set<String>? seen;
  final String userId = security.pairing.userId;
  try {
    snapshot = await security.load();
    seen = await store.read(userId);
  } on Object {
    return;
  }
  final ownId = snapshot.ownId;
  // Without this phone's own wrap there is no telling which one is not it.
  if (ownId == null) return;
  final rows = deviceRows(
    wraps: snapshot.wraps,
    ownId: ownId,
    revoked: snapshot.revoked,
    verified: snapshot.verified,
  );
  final all = {?rows.thisPhone?.id, for (final row in rows.others) row.id};
  final liveIds = all.difference({ownId});
  final fresh = [
    for (final wrap in newDevices(snapshot.wraps, seen: seen, ownId: ownId))
      if (liveIds.contains(wrap.id)) wrap,
  ];
  if (fresh.isEmpty) {
    // The first look, or devices that went: what is there now is what was seen.
    if (seen == null || !seen.containsAll(all) || !all.containsAll(seen)) {
      await _keep(store, userId, all);
    }
    return;
  }
  if (!context.mounted) return;
  final l10n = AppLocalizations.of(context);
  // The newest first: it is the one the title names.
  final newest = [...fresh]..sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));
  final answer = await LkSheet.show<_Answer>(
    context,
    title: l10n.signinNoticeTitle(newest.first.label ?? l10n.settingsSecurityUnnamed),
    children: [_NoticeBody(more: fresh.length - 1)],
  );
  // Seen, whichever way it was answered: "OK" and "That wasn't me" say they looked. Closing the
  // sheet some other way leaves it to be said again.
  if (answer == null) return;
  await _keep(store, userId, all);
  if (answer != _Answer.notMe || !context.mounted) return;
  if (fresh.length > 1) {
    unawaited(ref.read(routerProvider).push<void>('/settings'));
    return;
  }
  final row = rows.others.firstWhere((r) => r.id == fresh.single.id);
  final ok = await confirmSensitive(
    context,
    ref,
    reason: l10n.settingsSecurityLockRemove,
    checkRecoveryKey: security.checkRecoveryKey,
  );
  if (!ok || !context.mounted) return;
  // Someone else may have had this device, and a copy of the data key with it: the done step
  // suggests "Change keys" (the removal alone does not change them).
  await RemoveDeviceSheet.show(
    context,
    device: row,
    security: security,
    hasPasskeys: anyPasskeyWrap(snapshot.wraps),
    suggestChangeKeys: true,
    onChanged: () => ref.invalidate(securitySnapshotProvider),
  );
}

Future<void> _keep(SeenDevicesStore store, String userId, Set<String> ids) async {
  try {
    await store.keep(userId, ids);
  } on Object {
    // Not recorded: it is said again next time, which is the safe side.
  }
}

enum _Answer { ok, notMe }

class _NoticeBody extends StatelessWidget {
  const _NoticeBody({required this.more});

  final int more;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    return Padding(
      padding: const EdgeInsets.only(top: WambitoTokens.space3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: WambitoTokens.space3,
        children: [
          if (more > 0)
            Text(l10n.signinNoticeMore(more), style: LkText.body.copyWith(color: colors.ink)),
          Text(l10n.signinNoticeBody, style: LkText.body.copyWith(color: colors.ink)),
          PressButton.text(
            l10n.signinNoticeNotMe,
            key: const Key('signinNotice.notMe'),
            tone: PressTone.secondary,
            onPressed: () => Navigator.of(context).pop(_Answer.notMe),
          ),
          PressButton.text(
            l10n.signinNoticeOk,
            key: const Key('signinNotice.ok'),
            tone: PressTone.ghost,
            onPressed: () => Navigator.of(context).pop(_Answer.ok),
          ),
        ],
      ),
    );
  }
}

/// How long the notice waits for home to be free, and how often it looks. After the 5 minutes the
/// look is given up; the next resume (or start) asks again.
const _waitForHome = Duration(minutes: 5);
const _lookEvery = Duration(milliseconds: 250);

/// Says the notice at start (once the vault is Ready) and on every resume, over home with nothing
/// above it (app.dart puts it last of the start and resume hooks, after the seen ping).
class SigninNoticeHost extends ConsumerStatefulWidget {
  const SigninNoticeHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SigninNoticeHost> createState() => _SigninNoticeHostState();
}

class _SigninNoticeHostState extends ConsumerState<SigninNoticeHost> with WidgetsBindingObserver {
  var _running = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.listenManual(vaultSessionProvider, (_, next) {
      if (next != null) unawaited(_look());
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A resume while a look is still running (waiting for home, or the sheet open) is dropped: that
    // look is already going to say what there is, and `_look` never overlaps itself.
    if (state == AppLifecycleState.resumed && ref.read(vaultSessionProvider) != null) {
      unawaited(_look());
    }
  }

  Future<void> _look() async {
    if (_running) return;
    _running = true;
    try {
      final context = await _homeContext();
      if (context == null || !context.mounted) return;
      await showSigninNotice(context, ref);
    } on Object {
      // Nothing to say is better than a crash at start.
    } finally {
      _running = false;
    }
  }

  /// The router's navigator while the person is on home with nothing over it (no sheet, no other
  /// screen), waiting a few minutes for that. Null when home never frees up.
  Future<BuildContext?> _homeContext() async {
    final router = ref.read(routerProvider);
    final navigator = router.routerDelegate.navigatorKey;
    bool free() {
      final context = navigator.currentContext;
      // The router has no location yet while the app is still starting: not free, ask again.
      final String path;
      try {
        path = router.state.uri.path;
      } on Object {
        return false;
      }
      return mounted &&
          ref.read(vaultSessionProvider) != null &&
          path == '/' &&
          context != null &&
          context.mounted &&
          !Navigator.of(context).canPop();
    }

    final end = DateTime.now().add(_waitForHome);
    while (mounted && DateTime.now().isBefore(end)) {
      if (free()) {
        await WidgetsBinding.instance.endOfFrame;
        if (free()) return navigator.currentContext;
      }
      await Future<void>.delayed(_lookEvery);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
