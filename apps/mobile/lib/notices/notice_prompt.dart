import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../router.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../ui/lk_theme.dart';
import '../ui/press_button.dart';
import '../ui/sheet.dart';

/// Why the app asks to post notices: the notice that just became relevant.
enum NoticeReason {
  /// "Hoy vence…": a recurring payment exists and the notice is on.
  due,

  /// The guest warning: a guest account exists and the notice is on.
  guest,
}

/// Asks the person, in the app, whether notices may be posted, with one sentence on why. True:
/// "Permitir avisos"; false: "Ahora no"; null: nothing was answered (no screen to ask on, or the
/// question was closed by something other than the person, such as a link opening a sheet), so it
/// is asked again at the next chance.
typedef NoticePrompt = Future<bool?> Function(NoticeReason reason);

/// The question, on home and only there (replaced in tests), in the web's sheet: one sentence on
/// why, "Permitir avisos" and "Ahora no". Only those two buttons (and the back button, as "Ahora
/// no") answer it: the backdrop, a drag and Escape do nothing, and there is no "Cerrar".
final noticePromptProvider = Provider<NoticePrompt>((ref) {
  return (reason) async {
    final context = await _homeContext(ref);
    if (context == null || !context.mounted) return null;
    final l10n = AppLocalizations.of(context);
    return LkSheet.show<bool>(
      context,
      title: l10n.noticeAskTitle,
      dismissible: false,
      // The back button is "Ahora no"; a pop from the app itself (a link closing every sheet) does
      // not come here and leaves the result null.
      backResult: () => false,
      children: [
        _NoticeQuestion(
          why: switch (reason) {
            NoticeReason.due =>
              defaultTargetPlatform == TargetPlatform.iOS
                  ? l10n.noticeAskDueIos
                  : l10n.noticeAskDue,
            NoticeReason.guest => l10n.noticeAskGuest,
          },
          allowLabel: l10n.noticeAskAllow,
          laterLabel: l10n.noticeAskLater,
        ),
      ],
    );
  };
});

/// What the sheet says and offers: the reason, then the allowing button above the declining one
/// (the web's `ChoiceSheet` order: the way forward first, the way out last).
class _NoticeQuestion extends StatelessWidget {
  const _NoticeQuestion({required this.why, required this.allowLabel, required this.laterLabel});

  final String why;
  final String allowLabel;
  final String laterLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.lkColors;
    return Padding(
      key: const Key('notices.ask'),
      padding: const EdgeInsets.only(top: WambitoTokens.space3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: WambitoTokens.space4,
        children: [
          Text(
            why,
            key: const Key('notices.askWhy'),
            style: LkText.body.copyWith(color: colors.ink),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: WambitoTokens.space2,
            children: [
              PressButton.text(
                allowLabel,
                key: const Key('notices.askAllow'),
                onPressed: () => Navigator.of(context).pop(true),
              ),
              PressButton.text(
                laterLabel,
                key: const Key('notices.askLater'),
                tone: PressTone.ghost,
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// How long the question waits for home to be free, and how often it looks.
const _waitForHome = Duration(minutes: 5);
const _lookEvery = Duration(milliseconds: 250);

/// The screen to ask on: the router's navigator while the person is on home with nothing over it
/// (no sheet, no dialog, no other screen). It waits for that for a few minutes (a sheet the person
/// is using is theirs), and takes one more frame once there, since the navigator is still showing
/// the page that home replaces. Null when home never frees up: nothing is asked.
Future<BuildContext?> _homeContext(Ref ref) async {
  final router = ref.read(routerProvider);
  final navigator = router.routerDelegate.navigatorKey;

  bool free() {
    final context = navigator.currentContext;
    return router.state.uri.path == '/' &&
        context != null &&
        context.mounted &&
        !Navigator.of(context).canPop();
  }

  final end = DateTime.now().add(_waitForHome);
  while (DateTime.now().isBefore(end)) {
    if (free()) {
      await WidgetsBinding.instance.endOfFrame;
      if (free()) return navigator.currentContext;
    }
    await Future<void>.delayed(_lookEvery);
  }
  return null;
}
