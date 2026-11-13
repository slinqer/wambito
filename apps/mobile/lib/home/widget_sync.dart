import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/device.dart';
import '../api/gen/wambito_api.dart';
import '../api/session.dart';
import '../l10n/app_localizations.dart';
import '../settings/preferences.dart';
import 'home_controller.dart';
import 'widget_snapshot.dart';

/// The language of the widget's words and amounts: the one picked in Settings, else the phone's
/// (Spanish unless it asks for English), as the app's own screens.
String widgetLanguage(Ref ref) =>
    ref.read(localeOverrideProvider)?.languageCode ??
    languageOfTag(ref.read(deviceHintsProvider).locale);

/// The app's theme choice as the widget reads it (`theme` in the snapshot).
String widgetTheme(ThemeMode mode) => switch (mode) {
  ThemeMode.dark => 'dark',
  ThemeMode.light => 'light',
  ThemeMode.system => 'system',
};

/// Keeps the home-screen widget's snapshot (lib/home/widget_snapshot.dart) in step with the app
/// (spec section 7.1):
///
/// * every summary home loads is written, once the hide-amount choice has been read back (so a
///   hidden amount is never written in the clear, even for a moment at a cold start);
/// * the hide-amount switch and the theme choice are copied in whenever they change: the widget is
///   Kotlin and cannot read `flutter_secure_storage`, where Settings keeps them;
/// * a sign-out writes the signed-out snapshot at once, and nothing of a signed-in person is
///   written after it (Review Focus 4): every write checks the session right before it is sent,
///   with nothing awaited in between, so it lands either before the sign-out's or not at all.
///
/// Summary and choice writes run one after another, so an older one never lands after a newer
/// one. The Kotlin refresh job (RefreshWorker.kt) writes the same document on its own; it never
/// writes once the session token is gone.
class WidgetSync {
  WidgetSync(this._ref);

  final Ref _ref;
  var _queue = Future<void>.value();

  /// Grows at each sign-out: a write queued before it is dropped, even when the next session is
  /// already signed in by the time it runs (a guest replaced by an email account).
  var _session = 0;

  /// From a sign-out until the next sign-in, nothing signed in is written. Sign-out writes the
  /// widget before it forgets the session (so a process that dies in between leaves no figure),
  /// which means the session still reads as signed in for a moment: this covers that moment.
  var _closed = false;

  /// The signed-in account is `preview` (set by lib/vault/preview_sync.dart): its figures live only
  /// in the vault on this phone, so none is written to the widget, which says "Coming soon with
  /// encryption" instead. A plain account never sets it.
  var _preview = false;

  WidgetStore get _store => _ref.read(widgetStoreProvider);
  bool get _signedIn => _ref.read(sessionProvider).status == SessionStatus.signedIn;
  bool get _hideAmount => _ref.read(hideWidgetAmountProvider);
  String get _theme => widgetTheme(_ref.read(themeModeProvider));

  /// The sentence of a `preview` account's widget, in the widget's language.
  String _previewLine() =>
      lookupAppLocalizations(Locale(widgetLanguage(_ref))).comingSoonWithEncryption;

  Map<String, Object?> _previewSnapshot() => signedOutSnapshot(
    hideAmount: _hideAmount,
    theme: _theme,
    locale: widgetLanguage(_ref),
    line: _previewLine(),
  );

  /// The account's mode is now known to be `preview` or not. For `preview` the widget gets its
  /// no-figure snapshot with "Coming soon with encryption" (dropped when the session is gone), and
  /// no figure is written until the mode changes. Never called for, nor affects, a `plain` account.
  Future<void> modeChanged({required bool preview}) {
    final was = _preview;
    _preview = preview;
    if (!preview || was) return _queue;
    final session = _session;
    return _enqueue(() async {
      await _ref.read(hideWidgetAmountProvider.notifier).ready;
      if (_closed || !_signedIn || session != _session || !_preview) return;
      await saveWidgetSnapshot(_store, _previewSnapshot());
    });
  }

  /// Completes when every write asked so far is done (tests wait on it).
  Future<void> get idle => _queue;

  Future<void> _enqueue(Future<void> Function() write) {
    final next = _queue.then((_) async {
      try {
        await write();
      } on Object {
        // The widget keeps what it had; this never breaks the app.
      }
    });
    _queue = next;
    return next;
  }

  /// Writes [summary], the month home just loaded, in [currency], with the profile's [timezone].
  /// [locale] is the language its amount is written in ([widgetLanguage] when null).
  Future<void> summaryLoaded(
    Summary summary, {
    required String currency,
    required String timezone,
    String? locale,
  }) {
    final language = locale ?? widgetLanguage(_ref);
    final updatedAt = _ref.read(clockProvider)();
    final session = _session;
    return _enqueue(() async {
      await _ref.read(hideWidgetAmountProvider.notifier).ready;
      if (_closed || !_signedIn || session != _session) return;
      // The month's figures came from the vault on this phone: they stay there.
      if (_preview) {
        await saveWidgetSnapshot(_store, _previewSnapshot());
        return;
      }
      await saveWidgetSnapshot(
        _store,
        signedInSnapshot(
          summary,
          currency: currency,
          locale: language,
          hideAmount: _hideAmount,
          theme: _theme,
          updatedAt: updatedAt,
          timezone: timezone,
        ),
      );
    });
  }

  /// The session ended: the widget says "Abre Wambito para empezar" and holds no figure. Written
  /// straight away, ahead of anything queued (which then finds the session gone and writes
  /// nothing), and never held up by a slow store read.
  Future<void> signedOut() async {
    _session++;
    _closed = true;
    _preview = false;
    try {
      await saveWidgetSnapshot(
        _store,
        signedOutSnapshot(hideAmount: _hideAmount, theme: _theme, locale: widgetLanguage(_ref)),
      );
    } on Object {
      // Nothing more to do.
    }
  }

  /// Someone signed in: their figures may be written again.
  void signedIn() => _closed = false;

  /// The hide-amount switch or the theme changed: the stored snapshot gets them, its figures and
  /// their time unchanged.
  Future<void> choicesChanged() {
    final session = _session;
    return _enqueue(() async {
      await _ref.read(hideWidgetAmountProvider.notifier).ready;
      final stored = await _store.read(widgetSnapshotKey);
      final patched = withChoices(stored, hideAmount: _hideAmount, theme: _theme);
      if (patched == null) {
        // Nothing of this version yet: signed out, the signed-out snapshot carries the choices;
        // signed in, home's next load writes everything.
        if (!_signedIn) {
          await saveWidgetSnapshot(
            _store,
            signedOutSnapshot(hideAmount: _hideAmount, theme: _theme, locale: widgetLanguage(_ref)),
          );
        } else if (_preview && !_closed && session == _session) {
          await saveWidgetSnapshot(_store, _previewSnapshot());
        }
        return;
      }
      // Read before a sign-out, written after it: dropped, the sign-out's snapshot stands.
      if (patched['signedIn'] == true && (_closed || !_signedIn || session != _session)) return;
      await saveWidgetSnapshot(_store, patched);
    });
  }
}

/// The widget's snapshot keeper. The app watches it from the start (app.dart), so the choices are
/// followed for as long as the app runs.
final widgetSyncProvider = Provider<WidgetSync>((ref) {
  final sync = WidgetSync(ref);
  ref.listen(hideWidgetAmountProvider, (previous, next) {
    if (previous != next) unawaited(sync.choicesChanged());
  });
  ref.listen(themeModeProvider, (previous, next) {
    if (previous != next) unawaited(sync.choicesChanged());
  });
  return sync;
});
