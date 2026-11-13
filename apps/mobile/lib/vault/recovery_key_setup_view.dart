// The web's RecoveryKeySetup (apps/web/app/features/vault/RecoveryKeySetup.tsx): first run of a
// `preview` account shows the recovery key once, lets the person copy or share it, then asks for
// four of its characters back before "Continue" enables (spec 2026-11-12 section 6.3). Pure UI: the
// key comes in, the caller decides what happens next. Where the web downloads a file, the phone
// opens the system share sheet (a password manager, say) through `wambito/files`.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../entry/sign_in_frame.dart';
import '../l10n/app_localizations.dart';
import '../theme/surfaces.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../ui/input_box.dart';
import '../ui/lk_theme.dart';
import '../ui/press_button.dart';
import '../ui/web_text_field.dart' show editableStateBelow;
import 'vault_model.dart';

/// The name of the file the share sheet gets.
const recoveryFileName = 'wambito-recovery-key.txt';

/// The recovery key's face: the web's `font-mono text-[20px] font-bold`.
const _keyStyle = TextStyle(
  fontFamily: 'monospace',
  fontFamilyFallback: ['Menlo', 'Roboto Mono', 'Courier'],
  fontSize: 20,
  fontWeight: FontWeight.w700,
  height: 1.5,
  letterSpacing: 0.4,
);

class RecoveryKeySetupView extends StatefulWidget {
  const RecoveryKeySetupView({
    super.key,
    required this.recoveryKey,
    required this.onContinue,
    required this.onSignOut,
    this.onShare,
    this.onCopy,
    this.now,
    this.positions,
  });

  /// The formatted key (`XXXX-XXXX-…`). Shown here and nowhere else.
  final String recoveryKey;

  /// The person confirmed they kept it: the app goes on.
  final VoidCallback onContinue;

  /// Signs out (and wipes this phone's vault): nothing was sent yet, so nothing is kept.
  final VoidCallback onSignOut;

  /// Hands the file's name and text to the share sheet; null shares nothing.
  final Future<void> Function(String name, String text)? onShare;

  /// Puts the key on the clipboard; the phone's by default.
  final Future<void> Function(String text)? onCopy;

  /// For the file's date; now by default.
  final DateTime? now;

  /// The 1-based positions to type back (4); random unless a test pins them.
  final List<int>? positions;

  @override
  State<RecoveryKeySetupView> createState() => _RecoveryKeySetupViewState();
}

class _RecoveryKeySetupViewState extends State<RecoveryKeySetupView> {
  late final List<int> _positions = widget.positions ?? pickPositions();
  late final List<TextEditingController> _typed = [
    for (final _ in _positions) TextEditingController(),
  ];
  late final List<FocusNode> _focus = [for (final _ in _positions) FocusNode()];
  var _confirming = false;
  var _copied = false;
  Timer? _copiedTimer;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    for (final c in _typed) {
      c.dispose();
    }
    for (final f in _focus) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _copy() async {
    try {
      final copy = widget.onCopy;
      if (copy != null) {
        await copy(widget.recoveryKey);
      } else {
        await Clipboard.setData(ClipboardData(text: widget.recoveryKey));
      }
    } on Object {
      // The clipboard can be blocked; the key is on screen and can be shared.
      return;
    }
    if (!mounted) return;
    setState(() => _copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Future<void> _share() async {
    final l10n = AppLocalizations.of(context);
    final date = DateFormat.yMMMMd(l10n.localeName).format(widget.now ?? DateTime.now());
    final text = recoveryFileText(
      title: l10n.vaultSetupFileTitle,
      key: widget.recoveryKey,
      line: l10n.vaultSetupFileLine,
      date: l10n.vaultSetupFileDate(date),
    );
    try {
      await widget.onShare?.call(recoveryFileName, text);
    } on Object {
      // No share sheet on this phone; the key is on screen and can be copied.
    }
  }

  List<String> get _chars => [for (final c in _typed) c.text];

  @override
  Widget build(BuildContext context) => _confirming ? _confirm(context) : _show(context);

  Widget _show(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    return SignInFrame(
      children: [
        EntryTitle(l10n.vaultSetupTitle),
        EntryLead(l10n.vaultSetupLead),
        Semantics(
          container: true,
          label: l10n.vaultSetupKeyLabel,
          child: SizedBox(
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surfaceRow,
                borderRadius: LkSurface.radius(LkRadius.md),
                border: LkSurface.border(colors),
              ),
              child: Padding(
                padding: const EdgeInsets.all(WambitoTokens.space3),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: WambitoTokens.space3,
                  runSpacing: WambitoTokens.space2,
                  children: [
                    for (final group in widget.recoveryKey.split('-'))
                      Text(group, style: _keyStyle.copyWith(color: colors.ink)),
                  ],
                ),
              ),
            ),
          ),
        ),
        Row(
          spacing: WambitoTokens.space2,
          children: [
            Expanded(
              child: PressButton.text(
                _copied ? l10n.vaultSetupCopied : l10n.vaultSetupCopy,
                key: const Key('vault.copy'),
                tone: PressTone.secondary,
                onPressed: _copy,
              ),
            ),
            Expanded(
              child: PressButton.text(
                l10n.vaultSetupShare,
                key: const Key('vault.share'),
                tone: PressTone.secondary,
                onPressed: _share,
              ),
            ),
          ],
        ),
        SizedBox(
          width: double.infinity,
          child: PressButton.text(
            l10n.vaultSetupSaved,
            key: const Key('vault.saved'),
            onPressed: () => setState(() => _confirming = true),
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: PressButton.text(
            l10n.settingsSignOut,
            key: const Key('vault.signOut'),
            tone: PressTone.ghost,
            onPressed: widget.onSignOut,
          ),
        ),
      ],
    );
  }

  Widget _confirm(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    final chars = _chars;
    final filled = chars.every((c) => c.trim().isNotEmpty);
    final matches = confirmationMatches(widget.recoveryKey, _positions, chars);
    final mismatch = filled && !matches;
    return SignInFrame(
      children: [
        EntryTitle(l10n.vaultSetupConfirmTitle),
        EntryLead(l10n.vaultSetupConfirmLead),
        Semantics(
          container: true,
          label: l10n.vaultSetupCharsGroup,
          child: Row(
            spacing: WambitoTokens.space2,
            children: [
              for (final (i, n) in _positions.indexed)
                Expanded(child: _box(context, i, groupPosition(n), mismatch, colors)),
            ],
          ),
        ),
        if (mismatch) FieldError(l10n.vaultSetupMismatch, textAlign: TextAlign.center),
        SizedBox(
          width: double.infinity,
          child: PressButton.text(
            l10n.vaultSetupContinue,
            key: const Key('vault.continue'),
            onPressed: matches ? widget.onContinue : null,
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: PressButton.text(
            l10n.vaultSetupShowAgain,
            key: const Key('vault.showAgain'),
            tone: PressTone.ghost,
            onPressed: () => setState(() => _confirming = false),
          ),
        ),
      ],
    );
  }

  Widget _box(
    BuildContext context,
    int i,
    ({int group, int char}) at,
    bool mismatch,
    WambitoColors colors,
  ) {
    final l10n = AppLocalizations.of(context);
    return Column(
      spacing: WambitoTokens.space1,
      children: [
        ExcludeSemantics(
          child: Column(
            children: [
              Text(
                l10n.vaultSetupGroup(at.group),
                textAlign: TextAlign.center,
                style: LkText.note.copyWith(fontWeight: FontWeight.w700, color: colors.ink),
              ),
              Text(
                l10n.vaultSetupCharInGroup(at.char),
                textAlign: TextAlign.center,
                style: LkText.note.copyWith(color: colors.inkMuted),
              ),
            ],
          ),
        ),
        _CharBox(
          controller: _typed[i],
          focusNode: _focus[i],
          label: l10n.vaultSetupCharLabel(at.group, at.char),
          invalid: mismatch,
          onChanged: (_) {
            setState(() {});
            // One character: on to the next box.
            if (_typed[i].text.isNotEmpty && i + 1 < _focus.length) _focus[i + 1].requestFocus();
          },
        ),
      ],
    );
  }
}

/// One character of the quiz (`<input maxLength=1>`): a box with the key's face, centred, in
/// capitals, that hands the focus on once it has its character.
class _CharBox extends StatelessWidget {
  const _CharBox({
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.invalid,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final bool invalid;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.lkColors;
    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, _) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          focusNode.requestFocus();
          editableStateBelow(context)?.requestKeyboard();
        },
        child: InputBox(
          focused: focusNode.hasFocus,
          borderColor: invalid ? colors.over : null,
          alignment: Alignment.center,
          child: Semantics(
            label: label,
            textField: true,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 36),
              child: EditableText(
                controller: controller,
                focusNode: focusNode,
                style: _keyStyle.copyWith(color: colors.ink),
                textAlign: TextAlign.center,
                cursorColor: colors.ink,
                backgroundCursorColor: colors.inkMuted,
                selectionColor: colors.brand.withValues(alpha: 0.4),
                rendererIgnoresPointer: true,
                maxLines: 1,
                inputFormatters: [LengthLimitingTextInputFormatter(1)],
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: onChanged,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
