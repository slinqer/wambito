// Port of apps/web/app/features/vault/vault-gate.test.ts, without the pairing cases (stage 3b),
// plus a guest that crashed half-way through its setup.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/local/keys_error.dart';
import 'package:wambito/local/prf.dart';
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
  bool guest = false,
  String? userId,
  Future<String?> Function()? sessionUserId,
  void Function()? reload,
  PasskeyPrf? Function()? takeSignInPrf,
  Future<String> Function(PasskeyPrf passkey)? unlockWithPasskey,
  Future<void> Function(PasskeyPrf passkey)? addPasskeyWrap,
  Future<PasskeyPrf?> Function(List<String>? credentialIds)? evaluatePrf,
  Future<List<String>> Function()? accountPasskeyIds,
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
      guest: guest,
      userId: userId,
      sessionUserId: sessionUserId,
      reload: reload,
      takeSignInPrf: takeSignInPrf,
      unlockWithPasskey: unlockWithPasskey,
      addPasskeyWrap: addPasskeyWrap,
      evaluatePrf: evaluatePrf,
      accountPasskeyIds: accountPasskeyIds,
    ),
  );
  h.gate.subscribe(() => h.seen.add(h.gate.state.status));
  return h;
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

    test('a guest commits at once: there is no key to show', () async {
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

    test(
      'a guest whose account has keys elsewhere is locked out here: no recovery key to type',
      () async {
        final h = gateWith(guest: true, prepareAccount: alreadySetUp);
        h.gate.start();
        await settle();
        expect(h.gate.state, const Locked(LockedKind.guest, false));
        h.gate.retry();
        await settle();
        expect(h.gate.state, const Locked(LockedKind.guest, false));
        expect(h.unlocked, isEmpty);
      },
    );

    test('a guest that loses the setup race is locked out too', () async {
      final h = gateWith(
        guest: true,
        prepareAccount: () async =>
            GatePrepared(recoveryKey: null, commit: () async => throw fail('already_set_up')),
      );
      h.gate.start();
      await settle();
      expect(h.gate.state, const Locked(LockedKind.guest, false));
    });

    test('a guest that crashed between the recovery PUT and the device PUT is locked out, on the '
        'retry and on the next start', () async {
      // The recovery wrap reached the server, the device wrap did not: the account has a wrap
      // nobody here can open, and a guest has no recovery key to type.
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

      final h = gateWith(guest: true, prepareAccount: prepare);
      h.gate.start();
      await settle();
      expect(h.gate.state, const Locked(LockedKind.offline, false));
      h.gate.retry();
      await settle();
      expect(h.gate.state, const Locked(LockedKind.guest, false));
      expect(h.opened, isEmpty);

      // The app was killed in between: the next start finds the account set up.
      final next = gateWith(guest: true, prepareAccount: prepare);
      next.gate.start();
      await settle();
      expect(next.gate.state, const Locked(LockedKind.guest, false));
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

      test('a removed guest is locked out: it has no recovery key to type', () async {
        final h = gateWith(loadLocalKeys: () async => 'kept', guest: true);
        h.gate.start();
        await settle();
        h.gate.removed();
        expect(h.gate.state, const Locked(LockedKind.guest, false));
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

      test('a guest removed while closed is Locked guest', () async {
        final h = gateWith(
          loadLocalKeys: () async => 'kept',
          open: (_, _) async => throw fail('device_removed'),
          guest: true,
        );
        h.gate.start();
        await settle();
        expect(h.gate.state, const Locked(LockedKind.guest, false));
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

      test('an unverified guest goes to its Locked', () async {
        final h = gateWith(loadLocalKeys: () async => 'kept', guest: true);
        h.gate.start();
        await settle();
        h.gate.unverified();
        expect(h.gate.state, const Locked(LockedKind.guest, false));
      });

      test('an opening that fails with key_unverified shows Unlock with the notice; a guest its '
          'Locked', () async {
        Future<String> open(String _, bool _) async => throw fail('key_unverified');
        final h = gateWith(loadLocalKeys: () async => 'kept', open: open);
        h.gate.start();
        await settle();
        expect(h.gate.state, const Unlock(notice: Unlock.unverified));
        expect(h.prepares, 0);
        final guest = gateWith(loadLocalKeys: () async => 'kept', open: open, guest: true);
        guest.gate.start();
        await settle();
        expect(guest.gate.state, const Locked(LockedKind.guest, false));
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
  });
}
