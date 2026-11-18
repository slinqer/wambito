import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/auth_api.dart';
import '../api/session.dart';
import '../l10n/app_localizations.dart';
import '../ui/press_button.dart';
import 'auth_errors.dart';
import 'needs_connection.dart';
import 'sign_in_frame.dart';

/// The welcome (phone-first accounts, spec section 4): Wambi on the web's sign-in frame, "Start"
/// (primary) and "I already have an account" (a link). "Start" signs in anonymously
/// (`POST /auth/sign-in/anonymous`) and lands home; nothing else is asked. On a server that makes
/// encrypted new users the vault gate then sets the account up without a recovery key; on one that
/// makes `plain` users it is today's guest. "I already have an account" opens the sign-in (email code
/// or magic link, and the passkey) without making any account. A brand-new person has no passkey,
/// so it lives on that step. Without network, "Start" opens a provisional vault where new users
/// are known to be encrypted (`SessionController.startGuest`); elsewhere [NeedsConnection] says it
/// needs a connection, with "Try again".
class EntryScreen extends ConsumerStatefulWidget {
  const EntryScreen({super.key});

  @override
  ConsumerState<EntryScreen> createState() => _EntryScreenState();
}

enum _Busy { none, start }

class _EntryScreenState extends ConsumerState<EntryScreen> {
  _Busy _busy = _Busy.none;
  AuthError? _error;

  /// The last "Start" found no network (and could not start offline): [NeedsConnection] says so.
  bool _offline = false;

  Future<void> _run(
    _Busy busy,
    Future<void> Function() action,
    AuthError? Function(AuthFailure) onFail,
  ) async {
    setState(() {
      _busy = busy;
      _error = null;
    });
    try {
      await action();
      if (mounted) setState(() => _offline = false);
    } on Object catch (error) {
      // No network, on a server not known to make encrypted users: nothing was made, and the
      // welcome says it needs a connection (ruling 8).
      if (isOfflineError(error)) {
        if (mounted) setState(() => _offline = true);
      } else if (error is AuthFailure) {
        if (mounted) {
          setState(() {
            _offline = false;
            _error = onFail(error);
          });
        }
      } else {
        // Never an unhandled error with a busy button: a message, and the buttons work again.
        if (mounted) {
          setState(() {
            _offline = false;
            _error = unexpectedErrorFor(error);
          });
        }
      }
    } finally {
      if (mounted) setState(() => _busy = _Busy.none);
    }
  }

  void _start() => _run(
    _Busy.start,
    () => ref.read(sessionProvider.notifier).startGuest(),
    (failure) => authErrorFor(failure, AuthAction.signIn),
  );

  /// The web's `w-full`.
  Widget _full(Widget child) => SizedBox(width: double.infinity, child: child);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final busy = _busy != _Busy.none;
    final error = _error;

    return SignInFrame(
      children: [
        EntryTitle(l10n.appName),
        EntryLead(l10n.entryLead),
        // Nothing to fill and nothing to choose: start, or say you already have an account.
        _full(
          PressButton.text(
            _busy == _Busy.start ? l10n.entryStartBusy : l10n.entryStart,
            key: const Key('entry.start'),
            onPressed: busy ? null : _start,
          ),
        ),
        _full(
          PressButton.text(
            l10n.entryHaveAccount,
            key: const Key('entry.haveAccount'),
            tone: PressTone.ghost,
            link: true,
            onPressed: busy ? null : () => context.push('/entry/email'),
          ),
        ),
        if (_offline) NeedsConnection(onTryAgain: busy ? null : _start),
        if (error != null) FieldError(error.message(l10n), textAlign: TextAlign.center),
      ],
    );
  }
}
