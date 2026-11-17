import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../feedback/stored_flag.dart';
import '../l10n/app_localizations.dart';
import '../theme/surfaces.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../ui/lk_theme.dart';
import '../ui/press_button.dart';
import '../ui/sheet.dart';
import 'wambi_face.dart';
import 'widget_pin.dart';

/// Where the person's "Ahora no" on the widget card is kept (it stays on this phone, for good).
const widgetCardClosedKey = 'wambito.widgetCard.closed';

bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Whether a Wambito widget is on a home screen. Android only: elsewhere there is nothing to ask,
/// so it reads true (nothing to offer). After the launcher's dialog the answer is asked again on
/// the next return to the app ([pinned]), since the person may have declined.
class WidgetOnHome extends AsyncNotifier<bool> with WidgetsBindingObserver {
  var _awaiting = false;

  @override
  Future<bool> build() async {
    final binding = WidgetsBinding.instance..addObserver(this);
    ref.onDispose(() => binding.removeObserver(this));
    if (!_android) return true;
    return ref.read(widgetPinProvider).installed();
  }

  /// The launcher's dialog was shown: look again when the person is back.
  void pinned() => _awaiting = true;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_awaiting) return;
    _awaiting = false;
    ref.invalidateSelf();
  }
}

final widgetOnHomeProvider = AsyncNotifierProvider<WidgetOnHome, bool>(WidgetOnHome.new);

/// Asks the launcher to add the widget when it can; otherwise explains the three steps.
Future<void> addWidget(BuildContext context, WidgetRef ref) async {
  final pin = ref.read(widgetPinProvider);
  if (await pin.supported() && await pin.pin()) {
    ref.read(widgetOnHomeProvider.notifier).pinned();
    return;
  }
  if (context.mounted) await showWidgetSteps(context);
}

/// Home's "Anota sin abrir la app": true when it should show, which is Android, no widget yet and
/// not put away. Home adds "there is a movement".
class WidgetCardController extends AsyncNotifier<bool> {
  FlagStore get _store => ref.read(flagStoreProvider(widgetCardClosedKey));

  @override
  Future<bool> build() async {
    if (!_android) return false;
    var closed = false;
    try {
      closed = await _store.read() ?? false;
    } on Object {
      // Unreadable: not put away.
    }
    if (closed) return false;
    return !await ref.watch(widgetOnHomeProvider.future);
  }

  /// "Ahora no": gone for good.
  Future<void> close() async {
    state = const AsyncData(false);
    try {
      await _store.write(true);
    } on Object {
      // Not kept: the card is back at the next start.
    }
  }

  /// "Añadir widget": the launcher's dialog, or the steps when it cannot.
  Future<void> add(BuildContext context, WidgetRef ref) => addWidget(context, ref);
}

final widgetCardProvider = AsyncNotifierProvider<WidgetCardController, bool>(
  WidgetCardController.new,
);

/// The card on home: Wambi, what the widget is for, "Añadir widget" and "Ahora no".
class WidgetCard extends ConsumerWidget {
  const WidgetCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    final controller = ref.read(widgetCardProvider.notifier);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: l10n.widgetCardTitle,
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
                            l10n.widgetCardTitle,
                            style: LkText.cardTitle.copyWith(color: colors.ink),
                          ),
                        ),
                        Text(
                          l10n.widgetCardBody,
                          style: LkText.cardLead.copyWith(color: colors.inkMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                spacing: WambitoTokens.space2,
                children: [
                  PressButton.text(
                    l10n.widgetCardClose,
                    key: const Key('widgetCard.close'),
                    tone: PressTone.ghost,
                    size: PressSize.sm,
                    onPressed: () => unawaited(controller.close()),
                  ),
                  PressButton.text(
                    l10n.widgetCardAdd,
                    key: const Key('widgetCard.add'),
                    size: PressSize.sm,
                    onPressed: () => unawaited(controller.add(context, ref)),
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

/// "Así añades el widget": the three steps, for a launcher that cannot be asked.
Future<void> showWidgetSteps(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return LkSheet.show<void>(
    context,
    title: l10n.widgetStepsTitle,
    children: [
      for (final (i, step) in [l10n.widgetStep1, l10n.widgetStep2, l10n.widgetStep3].indexed)
        _Step(number: i + 1, text: step),
    ],
    stuck: [
      Builder(
        builder: (sheet) => PressButton.text(
          l10n.widgetStepsDone,
          key: const Key('widgetSteps.done'),
          expanded: true,
          onPressed: () => Navigator.of(sheet).pop(),
        ),
      ),
    ],
  );
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.lkColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: WambitoTokens.space3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: WambitoTokens.space3,
        children: [
          ExcludeSemantics(
            child: Text('$number', style: LkText.cardTitle.copyWith(color: colors.brand)),
          ),
          Expanded(
            child: Text(text, style: LkText.body.copyWith(color: colors.ink)),
          ),
        ],
      ),
    );
  }
}
