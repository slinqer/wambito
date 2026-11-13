import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/session.dart';
import '../feedback/stored_flag.dart';
import '../home/widget_sync.dart';
import '../settings/preferences.dart';
import '../vault/encryption_mode.dart';
import 'notice_backend.dart';
import 'notice_platform.dart';
import 'notice_prompt.dart';

/// Keeps the app's two local notices (spec section 7.2) in step with the person, on the phone:
///
///  * **"Hoy vence…"** is scheduled for 9:00 in the profile's zone only while someone is signed in,
///    its switch is on, they have a recurring payment still running **and** notifications are
///    allowed (a guest included); otherwise it is cancelled, so the phone never wakes up, nor
///    asks the server anything, for a notice that cannot be posted. Offline, with nothing known,
///    the job is left as it is.
///  * **The guest warning** is set 44 days ahead, again at every opening of the app on a guest
///    account **that the server accepted a request from** (that is when its own 60-day clock
///    restarts; an opening offline leaves the job as it was), and cancelled when the account
///    stops being a guest (a claimed email, a sign-out) or its switch goes off.
///  * **The notification permission** (Android 13+) is asked in the app, with one sentence on why,
///    the first time a notice is relevant while the app is open: a recurring payment and the due
///    switch on, or a guest account and the guest switch on. It is asked once, whatever the
///    answer: a refusal only means the notices are not posted.
///
/// Runs one pass at a time; a pass is asked for at the start, whenever the session, a switch or the
/// language changes, and whenever the app comes back to the foreground (that is an opening too).
/// Where there is no Android side ([NoticePermission.unavailable]) it does nothing at all.
class NoticeSync with WidgetsBindingObserver {
  NoticeSync(this._ref);

  final Ref _ref;
  var _queue = Future<void>.value();
  var _asking = Future<void>.value();
  var _askingNow = false;
  NoticeFacts? _facts;

  /// Completes when every pass asked so far is done, and the question to the person, if one was
  /// put (tests wait on it).
  Future<void> get idle async {
    await _queue;
    await _asking;
  }

  /// Asks for a pass.
  void request() {
    _queue = _queue.then((_) async {
      try {
        await _pass();
      } on Object {
        // The notices keep what they had; this never breaks the app.
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) request();
  }

  NoticePlatform get _platform => _ref.read(noticePlatformProvider);

  Future<void> _pass() async {
    final platform = _platform;
    final session = _ref.read(sessionProvider.notifier);
    await session.ready;
    if (_ref.read(sessionProvider).status == SessionStatus.loading) return;
    // Android's answer first: where there is none, there is nothing to schedule or ask.
    final permission = await platform.permission();
    if (permission == NoticePermission.unavailable) return;

    if (_ref.read(sessionProvider).status != SessionStatus.signedIn) {
      _facts = null;
      await platform.cancelDue();
      await platform.cancelGuest();
      return;
    }
    // A `preview` account's payments live only in the vault on this phone: nothing is asked of the
    // server for them (no recurrence list), and "Hoy vence…" waits for encryption. The guest
    // warning needs no finances but is only (re)scheduled on proof the server saw the person, which
    // a pass that asks nothing cannot give: it stays as it is.
    if (_ref.read(currentVaultAccountProvider)?.mode == EncryptionMode.preview) {
      _facts = null;
      await platform.cancelDue();
      return;
    }
    final due = _ref.read(dueNoticeEnabledProvider.notifier);
    final guestNotice = _ref.read(guestNoticeEnabledProvider.notifier);
    await Future.wait([due.ready, guestNotice.ready]);
    // Read after the waits: the session may have changed meanwhile, and a later pass is queued.
    if (_ref.read(sessionProvider).status != SessionStatus.signedIn) return;
    final dueOn = _ref.read(dueNoticeEnabledProvider);
    final guestOn = _ref.read(guestNoticeEnabledProvider);
    final guest = _ref.read(sessionProvider).isGuest;
    final language = widgetLanguage(_ref);

    final guestRelevant = guest && guestOn;
    // One foreground request per pass: the zone and the recurring payments are the server's word,
    // and an answer is also the proof that the server saw the person (its own 60-day clock moved).
    NoticeFacts? fresh;
    if (dueOn || guestRelevant) {
      try {
        fresh = _facts = await _ref.read(noticeBackendProvider).facts();
      } on Object {
        // Offline or a server error: nothing moved on the server, and nothing moves here.
      }
    }
    if (guestRelevant) {
      // The 44 days restart only when the server accepted a request: an opening that never
      // reached it (offline) must not push the warning past the 60 days it counts.
      if (fresh != null) await platform.scheduleGuest(language: language);
    } else {
      await platform.cancelGuest();
    }

    var recurringRelevant = false;
    if (dueOn) {
      final facts = fresh ?? _facts;
      if (facts == null) {
        // Nothing known (offline): the job stays as it is.
      } else if (!facts.hasRecurring) {
        await platform.cancelDue();
      } else {
        recurringRelevant = true;
        if (permission == NoticePermission.granted) {
          await platform.scheduleDue(zone: facts.timezone, language: language);
        } else {
          await platform.cancelDue();
        }
      }
    } else {
      await platform.cancelDue();
    }

    // The question waits for the person, so it never holds up the passes behind it.
    if (recurringRelevant) {
      _ask(NoticeReason.due);
    } else if (guestRelevant) {
      _ask(NoticeReason.guest);
    }
  }

  void _ask(NoticeReason reason) {
    if (_askingNow) return;
    _askingNow = true;
    _asking = _askOnce(reason)
        .then((allowed) {
          // Allowed just now: "Hoy vence…", which was waiting for it, can be scheduled.
          if (allowed && reason == NoticeReason.due) request();
        })
        .catchError((Object _) {
          // Nothing asked: the notices just do not post.
        })
        .whenComplete(() => _askingNow = false);
  }

  /// The permission, once: with a sentence on why in the app, then Android's own prompt.
  Future<bool> _askOnce(NoticeReason reason) async {
    final asked = _ref.read(flagStoreProvider('notice.permission.asked'));
    if (await asked.read() == true) return false;
    // Allowed already, or switched off where the app cannot change it: nothing to ask.
    if (await _platform.permission() != NoticePermission.askable) return false;
    final answer = await _ref.read(noticePromptProvider)(reason);
    // No screen to ask on, or the question was closed by something other than the person (a link
    // opening a sheet): not an answer, it is asked at the next chance.
    if (answer == null) return false;
    // Counted as soon as the person has answered, whatever they answer.
    try {
      await asked.write(true);
    } on Object {
      // Not kept: it may be asked once more after a restart.
    }
    return answer && await _platform.requestPermission();
  }
}

/// The notices' keeper. The app watches it from the start (app.dart).
final noticeSyncProvider = Provider<NoticeSync>((ref) {
  final sync = NoticeSync(ref);
  WidgetsBinding.instance.addObserver(sync);
  ref.onDispose(() => WidgetsBinding.instance.removeObserver(sync));
  // A new session, a guest who claimed an email, a switch, the language: a new pass.
  ref.listen(sessionProvider.select((s) => (s.status, s.isGuest)), (previous, next) {
    if (previous != next) sync.request();
  });
  ref.listen(dueNoticeEnabledProvider, (previous, next) {
    if (previous != next) sync.request();
  });
  ref.listen(guestNoticeEnabledProvider, (previous, next) {
    if (previous != next) sync.request();
  });
  ref.listen(localeOverrideProvider, (previous, next) {
    if (previous != next) sync.request();
  });
  // The account turning out to be `preview`: "Hoy vence…" is cancelled and the server asked nothing.
  // (`plain` needs no pass of its own: until the mode is known the guard holds every finance call.)
  ref.listen(currentVaultAccountProvider.select((a) => a?.mode), (previous, next) {
    if (next == EncryptionMode.preview && previous != next) sync.request();
  });
  // While the stored session is being read the listener above asks as soon as it is known.
  if (ref.read(sessionProvider).status != SessionStatus.loading) sync.request();
  return sync;
});
