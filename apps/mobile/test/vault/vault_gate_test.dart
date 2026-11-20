// Port of apps/web/app/features/vault/vault-gate.test.ts, plus an anonymous account that crashed
// half-way through its setup. An anonymous account is one whose prepared setup has no key to show;
// the gate has no guest branch (every `preview` account, with or without email, gets Unlock).
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/local/keys_error.dart';
import 'package:wambito/local/prf.dart';
import 'package:wambito/local/sync.dart' show SyncProblemCode;
import 'package:wambito/local/vault_session.dart' show VaultOpenError;
import 'package:wambito/vault/vault_gate.dart';

/// Keys and sessions are plain strings here: a session is the keys it was opened with.
typedef Gate = VaultGate<String, String>;

KeysError fail(String code) => KeysError(code);

/// Lets every pending future settle.
Future<void> settle() => pumpEventQueue();

/// Answers in turn, the last one again once the list is used up.
Future<T> Function() inTurn<T>(List<FutureOr<T> Function()> answers) {
  var i = 0;
  return () async {
    final answer = answers[i < answers.length - 1 ? i++ : i];
    return answer();
  };
}

class Harness {
  late Gate gate;
  final seen = <String>[];
  int loads = 0;
  int prepares = 0;
  final unlocked = <String>[];
  final opened = <(String, bool)>[];

  /// The last `open` call.
  (String, bool)? get lastOpen => opened.isEmpty ? null : opened.last;
}

Harness gateWith({
  Future<String?> Function()? loadLocalKeys,
  Future<GatePrepared<String>> Function()? prepareAccount,
  Future<String> Function(String text)? unlockWithRecovery,
  Future<String> Function(String keys, bool fresh)? open,
  String? userId,
  Future<String?> Function()? sessionUserId,
  void Function()? reload,
  PasskeyPrf? Function()? takeSignInPrf,
  Future<String> Function(PasskeyPrf passkey)? unlockWithPasskey,
  Future<void> Function(PasskeyPrf passkey)? addPasskeyWrap,
  Future<PasskeyPrf?> Function(List<String>? credentialIds)? evaluatePrf,
  Future<List<String>> Function()? accountPasskeyIds,
  Future<GatePairing<String>> Function()? startPairing,
  Uint8List? Function()? takeSignInRecoverySecret,
  Future<String> Function(Uint8List secret)? unlockWithRecoverySecret,
  Future<bool> Function()? passkeyGaveNoPrf,
  Future<void> Function()? notePasskeyWithoutPrf,
  Future<void> Function()? notePasskeyOpened,
  Future<bool> Function()? hasPasskeyWrap,
}) {
  final h = Harness();
  h.gate = Gate(
    VaultGateDeps(
      loadLocalKeys: () {
        h.loads += 1;
        return (loadLocalKeys ?? () async => null)();
      },
      prepareAccount: () {
        h.prepares += 1;
        return (prepareAccount ??
            () async => GatePrepared(recoveryKey: 'ABCD-EFGH', commit: () async => 'new'))();
      },
      unlockWithRecovery: (text) {
        h.unlocked.add(text);
        return (unlockWithRecovery ?? (_) async => 'unlocked')(text);
      },
      open: (keys, fresh) {
        h.opened.add((keys, fresh));
        return (open ?? (k, _) async => k)(keys, fresh);
      },
      userId: userId,
      sessionUserId: sessionUserId,
      reload: reload,
      takeSignInPrf: takeSignInPrf,
      unlockWithPasskey: unlockWithPasskey,
      addPasskeyWrap: addPasskeyWrap,
      evaluatePrf: evaluatePrf,
      accountPasskeyIds: accountPasskeyIds,
      startPairing: startPairing,
      takeSignInRecoverySecret: takeSignInRecoverySecret,
      unlockWithRecoverySecret: unlockWithRecoverySecret,
      passkeyGaveNoPrf: passkeyGaveNoPrf,
      notePasskeyWithoutPrf: notePasskeyWithoutPrf,
      notePasskeyOpened: notePasskeyOpened,
      hasPasskeyWrap: hasPasskeyWrap,
    ),
  );
  h.gate.subscribe(() => h.seen.add(h.gate.state.status));
  return h;
}

/// A new-device pairing whose `finish()` the test settles ([done], [fail]).
class FakePairing implements GatePairing<String> {
  FakePairing([this.id = 'p-1']);

  @override
  final String id;
  final finishing = Completer<String>();
  var cancels = 0;

  @override
  String get code => 'ABCDEFGH';
  @override
  String get qr => 'wambito://pair?id=$id&key=k';
  @override
  String get expiresAt => '2026-11-10T12:10:00Z';
  @override
  Future<String> number() async => '123456';
  @override
  Future<String> finish() => finishing.future;
  @override
  void cancel() => cancels += 1;
}

Future<GatePrepared<String>> alreadySetUp() async => throw fail('already_set_up');

bool zeroed(Uint8List bytes) => bytes.every((b) => b == 0);

void main() {
  group('vault gate', () {
    test('opens a known browser with its kept keys, without waiting for the network', () async {
      final h = gateWith(loadLocalKeys: () async => 'kept');
      h.gate.start();
      await settle();
      expect(h.gate.state, const Ready('kept'));
      expect(h.opened, [('kept', false)]);
      expect(h.prepares, 0);
      expect(h.seen, ['checking', 'opening', 'ready']);
    });

    test('a new account shows the key and sends nothing until the person confirms', () async {
      var commits = 0;
      final h = gateWith(
        prepareAccount: () async => GatePrepared(
          recoveryKey: 'ABCD-EFGH',
          commit: () async {
            commits += 1;
            return 'new';
          },
        ),
      );
      h.gate.start();
      await settle();
      expect(h.gate.state, const Setup('ABCD-EFGH'));
      expect(commits, 0);

      await h.gate.confirmSetup();
      expect(commits, 1);
      expect(h.opened, [('new', true)]);
      expect(h.gate.state, const Ready('new'));
    });

    test('an anonymous account commits at once: there is no key to show', () async {
      var commits = 0;
      final h = gateWith(
        prepareAccount: () async => GatePrepared(
          recoveryKey: null,
          commit: () async {
            commits += 1;
            return 'guest';
          },
        ),
      );
      h.gate.start();
      await settle();
      expect(commits, 1);
      expect(h.seen, isNot(contains('setup')));
      expect(h.gate.state, const Ready('guest'));
    });

    test('a failed commit locks, and the retry commits the same prepared keys again', () async {
      var commits = 0;
      final commit = inTurn<String>([() => throw fail('offline'), () => 'new']);
      final h = gateWith(
        prepareAccount: () async => GatePrepared(
          recoveryKey: 'ABCD-EFGH',
          commit: () {
            commits += 1;
            return commit();
          },
        ),
      );
      h.gate.start();
      await settle();
      await h.gate.confirmSetup();
      expect(h.gate.state, const Locked(LockedKind.offline, false));

      h.gate.retry();
      expect(h.gate.state, const Committing());
      await settle();
      expect(commits, 2);
      expect(h.prepares, 1);
      expect(h.gate.state, const Ready('new'));
    });

    test('an account with wraps asks for the recovery key; refusals stay on Unlock', () async {
      final answers = inTurn<String>([
        () => throw fail('wrong_recovery_key'),
        () => throw StateError('boom'),
        () => 'unlocked',
      ]);
      final g = gateWith(prepareAccount: alreadySetUp, unlockWithRecovery: (_) => answers());
      g.gate.start();
      await settle();
      expect(g.gate.state, const Unlock());

      expect(await g.gate.unlock('nope'), 'wrong_recovery_key');
      expect(g.gate.state, const Unlock());
      expect(await g.gate.unlock('nope'), 'server');
      expect(await g.gate.unlock('right'), isNull);
      expect(g.lastOpen, ('unlocked', true));
      expect(g.gate.state, const Ready('unlocked'));
    });

    test('a failed first sync locks, and the retry starts over with the kept keys', () async {
      String? keys;
      final opening = inTurn<String>([() => throw fail('server'), () => 'again']);
      final h = gateWith(
        loadLocalKeys: () async => keys,
        prepareAccount: () async =>
            GatePrepared(recoveryKey: null, commit: () async => keys = 'new'),
        open: (_, _) => opening(),
      );
      h.gate.start();
      await settle();
      expect(h.gate.state, const Locked(LockedKind.error, false));

      h.gate.retry();
      // starting over shows the check's loading state
      expect(h.gate.state, const Checking());
      await settle();
      expect(h.lastOpen, ('new', false));
      expect(h.opened, hasLength(2));
      expect(h.gate.state, const Ready('again'));
    });

    test('a first open refused busy (a background engine holds the lease) locks like offline, and '
        'the retry opens', () async {
      String? keys;
      final opening = inTurn<String>([
        () => throw const VaultOpenError(SyncProblemCode.busy),
        () => 'again',
      ]);
      final h = gateWith(
        loadLocalKeys: () async => keys,
        prepareAccount: () async =>
            GatePrepared(recoveryKey: null, commit: () async => keys = 'new'),
        open: (_, _) => opening(),
      );
      h.gate.start();
      await settle();
      expect(h.gate.state, const Locked(LockedKind.offline, false));

      h.gate.retry();
      await settle();
      expect(h.gate.state, const Ready('again'));
    });

    test('an error reading the account (offline) locks with the offline copy', () async {
      final h = gateWith(prepareAccount: () async => throw fail('offline'));
      h.gate.start();
      await settle();
      expect(h.gate.state, const Locked(LockedKind.offline, false));
    });

    test(
      'a setup that lost the race to another (409 already_set_up on commit) asks for the key',
      () async {
        var commits = 0;
        final h = gateWith(
          prepareAccount: () async => GatePrepared(
            recoveryKey: 'ABCD-EFGH',
            commit: () async {
              commits += 1;
              throw fail('already_set_up');
            },
          ),
        );
        h.gate.start();
        await settle();
        await h.gate.confirmSetup();
        expect(h.gate.state, const Unlock());
        expect(h.opened, isEmpty);
        // the prepared data key is gone: nothing commits it again
        await h.gate.confirmSetup();
        expect(commits, 1);
      },
    );

    test('the gate has no guest: its locked kinds, and pairing only from Unlock', () {
      expect(LockedKind.values, [
        LockedKind.error,
        LockedKind.offline,
        LockedKind.unsupported,
        LockedKind.plainServer,
      ]);
      expect(PairingFrom.values, [PairingFrom.unlock]);
    });

    test('an anonymous account with wraps elsewhere shows Unlock, not Locked', () async {
      // A regression guard: the gate has no notion of anonymity, so it must never lock this account out.
      final h = gateWith(prepareAccount: alreadySetUp, startPairing: () async => FakePairing());
      h.gate.start();
      await settle();
      expect(h.gate.state, const Unlock());
      // Its way back to its data is pairing, from Unlock, and back returns there.
      await h.gate.pair();
      expect(h.gate.state, const Pairing(PairingFrom.unlock));
      h.gate.leavePairing();
      expect(h.gate.state, const Unlock());
    });

    test('an anonymous account that loses the setup race shows Unlock', () async {
      final h = gateWith(
        prepareAccount: () async =>
            GatePrepared(recoveryKey: null, commit: () async => throw fail('already_set_up')),
      );
      h.gate.start();
      await settle();
      expect(h.gate.state, const Unlock());
    });

    test('an anonymous account that crashed between the recovery PUT and the device PUT shows '
        'Unlock, on the retry and on the next start', () async {
      // The recovery wrap reached the server, the device wrap did not: the account has a wrap
      // nobody here can open, so Unlock (pairing, or a recovery key if one was saved).
      var recoveryOnServer = false;
      Future<GatePrepared<String>> prepare() async {
        if (recoveryOnServer) throw fail('already_set_up');
        return GatePrepared(
          recoveryKey: null,
          commit: () async {
            // `If-None-Match: *` on the recovery PUT: the second time, it is already there.
            if (recoveryOnServer) throw fail('already_set_up');
            recoveryOnServer = true;
            throw fail('offline');
          },
        );
      }

      final h = gateWith(prepareAccount: prepare);
      h.gate.start();
      await settle();
      expect(h.gate.state, const Locked(LockedKind.offline, false));
      h.gate.retry();
      await settle();
      expect(h.gate.state, const Unlock());
      expect(h.opened, isEmpty);

      // The app was killed in between: the next start finds the account set up.
      final next = gateWith(prepareAccount: prepare);
      next.gate.start();
      await settle();
      expect(next.gate.state, const Unlock());
      expect(next.opened, isEmpty);
    });

    test('a browser that cannot keep the key safely is locked, with no retry', () async {
      final h = gateWith(prepareAccount: () async => throw fail('unsupported_browser'));
      h.gate.start();
      await settle();
      expect(h.gate.state, const Locked(LockedKind.unsupported, false));
      h.gate.retry();
      await settle();
      expect(h.prepares, 1);
    });

    test('unlocking in a browser that cannot keep the key safely locks too', () async {
      final h = gateWith(
        prepareAccount: alreadySetUp,
        unlockWithRecovery: (_) async => throw fail('unsupported_browser'),
      );
      h.gate.start();
      await settle();
      expect(await h.gate.unlock('KEY'), isNull);
      expect(h.gate.state, const Locked(LockedKind.unsupported, false));
    });

    test(
      'a vault closed under the open app checks again: reopens with kept keys, else Unlock',
      () async {
        String? kept = 'kept';
        final h = gateWith(loadLocalKeys: () async => kept, prepareAccount: alreadySetUp);
        h.gate.start();
        await settle();
        expect(h.gate.state.status, 'ready');

        h.gate.closed();
        await settle();
        expect(h.gate.state, const Ready('kept'));
        expect(h.opened, hasLength(2));

        kept = null; // another tab signed out and deleted the vault
        h.gate.closed();
        await settle();
        expect(h.gate.state, const Unlock());
      },
    );

    test('starts once', () async {
      final h = gateWith();
      h.gate
        ..start()
        ..start();
      await settle();
      expect(h.loads, 1);
    });

    group('another account signed in (another tab)', () {
      /// The gate of `me`, whose session now says `signedIn` (null: signed out).
      ({Harness h, List<int> reloads}) changedGate(
        String? Function() signedIn, {
        Future<String?> Function()? loadLocalKeys,
        Future<GatePrepared<String>> Function()? prepareAccount,
        Future<String> Function(String keys, bool fresh)? open,
        Future<String?> Function()? sessionUserId,
      }) {
        final reloads = <int>[];
        final h = gateWith(
          userId: 'me',
          sessionUserId: sessionUserId ?? () async => signedIn(),
          reload: () => reloads.add(1),
          loadLocalKeys: loadLocalKeys,
          prepareAccount: prepareAccount,
          open: open,
        );
        return (h: h, reloads: reloads);
      }

      test('a vault closed under the app reloads it when the signed-in account changed', () async {
        String? who = 'me';
        final (:h, :reloads) = changedGate(() => who, loadLocalKeys: () async => 'kept');
        h.gate.start();
        await settle();
        expect(h.gate.state.status, 'ready');
        who = 'someone-else';
        h.gate.closed();
        await settle();
        expect(reloads, hasLength(1));
        expect(h.loads, 1);
        expect(h.opened, hasLength(1));
        expect(h.gate.state.status, 'checking');
      });

      test('signed out in another tab: reloads too (the layout sends to sign-in)', () async {
        String? who = 'me';
        final (:h, :reloads) = changedGate(() => who, loadLocalKeys: () async => 'kept');
        h.gate.start();
        await settle();
        who = null;
        h.gate.closed();
        await settle();
        expect(reloads, hasLength(1));
      });

      test('never prepares an account for the old id', () async {
        final (:h, :reloads) = changedGate(() => 'someone-else');
        h.gate.start();
        await settle();
        expect(reloads, hasLength(1));
        expect(h.prepares, 0);
      });

      test('never unlocks for the old id', () async {
        var who = 'me';
        final (:h, :reloads) = changedGate(() => who, prepareAccount: alreadySetUp);
        h.gate.start();
        await settle();
        expect(h.gate.state, const Unlock());
        who = 'someone-else';
        expect(await h.gate.unlock('KEY'), isNull);
        expect(reloads, hasLength(1));
        expect(h.unlocked, isEmpty);
      });

      test('a sync that says session_changed reloads when the id differs', () async {
        var who = 'me';
        final (:h, :reloads) = changedGate(() => who, loadLocalKeys: () async => 'kept');
        h.gate.start();
        await settle();
        who = 'someone-else';
        h.gate.sessionChanged();
        await settle();
        expect(reloads, hasLength(1));
      });

      test('an open or a keys call refused with session_changed reloads too', () async {
        var who = 'me';
        final (:h, :reloads) = changedGate(
          () => who,
          loadLocalKeys: () async => 'kept',
          open: (_, _) async {
            who = 'someone-else';
            throw fail('session_changed');
          },
        );
        h.gate.start();
        await settle();
        expect(reloads, hasLength(1));
      });

      test('session_changed while the same account is signed in locks, without looping', () async {
        final (:h, :reloads) = changedGate(
          () => 'me',
          loadLocalKeys: () async => 'kept',
          open: (_, _) async => throw fail('session_changed'),
        );
        h.gate.start();
        await settle();
        expect(reloads, isEmpty);
        expect(h.opened, hasLength(1));
        expect(h.gate.state, const Locked(LockedKind.error, false));
      });

      test('cannot tell who is signed in (offline): goes on as before', () async {
        final (:h, :reloads) = changedGate(
          () => 'me',
          sessionUserId: () async => throw fail('offline'),
          loadLocalKeys: () async => 'kept',
        );
        h.gate.start();
        await settle();
        h.gate.closed();
        await settle();
        expect(reloads, isEmpty);
        expect(h.opened, hasLength(2));
      });
    });

    group('passkeys', () {
      PasskeyPrf stash() =>
          PasskeyPrf(credentialId: 'cred-1', prf: Uint8List(32)..fillRange(0, 32, 7));

      test('a stashed sign-in PRF that opens a wrap unlocks without showing Unlock', () async {
        final kept = stash();
        final tried = <String>[];
        final h = gateWith(
          prepareAccount: alreadySetUp,
          takeSignInPrf: () => kept,
          unlockWithPasskey: (passkey) async {
            tried.add(passkey.credentialId);
            return 'passkey';
          },
        );
        h.gate.start();
        await settle();
        expect(tried, ['cred-1']);
        expect(h.opened, [('passkey', true)]);
        expect(h.gate.state, const Ready('passkey'));
        expect(h.seen, isNot(contains('unlock')));
        // Used, then zeroed.
        expect(zeroed(kept.prf), isTrue);
      });

      test('one that opens nothing shows Unlock, and after a recovery unlock the wrap for that '
          'credential is added', () async {
        final kept = stash();
        var wraps = 0;
        final h = gateWith(
          prepareAccount: alreadySetUp,
          takeSignInPrf: () => kept,
          unlockWithPasskey: (_) async => throw fail('no_passkey_wrap'),
          addPasskeyWrap: (passkey) async {
            wraps += 1;
            expect(passkey.credentialId, 'cred-1');
            expect(passkey.prf, Uint8List(32)..fillRange(0, 32, 7));
          },
        );
        h.gate.start();
        await settle();
        expect(h.gate.state, const Unlock());
        expect(wraps, 0);

        expect(await h.gate.unlock('ABCD'), isNull);
        expect(h.unlocked, ['ABCD']);
        expect(wraps, 1);
        expect(h.gate.state, const Ready('unlocked'));
        expect(zeroed(kept.prf), isTrue);
      });

      test('a wrap that fails to save still opens the vault', () async {
        final h = gateWith(
          prepareAccount: alreadySetUp,
          takeSignInPrf: stash,
          unlockWithPasskey: (_) async => throw fail('no_passkey_wrap'),
          addPasskeyWrap: (_) async => throw fail('offline'),
        );
        h.gate.start();
        await settle();
        await h.gate.unlock('ABCD');
        expect(h.gate.state, const Ready('unlocked'));
      });

      test('dispose zeroes a pending PRF and tells nobody again (phone only)', () async {
        final kept = stash();
        final h = gateWith(
          prepareAccount: alreadySetUp,
          takeSignInPrf: () => kept,
          unlockWithPasskey: (_) async => throw fail('no_passkey_wrap'),
        );
        h.gate.start();
        await settle();
        expect(h.gate.state, const Unlock());
        expect(zeroed(kept.prf), isFalse);
        final seen = h.seen.length;
        h.gate.dispose();
        expect(zeroed(kept.prf), isTrue);
        expect(h.gate.disposed, isTrue);
        await h.gate.unlock('ABCD');
        expect(h.seen, hasLength(seen));
      });

      test('no stash shows Unlock', () async {
        var tries = 0;
        final h = gateWith(
          prepareAccount: alreadySetUp,
          takeSignInPrf: () => null,
          unlockWithPasskey: (_) async {
            tries += 1;
            return 'passkey';
          },
        );
        h.gate.start();
        await settle();
        expect(h.gate.state, const Unlock());
        expect(tries, 0);
      });

      test("a new account adds the stashed passkey's wrap after setup", () async {
        final wrapped = <String>[];
        final h = gateWith(
          takeSignInPrf: stash,
          addPasskeyWrap: (passkey) async => wrapped.add(passkey.credentialId),
        );
        h.gate.start();
        await settle();
        await h.gate.confirmSetup();
        expect(wrapped, ['cred-1']);
        expect(h.gate.state, const Ready('new'));
      });

      test('a known browser zeroes the stash and opens', () async {
        final kept = stash();
        final h = gateWith(loadLocalKeys: () async => 'kept', takeSignInPrf: () => kept);
        h.gate.start();
        await settle();
        expect(h.gate.state, const Ready('kept'));
        expect(zeroed(kept.prf), isTrue);
      });

      test("Use a passkey: the touch's PRF opens the vault", () async {
        final touched = stash();
        final h = gateWith(
          prepareAccount: alreadySetUp,
          evaluatePrf: (_) async => touched,
          unlockWithPasskey: (_) async => 'touched',
        );
        h.gate.start();
        await settle();
        expect(await h.gate.unlockWithPasskey(), isNull);
        expect(h.gate.state, const Ready('touched'));
        expect(zeroed(touched.prf), isTrue);
      });

      test(
        'Use a passkey: cancelled stays on Unlock; no_prf and no_passkey_wrap are shown',
        () async {
          final touches = inTurn<PasskeyPrf?>([() => null, () => throw fail('no_prf'), stash]);
          final h = gateWith(
            prepareAccount: alreadySetUp,
            evaluatePrf: (_) => touches(),
            unlockWithPasskey: (_) async => throw fail('no_passkey_wrap'),
          );
          h.gate.start();
          await settle();
          expect(await h.gate.unlockWithPasskey(), isNull);
          expect(h.gate.state, const Unlock());
          expect(await h.gate.unlockWithPasskey(), 'no_prf');
          expect(await h.gate.unlockWithPasskey(), 'no_passkey_wrap');
          expect(h.gate.state, const Unlock());
        },
      );

      test("a pending credential that is not the account's gets no wrap, is zeroed, and the vault "
          'opens', () async {
        final kept = stash();
        var wraps = 0;
        final h = gateWith(
          prepareAccount: alreadySetUp,
          takeSignInPrf: () => kept,
          unlockWithPasskey: (_) async => throw fail('no_passkey_wrap'),
          addPasskeyWrap: (_) async {
            wraps += 1;
            throw fail('unknown_passkey');
          },
        );
        h.gate.start();
        await settle();
        await h.gate.unlock('ABCD');
        expect(wraps, 1);
        expect(zeroed(kept.prf), isTrue);
        expect(h.gate.state, const Ready('unlocked'));
      });

      test('the stash is zeroed when another account is signed in now', () async {
        final kept = stash();
        final reloads = <int>[];
        var tries = 0;
        final h = gateWith(
          prepareAccount: alreadySetUp,
          userId: 'me',
          sessionUserId: () async => 'someone-else',
          reload: () => reloads.add(1),
          takeSignInPrf: () => kept,
          unlockWithPasskey: (_) async {
            tries += 1;
            return 'passkey';
          },
        );
        h.gate.start();
        await settle();
        expect(reloads, isNotEmpty);
        expect(tries, 0);
        expect(zeroed(kept.prf), isTrue);
      });

      test("Use a passkey offers only the account's passkeys", () async {
        final asked = <List<String>?>[];
        final h = gateWith(
          prepareAccount: alreadySetUp,
          accountPasskeyIds: () async => ['cred-1', 'cred-2'],
          evaluatePrf: (ids) async {
            asked.add(ids);
            return null;
          },
        );
        h.gate.start();
        await settle();
        await h.gate.unlockWithPasskey();
        expect(asked, [
          ['cred-1', 'cred-2'],
        ]);
      });

      test(
        'Use a passkey on an account without passkeys is no_passkey_wrap, with no touch',
        () async {
          var touches = 0;
          final h = gateWith(
            prepareAccount: alreadySetUp,
            accountPasskeyIds: () async => [],
            evaluatePrf: (_) async {
              touches += 1;
              return null;
            },
          );
          h.gate.start();
          await settle();
          expect(await h.gate.unlockWithPasskey(), 'no_passkey_wrap');
          expect(touches, 0);
        },
      );

      test(
        "Use a passkey with an unreadable list still asks (the server checks the wrap's ref)",
        () async {
          final asked = <List<String>?>[];
          final h = gateWith(
            prepareAccount: alreadySetUp,
            accountPasskeyIds: () async => throw fail('offline'),
            evaluatePrf: (ids) async {
              asked.add(ids);
              return null;
            },
          );
          h.gate.start();
          await settle();
          await h.gate.unlockWithPasskey();
          expect(asked, [null]);
        },
      );
    });

    group('pairing', () {
      test('pairing -> open after finish(), as a fresh unlock (the pending passkey gets its '
          'wrap)', () async {
        final pairing = FakePairing();
        var wraps = 0;
        final h = gateWith(
          prepareAccount: alreadySetUp,
          takeSignInPrf: () =>
              PasskeyPrf(credentialId: 'cred-1', prf: Uint8List(32)..fillRange(0, 32, 7)),
          unlockWithPasskey: (_) async => throw fail('no_passkey_wrap'),
          addPasskeyWrap: (_) async => wraps += 1,
          startPairing: () async => pairing,
        );
        h.gate.start();
        await settle();
        expect(h.gate.state, const Unlock());

        await h.gate.pair();
        expect(h.gate.state, const Pairing(PairingFrom.unlock));
        expect(await h.gate.startPairing(), same(pairing));
        await settle();
        expect(h.opened, isEmpty);

        pairing.finishing.complete('paired');
        await settle();
        expect(wraps, 1);
        expect(h.lastOpen, ('paired', true));
        expect(h.gate.state, const Ready('paired'));
        // a finished pairing is not cancelled behind its own back
        expect(pairing.cancels, 0);
      });

      test('back cancels the pairing and shows Unlock; starting again cancels the previous '
          'one', () async {
        final first = FakePairing('p-1');
        final second = FakePairing('p-2');
        final queue = [first, second];
        final h = gateWith(
          prepareAccount: alreadySetUp,
          startPairing: () async => queue.removeAt(0),
        );
        h.gate.start();
        await settle();
        await h.gate.pair();
        await h.gate.startPairing();
        await h.gate.startPairing();
        expect(first.cancels, 1);
        expect(second.cancels, 0);

        h.gate.leavePairing();
        expect(second.cancels, 1);
        expect(h.gate.state, const Unlock());
      });

      test('the latest startPairing wins: an older call resolving last cancels its own '
          'request', () async {
        final first = FakePairing('p-1');
        final second = FakePairing('p-2');
        final firstReady = Completer<GatePairing<String>>();
        final secondReady = Completer<GatePairing<String>>();
        final queue = [firstReady, secondReady];
        final h = gateWith(
          prepareAccount: alreadySetUp,
          startPairing: () => queue.removeAt(0).future,
        );
        h.gate.start();
        await settle();
        await h.gate.pair();
        // A quick "Start again": two calls in flight.
        final a = h.gate.startPairing();
        final b = h.gate.startPairing();
        unawaited(a.then((_) {}, onError: (_) {}));
        secondReady.complete(second);
        expect(await b, same(second));
        firstReady.complete(first);
        await expectLater(a, throwsA(isA<GateError>().having((e) => e.code, 'code', 'cancelled')));
        expect(first.cancels, greaterThan(0));
        expect(second.cancels, 0);

        second.finishing.complete('second');
        await settle();
        expect(h.lastOpen, ('second', true));
        expect(h.gate.state, const Ready('second'));
      });

      test('a pairing that fails stays on the pairing screen, which shows why', () async {
        final pairing = FakePairing();
        final h = gateWith(prepareAccount: alreadySetUp, startPairing: () async => pairing);
        h.gate.start();
        await settle();
        await h.gate.pair();
        await h.gate.startPairing();
        pairing.finishing.completeError(fail('tampered'));
        await settle();
        expect(h.opened, isEmpty);
        expect(h.gate.state, const Pairing(PairingFrom.unlock));
      });

      test('a finish refused with session_changed reloads for the account signed in now', () async {
        var reloads = 0;
        var who = 'me';
        final pairing = FakePairing();
        final h = gateWith(
          prepareAccount: alreadySetUp,
          userId: 'me',
          sessionUserId: () async => who,
          reload: () => reloads += 1,
          startPairing: () async => pairing,
        );
        h.gate.start();
        await settle();
        await h.gate.pair();
        await h.gate.startPairing();
        who = 'someone-else';
        pairing.finishing.completeError(fail('session_changed'));
        await settle();
        expect(reloads, 1);
      });

      test('a cancelled pairing is not opened when its finish resolves late', () async {
        final pairing = FakePairing();
        final h = gateWith(prepareAccount: alreadySetUp, startPairing: () async => pairing);
        h.gate.start();
        await settle();
        await h.gate.pair();
        await h.gate.startPairing();
        h.gate.leavePairing();
        pairing.finishing.complete('late');
        await settle();
        expect(h.opened, isEmpty);
        expect(h.gate.state, const Unlock());
      });

      test('disposing the gate cancels the pairing in progress', () async {
        final pairing = FakePairing();
        final h = gateWith(prepareAccount: alreadySetUp, startPairing: () async => pairing);
        h.gate.start();
        await settle();
        await h.gate.pair();
        await h.gate.startPairing();
        h.gate.dispose();
        expect(pairing.cancels, 1);
      });

      test('pair() does nothing outside Unlock', () async {
        final h = gateWith(
          loadLocalKeys: () async => 'kept',
          startPairing: () async => FakePairing(),
        );
        h.gate.start();
        await settle();
        await h.gate.pair();
        expect(h.gate.state, const Ready('kept'));
      });

      test('without a startPairing dependency pair() does nothing', () async {
        final h = gateWith(prepareAccount: alreadySetUp);
        h.gate.start();
        await settle();
        await h.gate.pair();
        expect(h.gate.state, const Unlock());
      });

      test('the notice stays through a failed unlock and goes with a new screen', () async {
        final h = gateWith(
          loadLocalKeys: () async => 'kept',
          unlockWithRecovery: (_) async => throw fail('wrong_recovery_key'),
          startPairing: () async => FakePairing(),
        );
        h.gate.start();
        await settle();
        h.gate.removed();
        expect(await h.gate.unlock('nope'), 'wrong_recovery_key');
        expect(h.gate.state, const Unlock(notice: Unlock.removed));
        await h.gate.pair();
        h.gate.leavePairing();
        expect(h.gate.state, const Unlock());
      });
    });

    group('a removed browser', () {
      test('removed() from the open app shows Unlock with the removed notice', () async {
        final h = gateWith(loadLocalKeys: () async => 'kept');
        h.gate.start();
        await settle();
        h.gate.removed();
        expect(h.gate.state, const Unlock(notice: Unlock.removed));
        // the vault is gone already: nothing is opened or made again
        expect(h.prepares, 0);
        expect(h.opened, hasLength(1));
      });

      test('the notice stays through a failed unlock', () async {
        final h = gateWith(
          loadLocalKeys: () async => 'kept',
          unlockWithRecovery: (_) async => throw fail('wrong_recovery_key'),
        );
        h.gate.start();
        await settle();
        h.gate.removed();
        expect(await h.gate.unlock('nope'), 'wrong_recovery_key');
        expect(h.gate.state, const Unlock(notice: Unlock.removed));
      });

      test('a removed anonymous phone shows Unlock(removed)', () async {
        // An anonymous account's phone, set up with no key shown, then removed from the account.
        final h = gateWith(
          prepareAccount: () async => GatePrepared(recoveryKey: null, commit: () async => 'anon'),
        );
        h.gate.start();
        await settle();
        expect(h.gate.state, const Ready('anon'));
        h.gate.removed();
        expect(h.gate.state, const Unlock(notice: Unlock.removed));
      });

      test('a browser removed while closed opens to Unlock with the removed notice', () async {
        final h = gateWith(
          loadLocalKeys: () async => 'kept',
          open: (_, _) async => throw fail('device_removed'),
        );
        h.gate.start();
        await settle();
        expect(h.gate.state, const Unlock(notice: Unlock.removed));
        expect(h.prepares, 0);
      });

      test('removed() outside the open app does nothing', () async {
        final h = gateWith(prepareAccount: alreadySetUp);
        h.gate.start();
        await settle();
        h.gate.removed();
        expect(h.gate.state, const Unlock());
      });
    });

    group('a new key version this browser cannot verify', () {
      test('unverified() from the open app shows Unlock with the unverified notice', () async {
        final h = gateWith(loadLocalKeys: () async => 'kept');
        h.gate.start();
        await settle();
        h.gate.unverified();
        expect(h.gate.state, const Unlock(notice: Unlock.unverified));
        expect(h.prepares, 0);
        expect(h.opened, hasLength(1));
      });

      test('an opening that fails with key_unverified shows Unlock with the notice', () async {
        Future<String> open(String _, bool _) async => throw fail('key_unverified');
        final h = gateWith(loadLocalKeys: () async => 'kept', open: open);
        h.gate.start();
        await settle();
        expect(h.gate.state, const Unlock(notice: Unlock.unverified));
        expect(h.prepares, 0);
      });

      test('the recovery key from unverified unlocks the kept vault and opens it fresh', () async {
        final h = gateWith(loadLocalKeys: () async => 'kept');
        h.gate.start();
        await settle();
        h.gate.unverified();
        expect(await h.gate.unlock('ABCD-EFGH'), isNull);
        expect(h.unlocked, ['ABCD-EFGH']);
        expect(h.prepares, 0);
        expect(h.lastOpen, ('unlocked', true));
        expect(h.gate.state, const Ready('unlocked'));
      });

      test('unverified() outside the open app does nothing', () async {
        final h = gateWith(prepareAccount: alreadySetUp);
        h.gate.start();
        await settle();
        h.gate.unverified();
        expect(h.gate.state, const Unlock());
      });
    });

    group('the recovery key held from the sign-in', () {
      Uint8List held() => Uint8List.fromList(List.filled(16, 7));

      test('a held recovery key opens a known account\'s wrap on a new phone', () async {
        final secret = held();
        var takes = 0;
        final tried = <List<int>>[];
        final h = gateWith(
          prepareAccount: alreadySetUp,
          takeSignInRecoverySecret: () {
            takes += 1;
            return takes == 1 ? secret : null;
          },
          unlockWithRecoverySecret: (s) async {
            tried.add(List.of(s));
            return 'from-key';
          },
        );
        h.gate.start();
        await settle();
        expect(tried, [List.filled(16, 7)]);
        expect(h.seen, isNot(contains('unlock')));
        expect(h.unlocked, isEmpty);
        expect(h.lastOpen, ('from-key', true));
        expect(h.gate.state, const Ready('from-key'));
        // Tried once, then zeroed.
        expect(takes, 1);
        expect(zeroed(secret), isTrue);
      });

      test('a held key that opens nothing shows Unlock with wrong_recovery_key', () async {
        final secret = held();
        final h = gateWith(
          prepareAccount: alreadySetUp,
          takeSignInRecoverySecret: () => secret,
          unlockWithRecoverySecret: (_) async => throw fail('wrong_recovery_key'),
        );
        h.gate.start();
        await settle();
        expect(h.gate.state, const Unlock(error: 'wrong_recovery_key'));
        expect(h.opened, isEmpty);
        expect(zeroed(secret), isTrue);
        // Typing the key on Unlock still works.
        expect(await h.gate.unlock('right'), isNull);
        expect(h.gate.state, const Ready('unlocked'));
      });

      test('a phone that already holds the keys opens them and zeroes the held key', () async {
        final secret = held();
        var tries = 0;
        final h = gateWith(
          loadLocalKeys: () async => 'kept',
          takeSignInRecoverySecret: () => secret,
          unlockWithRecoverySecret: (_) async {
            tries += 1;
            return 'from-key';
          },
        );
        h.gate.start();
        await settle();
        expect(h.gate.state, const Ready('kept'));
        expect(tries, 0);
        expect(zeroed(secret), isTrue);
      });
    });
  });

  group('what can open the data here', () {
    PasskeyPrf stash() =>
        PasskeyPrf(credentialId: 'cred-1', prf: Uint8List(32)..fillRange(0, 32, 7));

    test('the unlock state carries the hint and the wrap', () async {
      final h = gateWith(
        prepareAccount: alreadySetUp,
        passkeyGaveNoPrf: () async => true,
        hasPasskeyWrap: () async => false,
      );
      h.gate.start();
      await settle();
      expect(h.gate.state, const Unlock(noPrfHere: true, passkeyWrap: false));
    });

    test('the notices carry the means too', () async {
      final h = gateWith(
        loadLocalKeys: () async => 'kept',
        passkeyGaveNoPrf: () async => true,
        hasPasskeyWrap: () async => false,
      );
      h.gate.start();
      await settle();
      await h.gate.removed();
      expect(
        h.gate.state,
        const Unlock(notice: Unlock.removed, noPrfHere: true, passkeyWrap: false),
      );
    });

    test('an unreadable wraps list counts as a passkey wrap', () async {
      final h = gateWith(
        prepareAccount: alreadySetUp,
        passkeyGaveNoPrf: () async => throw StateError('storage'),
        hasPasskeyWrap: () async => throw fail('offline'),
      );
      h.gate.start();
      await settle();
      expect(h.gate.state, const Unlock());
      expect(h.gate.state, const Unlock(noPrfHere: false, passkeyWrap: true));
    });

    test('a passkey touch without PRF notes the hint', () async {
      var noted = 0;
      final h = gateWith(
        prepareAccount: alreadySetUp,
        accountPasskeyIds: () async => ['cred-1'],
        evaluatePrf: (_) async => throw fail('no_prf'),
        notePasskeyWithoutPrf: () async => noted += 1,
      );
      h.gate.start();
      await settle();
      expect(await h.gate.unlockWithPasskey(), 'no_prf');
      expect(noted, 1);
      // The layout under the person's hands does not jump; the next Unlock reads the hint.
      expect(h.gate.state, const Unlock());
    });

    test("a touch without PRF notes nothing when the account's passkeys are not known (it may be "
        "another account's passkey)", () async {
      var noted = 0;
      final h = gateWith(
        prepareAccount: alreadySetUp,
        accountPasskeyIds: () async => throw fail('passkeys_unavailable'),
        evaluatePrf: (_) async => throw fail('no_prf'),
        notePasskeyWithoutPrf: () async => noted += 1,
      );
      h.gate.start();
      await settle();
      expect(await h.gate.unlockWithPasskey(), 'no_prf');
      expect(noted, 0);
    });

    test('a passkey that opens the data clears the hint', () async {
      var viaButton = 0;
      final a = gateWith(
        prepareAccount: alreadySetUp,
        evaluatePrf: (_) async => stash(),
        unlockWithPasskey: (_) async => 'passkey',
        notePasskeyOpened: () async => viaButton += 1,
      );
      a.gate.start();
      await settle();
      await a.gate.unlockWithPasskey();
      expect(viaButton, 1);

      var viaSignIn = 0;
      final b = gateWith(
        prepareAccount: alreadySetUp,
        takeSignInPrf: stash,
        unlockWithPasskey: (_) async => 'passkey',
        notePasskeyOpened: () async => viaSignIn += 1,
      );
      b.gate.start();
      await settle();
      expect(viaSignIn, 1);
      expect(b.gate.state, const Ready('passkey'));
    });

    test('a passkey that opens nothing does not clear the hint', () async {
      var opened = 0;
      final h = gateWith(
        prepareAccount: alreadySetUp,
        takeSignInPrf: stash,
        unlockWithPasskey: (_) async => throw fail('no_passkey_wrap'),
        notePasskeyOpened: () async => opened += 1,
      );
      h.gate.start();
      await settle();
      expect(opened, 0);
      expect(h.gate.state, const Unlock());
    });

    test(
      "the sign-in's PRF of another account is zeroed and no hint is written for this one",
      () async {
        final kept = stash();
        var noted = 0;
        var opened = 0;
        final h = gateWith(
          prepareAccount: alreadySetUp,
          userId: 'me',
          sessionUserId: () async => 'someone-else',
          reload: () {},
          takeSignInPrf: () => kept,
          notePasskeyWithoutPrf: () async => noted += 1,
          notePasskeyOpened: () async => opened += 1,
        );
        h.gate.start();
        await settle();
        expect(zeroed(kept.prf), isTrue);
        expect(noted, 0);
        expect(opened, 0);
      },
    );

    test('back to Unlock from an open vault, Unlock shows at once with the last known means, '
        'then what is read now', () async {
      final wrapRead = Completer<bool>();
      var reads = 0;
      final h = gateWith(
        prepareAccount: alreadySetUp,
        passkeyGaveNoPrf: () async => true,
        hasPasskeyWrap: () {
          reads += 1;
          return reads == 1 ? Future.value(false) : wrapRead.future;
        },
        evaluatePrf: (_) async => stash(),
        unlockWithPasskey: (_) async => 'passkey',
      );
      h.gate.start();
      await settle();
      await h.gate.unlockWithPasskey();
      expect(h.gate.state, const Ready('passkey'));

      final removing = h.gate.removed();
      // Never "ready" while the wraps are read: Unlock at once, with what was known.
      expect(
        h.gate.state,
        const Unlock(notice: Unlock.removed, noPrfHere: true, passkeyWrap: false),
      );
      wrapRead.complete(true);
      await removing;
      expect(
        h.gate.state,
        const Unlock(notice: Unlock.removed, noPrfHere: true, passkeyWrap: true),
      );
    });

    test('a late wraps read never overwrites a newer state', () async {
      final wrapRead = Completer<bool>();
      var reads = 0;
      final h = gateWith(
        prepareAccount: alreadySetUp,
        hasPasskeyWrap: () {
          reads += 1;
          return reads == 1 ? Future.value(true) : wrapRead.future;
        },
        evaluatePrf: (_) async => stash(),
        unlockWithPasskey: (_) async => 'passkey',
        startPairing: () async => FakePairing(),
      );
      h.gate.start();
      await settle();
      await h.gate.unlockWithPasskey();
      final removing = h.gate.unverified();
      await h.gate.pair();
      expect(h.gate.state, const Pairing<String>(PairingFrom.unlock));
      wrapRead.complete(false);
      await removing;
      expect(h.gate.state, const Pairing<String>(PairingFrom.unlock));
    });
  });
}
