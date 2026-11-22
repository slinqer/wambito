// `/merge`: where a merge into an email account stands (phone-first spec 7.2): bringing the data,
// the currency stop (cancel, or keep only the account's data after a confirm), the upload, done,
// or a failed step with a retry.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../entry/sign_in_frame.dart';
import '../l10n/app_localizations.dart';
import '../theme/tokens.g.dart';
import '../ui/confirm_sheet.dart';
import '../ui/press_button.dart';
import 'merge_controller.dart';

class MergeScreen extends ConsumerStatefulWidget {
  const MergeScreen({super.key});

  /// How often the screen asks the upload to go on while it waits.
  static const retryEvery = Duration(seconds: 15);

  @override
  ConsumerState<MergeScreen> createState() => _MergeScreenState();
}

class _MergeScreenState extends ConsumerState<MergeScreen> {
  Timer? _retry;
  var _busy = false;

  @override
  void dispose() {
    _retry?.cancel();
    super.dispose();
  }

  MergeController get _merge => ref.read(mergeControllerProvider.notifier);

  Future<void> _do(Future<void> Function() step) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await step();
    } on Object {
      // The state says what went wrong.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _home() {
    if (mounted && GoRouter.maybeOf(context) != null) context.go('/');
  }

  Future<void> _keepAccount(AppLocalizations l10n) => ConfirmSheet.show(
    context,
    title: l10n.mergeKeepAccountTitle,
    body: l10n.mergeKeepAccountBody,
    confirmLabel: l10n.mergeKeepAccountConfirm,
    confirmKey: const Key('merge.keepAccountConfirm'),
    onConfirm: _merge.keepAccountOnly,
  );

  Widget _button(String label, Key key, VoidCallback onPressed, {PressTone? tone}) => SizedBox(
    width: double.infinity,
    child: PressButton.text(
      label,
      key: key,
      tone: tone ?? PressTone.primary,
      onPressed: _busy ? null : onPressed,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(mergeControllerProvider);
    // While the upload waits for the network (or the old vault for a headless run), ask again now
    // and then.
    if (state is MergeUploading || (state is MergeFailed && state.code == 'busy')) {
      _retry ??= Timer.periodic(MergeScreen.retryEvery, (_) => unawaited(_merge.run()));
    } else {
      _retry?.cancel();
      _retry = null;
    }
    final cancel = _button(
      l10n.mergeCancel,
      const Key('merge.cancel'),
      () => unawaited(
        _do(() async {
          await _merge.cancel();
          _home();
        }),
      ),
      tone: PressTone.secondary,
    );
    final children = switch (state) {
      MergeCurrencyStop(:final phone, :final account) => [
        EntryTitle(l10n.mergeCurrencyTitle),
        EntryLead(l10n.mergeCurrencyStop(account, phone), ink: true),
        EntryLead(l10n.mergeCurrencyLead),
        _buttons([
          cancel,
          _button(
            l10n.mergeKeepAccount,
            const Key('merge.keepAccount'),
            () => unawaited(_keepAccount(l10n)),
            tone: PressTone.secondary,
          ),
        ]),
      ],
      MergeUploading(:final pending) => [
        EntryTitle(l10n.mergeUploadingTitle),
        EntryLead(l10n.mergeUploadingLead(pending), ink: true),
        EntryLead(l10n.mergeUploadingNote),
        _button(l10n.mergeKeepUsing, const Key('merge.keepUsing'), _home),
      ],
      MergeDone() => [
        EntryTitle(l10n.mergeDoneTitle),
        _button(l10n.mergeDoneGo, const Key('merge.done'), _home),
      ],
      MergeFailed(:final code, :final carried) => [
        EntryTitle(l10n.mergeFailedTitle),
        EntryLead(code == 'account_plain' ? l10n.mergeFailedPlain : l10n.mergeFailedLead),
        _buttons([
          if (code != 'account_plain')
            _button(l10n.mergeRetry, const Key('merge.retry'), () => unawaited(_do(_merge.run))),
          if (!carried) cancel,
        ]),
      ],
      // Nothing to show (called off): the way home.
      MergeIdle() => [_button(l10n.mergeDoneGo, const Key('merge.done'), _home)],
      MergeSigningIn() || MergeWaitingUnlock() => [
        Semantics(liveRegion: true, container: true, child: EntryTitle(l10n.mergeWorking)),
      ],
    };
    return SignInFrame(children: children);
  }

  Widget _buttons(List<Widget> buttons) => SizedBox(
    width: double.infinity,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WambitoTokens.space2,
      children: buttons,
    ),
  );
}
