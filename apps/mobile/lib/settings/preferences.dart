import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../feedback/stored_flag.dart';
import '../home/widget_choice.dart';
import '../home/widget_snapshot.dart';
import 'initial_settings.dart';
import 'settings_store.dart';

// What Settings (Task 14) keeps on the phone. Sound and vibration live in lib/feedback
// (`soundEnabledProvider`, `vibrationEnabledProvider`); the rest is here.
//
// For the widget (Task 15) and the local notices (Task 16), which read these:
//
//  * `hideWidgetAmountProvider`: true replaces the widget's amount with "••••" (spec section 7.1).
//    Off until chosen. The widget is Kotlin and cannot read this store, so whoever writes the
//    widget snapshot reads this provider and writes the choice in with it, after
//    `ref.read(hideWidgetAmountProvider.notifier).ready`; changing the switch must write the
//    snapshot again.
//  * `dueNoticeEnabledProvider`: the 9:00 "Hoy vence…" notice (spec section 7.2). On until chosen.
//  * `guestNoticeEnabledProvider`: the 45-day "Tus datos se borrarán…" notice for a guest account.
//    On until chosen.
//
// Each is a `StoredFlag`: `state` is the choice, `ready` completes when the kept choice has been
// read back, and `set(bool)` changes and keeps it. A notice scheduler should await `ready` before
// scheduling, and cancel or reschedule when the choice changes.

/// "Hoy vence…": at 9:00, one notice for the recurring payments still pending today.
class DueNoticeEnabled extends StoredFlag {
  @override
  FlagStore get store => ref.read(flagStoreProvider('setting.notice.due'));

  @override
  bool get initial => true;
}

final dueNoticeEnabledProvider = NotifierProvider<DueNoticeEnabled, bool>(DueNoticeEnabled.new);

/// The guest warning: a guest account that has not been opened for 45 days.
class GuestNoticeEnabled extends StoredFlag {
  @override
  FlagStore get store => ref.read(flagStoreProvider('setting.notice.guest'));

  @override
  bool get initial => true;
}

final guestNoticeEnabledProvider = NotifierProvider<GuestNoticeEnabled, bool>(
  GuestNoticeEnabled.new,
);

/// "Hide the amount in the widget": the widget shows "••••" in place of "Te quedan".
class HideWidgetAmount extends StoredFlag {
  /// In the widget's preferences, where the widget's eye writes it too (lib/home/widget_choice.dart);
  /// copied once from the secure-storage key it had before.
  @override
  FlagStore get store => WidgetPrefsFlagStore(
    ref.read(widgetStoreProvider),
    legacy: ref.read(flagStoreProvider('setting.widget.hideAmount')),
  );

  @override
  bool get initial => false;
}

final hideWidgetAmountProvider = NotifierProvider<HideWidgetAmount, bool>(HideWidgetAmount.new);

/// The theme: night unless the person picked day or "System" (the phone's own mode). Every choice
/// is kept, "System" included, since night is what no choice at all means.
class ThemeModeSetting extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.watch(initialSettingsProvider).themeMode;

  Future<void> set(ThemeMode mode) async {
    state = mode;
    final store = ref.read(settingsStoreProvider);
    try {
      await store.write(themeModeKey, switch (mode) {
        ThemeMode.system => 'system',
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
      });
    } on Object {
      // Not kept: the choice holds for this run.
    }
  }
}

final themeModeProvider = NotifierProvider<ThemeModeSetting, ThemeMode>(ThemeModeSetting.new);

/// The language: null follows the phone; otherwise `es` or `en`.
class LocaleOverride extends Notifier<Locale?> {
  @override
  Locale? build() => ref.watch(initialSettingsProvider).locale;

  Future<void> set(Locale? locale) async {
    state = locale;
    final store = ref.read(settingsStoreProvider);
    try {
      if (locale == null) {
        await store.delete(localeKey);
      } else {
        await store.write(localeKey, locale.languageCode);
      }
    } on Object {
      // Not kept: the choice holds for this run.
    }
  }
}

final localeOverrideProvider = NotifierProvider<LocaleOverride, Locale?>(LocaleOverride.new);
