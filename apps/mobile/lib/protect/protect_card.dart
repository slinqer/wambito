// Home's "Protect your data" nudge (phone-first spec 5.2): for a `preview` guest with neither way
// back done, first after 7 days or 20 movements, then 14 days after the first "Not now", 30 after
// the second and every 30 after that. It is kept per account on this phone (`home.protect.<user id>`,
// JSON); the first evaluation writes `firstOpen`. Step 1 is the recovery key, as in Settings.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../crypto/records.dart' show RecordType;
import '../home/home_controller.dart' show clockProvider;
import '../home/wambi_face.dart';
import '../l10n/app_localizations.dart';
import '../storage/secure_storage.dart';
import '../theme/surfaces.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../ui/lk_theme.dart';
import '../ui/press_button.dart';
import '../vault/vault_providers.dart' show vaultSessionProvider;
import 'protect_actions.dart';
import 'protect_status.dart';

/// What the card remembers about one account.
class ProtectCardState {
  const ProtectCardState({required this.firstOpen, this.lastDismissed, this.dismissals = 0});

  final DateTime firstOpen;
  final DateTime? lastDismissed;
  final int dismissals;

  Map<String, Object?> toJson() => {
    'firstOpen': firstOpen.toUtc().toIso8601String(),
    'lastDismissed': lastDismissed?.toUtc().toIso8601String(),
    'dismissals': dismissals,
  };

  /// Null when [json] is not a state this app wrote.
  static ProtectCardState? fromJson(Object? json) {
    if (json is! Map) return null;
    final first = DateTime.tryParse('${json['firstOpen']}');
    if (first == null) return null;
    final last = json['lastDismissed'];
    final count = json['dismissals'];
    return ProtectCardState(
      firstOpen: first,
      lastDismissed: last is String ? DateTime.tryParse(last) : null,
      dismissals: count is int ? count : 0,
    );
  }
}

/// How many movements make the card due before its first week is out.
const protectCardMovements = 20;

/// Whether the card is due: none dismissed yet, 7 days since the first open or [movements] of 20;
/// one dismissal, 14 days since it; two or more, 30 days since the last.
bool protectCardDue(ProtectCardState state, {required int movements, required DateTime now}) {
  // A clock that moved back (or a stored time from a jump forward) counts as now: the wait restarts
  // from the present instead of waiting out a date in the future.
  DateTime upToNow(DateTime t) => t.isAfter(now) ? now : t;
  if (state.dismissals <= 0) {
    return now.difference(upToNow(state.firstOpen)) >= const Duration(days: 7) ||
        movements >= protectCardMovements;
  }
  final last = upToNow(state.lastDismissed ?? state.firstOpen);
  final wait = Duration(days: state.dismissals == 1 ? 14 : 30);
  return now.difference(last) >= wait;
}

/// Where a card's state is kept: `flutter_secure_storage` in the app, memory in tests.
abstract interface class ProtectCardStore {
  Future<ProtectCardState?> read(String userId);
  Future<void> write(String userId, ProtectCardState state);
}

class SecureProtectCardStore implements ProtectCardStore {
  const SecureProtectCardStore([this._storage = appSecureStorage]);

  final FlutterSecureStorage _storage;

  static String _key(String userId) => 'home.protect.$userId';

  @override
  Future<ProtectCardState?> read(String userId) async {
    final raw = await _storage.read(key: _key(userId));
    if (raw == null) return null;
    try {
      return ProtectCardState.fromJson(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> write(String userId, ProtectCardState state) =>
      _storage.write(key: _key(userId), value: jsonEncode(state.toJson()));
}

final protectCardStoreProvider = Provider<ProtectCardStore>(
  (ref) => const SecureProtectCardStore(),
);

/// Whether the card shows: the account is an unprotected `preview` guest ([protectStatusProvider])
/// and the schedule says it is due. False while unknown (nothing flashes) or when the vault or the
/// store cannot be read.
class ProtectCardController extends AsyncNotifier<bool> {
  String? _userId;
  ProtectCardState? _state;

  @override
  Future<bool> build() async {
    final status = await ref.watch(protectStatusProvider.future);
    if (status == null || status.protected) return false;
    final session = ref.watch(vaultSessionProvider);
    if (session == null) return false;
    ref.onDispose(session.subscribe(ref.invalidateSelf));
    final store = ref.read(protectCardStoreProvider);
    final now = ref.read(clockProvider)();
    final userId = session.userId;
    var state = await store.read(userId);
    if (state == null) {
      state = ProtectCardState(firstOpen: now);
      try {
        await store.write(userId, state);
      } on Object {
        // Not kept: the week starts again at the next start.
      }
    }
    _userId = userId;
    _state = state;
    // Movements only matter before the first dismissal and before a week is out: skip the listing
    // (it runs on every vault commit) once the answer does not depend on it.
    var due = protectCardDue(state, movements: 0, now: now);
    if (!due && state.dismissals <= 0) {
      final movements = (await session.store.list(RecordType.transaction)).length;
      due = protectCardDue(state, movements: movements, now: now);
    }
    return due;
  }

  /// "Not now": gone until the next wait is out, and kept.
  Future<void> dismiss() async {
    final userId = _userId;
    final before = _state;
    if (userId == null || before == null) return;
    final next = ProtectCardState(
      firstOpen: before.firstOpen,
      lastDismissed: ref.read(clockProvider)(),
      dismissals: before.dismissals + 1,
    );
    _state = next;
    // Kept first: a rebuild triggered by a commit meanwhile reads the dismissal, not the old state.
    try {
      await ref.read(protectCardStoreProvider).write(userId, next);
    } on Object {
      // Not kept: the card is back at the next start.
    }
    if (ref.mounted) state = const AsyncData(false);
  }
}

final protectCardProvider = AsyncNotifierProvider.autoDispose<ProtectCardController, bool>(
  ProtectCardController.new,
);

/// The card on home: Wambi, what the key is for, "Make my key" and "Not now".
class ProtectCard extends ConsumerStatefulWidget {
  const ProtectCard({super.key});

  @override
  ConsumerState<ProtectCard> createState() => _ProtectCardState();
}

class _ProtectCardState extends ConsumerState<ProtectCard> {
  var _busy = false;

  Future<void> _go() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await protectWithRecoveryKey(context, ref);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceRow,
          borderRadius: LkSurface.radius(LkRadius.lg),
          border: Border.all(color: colors.brand, width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(WambitoTokens.space3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: WambitoTokens.space2,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: WambitoTokens.space3,
                children: [
                  const WambiFace(mood: WambiMood.happy, size: 56, decorative: true),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: WambitoTokens.space1,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            l10n.protectCardTitle,
                            style: LkText.cardTitle.copyWith(color: colors.ink),
                          ),
                        ),
                        Text(
                          l10n.protectCardBody,
                          style: LkText.cardLead.copyWith(color: colors.inkMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // As the other home cards: the way in first, "Not now" at the end.
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                spacing: WambitoTokens.space2,
                children: [
                  Flexible(
                    child: PressButton.text(
                      l10n.protectCardGo,
                      key: const Key('protect.cardGo'),
                      size: PressSize.sm,
                      onPressed: _busy ? null : () => unawaited(_go()),
                    ),
                  ),
                  PressButton.text(
                    l10n.protectCardLater,
                    key: const Key('protect.cardLater'),
                    tone: PressTone.ghost,
                    size: PressSize.sm,
                    onPressed: _busy
                        ? null
                        : () => unawaited(ref.read(protectCardProvider.notifier).dismiss()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
