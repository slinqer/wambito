import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/session.dart';
import '../capture_auto/capture_platform.dart';
import '../feedback/stored_flag.dart';
import '../settings/assistants_repository.dart';
import 'home_repository.dart';

/// The cards home's carousel offers, in order: what matters most after installing. Turning on
/// automatic capture (no typing expenses), bringing a history, connecting an AI assistant.
enum Nudge {
  capture('capture'),
  import('import'),
  agents('agents');

  const Nudge(this.id);
  final String id;
}

/// Whether a person put a nudge away ("Ahora no"), for good, on this phone (the web's
/// `useDismissed`, kept per person and per device). Null until it has been read, so a card that
/// was put away never shows for a moment at the start; unreadable counts as not put away.
class NudgeDismissed extends Notifier<bool?> {
  NudgeDismissed(this.key);

  /// `home.dismissed.<user id>.<nudge id>`.
  final String key;

  var _chosen = false;

  FlagStore get _store => ref.read(flagStoreProvider(key));

  @override
  bool? build() {
    unawaited(_read());
    return null;
  }

  Future<void> _read() async {
    bool? kept;
    try {
      kept = await _store.read();
    } on Object {
      // Unreadable: not put away.
    }
    if (!_chosen && ref.mounted) state = kept ?? false;
  }

  /// Puts the card away, and keeps that.
  Future<void> dismiss() async {
    _chosen = true;
    state = true;
    try {
      await _store.write(true);
    } on Object {
      // Not kept: the card is back at the next start.
    }
  }
}

final nudgeDismissedProvider = NotifierProvider.family<NudgeDismissed, bool?, String>(
  NudgeDismissed.new,
);

/// The key of [nudge] for the person [userId].
String nudgeKey(String userId, Nudge nudge) => 'home.dismissed.$userId.${nudge.id}';

/// Whether the account has any transaction, in any month (the web's `useHasTransactions`): the
/// import card is for an account with none. Null while it is asked, and when it could not be (the
/// card waits for an answer rather than guess).
final hasTransactionsProvider = FutureProvider.autoDispose<bool?>((ref) async {
  try {
    return await ref.watch(homeRepositoryProvider).hasTransactions();
  } on Object {
    return null;
  }
});

/// Whether automatic capture still waits to be set up on this phone: on Android until a source is on
/// and the notifications can be read, on the iPhone until Apple Pay sent a payment through Shortcuts.
/// False on a phone with no capture, while it is asked, and when it could not be.
final captureNudgeProvider = FutureProvider.autoDispose<bool>((ref) async {
  try {
    final status = await ref.watch(autoCapturePlatformProvider).status();
    if (status == null) return false;
    final done = status.iosMajor != null ? status.configured : status.anyOn && status.access;
    return !done;
  } on Object {
    return false;
  }
});

/// Whether no AI assistant is connected yet: always for a guest (one needs an email first, which
/// Mis agentes offers), otherwise while the server lists none. False while it is asked and when it
/// could not be, so the card never shows for an account that has one.
final agentsNudgeProvider = FutureProvider.autoDispose<bool>((ref) async {
  // Only with a session read: home shown on its own, as tests do, has no account to ask about.
  if (!ref.exists(sessionProvider)) return false;
  if (ref.watch(sessionProvider.select((s) => s.isGuest))) return true;
  try {
    return (await ref.watch(assistantsRepositoryProvider).list()).isEmpty;
  } on Object {
    return false;
  }
});
