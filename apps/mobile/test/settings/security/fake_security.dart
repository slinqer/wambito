import 'package:dio/dio.dart';
import 'package:wambito/local/key_storage.dart';
import 'package:wambito/local/keys.dart' show KeysOptions, WrapDto;
import 'package:wambito/local/keys_error.dart';
import 'package:wambito/local/pairing.dart' show ApproverPairing;
import 'package:wambito/local/prf.dart' show PasskeyPrf;
import 'package:wambito/local/rotate.dart';
import 'package:wambito/local/signin_approval.dart' show SigninApproval;
import 'package:wambito/security/screen_lock.dart';
import 'package:wambito/settings/security/security_api.dart';

const recoveryKeyText = 'ABCD-EFGH-JKMN-PQRS-TUVW-XYZ2-345';

WrapDto wrapOf(String id, String kind, {String? ref, String? label, String? createdAt}) => WrapDto(
  id: id,
  kind: kind,
  ref: ref,
  keyV: 2,
  wrapped: 'w',
  label: label,
  createdAt: createdAt ?? '2026-10-01T10:00:00.000Z',
);

const ownId = '01930000-0000-7000-8000-00000000000a';
const laptopId = '01930000-0000-7000-8000-00000000000b';
const forgedId = '01930000-0000-7000-8000-00000000000c';

SecuritySnapshot snapshotOf({int unreadable = 0, bool passkeyWrap = false}) => SecuritySnapshot(
  wraps: [
    wrapOf('r', 'recovery'),
    wrapOf(ownId, 'device', label: 'Pixel 9', createdAt: '2026-10-02T10:00:00Z'),
    wrapOf(laptopId, 'device', label: 'Firefox on Linux', createdAt: '2026-10-03T10:00:00Z'),
    wrapOf(forgedId, 'device', label: 'Safari on iOS', createdAt: '2026-10-04T10:00:00Z'),
    if (passkeyWrap) wrapOf('p1', 'passkey', ref: 'cred-1'),
  ],
  ownId: ownId,
  revoked: const [],
  verified: {laptopId},
  unreadable: unreadable,
);

class FakeApprover implements ApproverPairing {
  @override
  Future<String> number() => Future<String>.value('123456');

  @override
  Future<void> approve() async {}

  @override
  void cancel() {}
}

/// A [SecurityApi] that records what it was asked, with failures to hand out.
class FakeSecurity implements SecurityApi {
  FakeSecurity([SecuritySnapshot? snapshot]) : snapshot = snapshot ?? snapshotOf();

  SecuritySnapshot snapshot;
  final calls = <String>[];
  int loads = 0;
  int forgets = 0;
  Object? loadFailure;
  Object? rotateFailure;
  Object? newKeyFailure;

  /// What each commit throws, in turn (null: succeeds).
  final commitFailures = <Object?>[];
  var dropped = <DroppedWrap>[];

  @override
  KeysOptions get pairing => KeysOptions(userId: 'u1', dio: Dio(), storage: KeyStorage());

  @override
  Future<SecuritySnapshot> load() async {
    loads += 1;
    final failure = loadFailure;
    if (failure != null) throw failure;
    return snapshot;
  }

  @override
  Future<PreparedRotation> rotate({
    required List<String> remove,
    required RotateRecovery recovery,
    PasskeyPrf? passkey,
  }) async {
    final kind = switch (recovery) {
      TypedRecovery(:final text) => 'typed:$text',
      FreshRecovery() => 'fresh',
    };
    calls.add('rotate remove=${remove.join(',')} $kind');
    final failure = rotateFailure;
    if (failure != null) throw failure;
    // as the library: once a commit was attempted, forget() is a no-op (R17)
    var attempted = false;
    var refused = false;
    return PreparedRotation(
      recoveryKey: recovery is FreshRecovery ? recoveryKeyText : null,
      refusedForGood: () => refused,
      commit: () async {
        attempted = true;
        calls.add('commit');
        if (commitFailures.isNotEmpty) {
          final failure = commitFailures.removeAt(0);
          // as the library: these two are latched, every retry says the same
          if (failure is KeysError &&
              (failure.code == 'tampered' || failure.code == 'rotated_elsewhere')) {
            refused = true;
          }
          if (failure != null) throw failure;
        }
        return RotateResult(keyV: 3, dropped: dropped);
      },
      forget: () {
        if (attempted) return;
        forgets += 1;
        calls.add('forget');
      },
    );
  }

  Object? removeFailure;

  @override
  Future<void> removeDevice(String id) async {
    calls.add('removeDevice $id');
    final failure = removeFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<void> checkRecoveryKey(String text) async {
    calls.add('check $text');
  }

  @override
  Future<NewRecoveryKey> newRecoveryKey() async {
    calls.add('newRecoveryKey');
    final failure = newKeyFailure;
    if (failure != null) throw failure;
    var attempted = false;
    return NewRecoveryKey(
      recoveryKey: recoveryKeyText,
      commit: () async {
        attempted = true;
        calls.add('commit');
        if (commitFailures.isNotEmpty) {
          final failure = commitFailures.removeAt(0);
          if (failure != null) throw failure;
        }
      },
      forget: () {
        if (attempted) return;
        forgets += 1;
        calls.add('forget');
      },
    );
  }

  @override
  Future<void> reloadKeys() async {
    calls.add('reloadKeys');
  }

  PasskeyPrf? touched;
  Object? touchFailure;

  @override
  Future<PasskeyPrf?> evaluatePrf(List<String>? credentialIds) async {
    calls.add('evaluatePrf ${credentialIds?.join(',')}');
    final failure = touchFailure;
    if (failure != null) throw failure;
    return touched;
  }

  Object? wrapFailure;

  @override
  Future<void> addPasskeyWrap(PasskeyPrf passkey) async {
    calls.add('addPasskeyWrap ${passkey.credentialId}');
    final failure = wrapFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<ApproverPairing> findPairing({String? code, String? qr}) async {
    calls.add('findPairing code=$code qr=$qr');
    return FakeApprover();
  }

  /// What [findSigninRequest] hands out; unset, it is a [StateError] (no test asked for it).
  Future<SigninApproval> Function({String? code, String? qr, bool fromLink})? findSignin;

  @override
  Future<SigninApproval> findSigninRequest({String? code, String? qr, bool fromLink = false}) {
    calls.add('findSigninRequest code=$code qr=$qr${fromLink ? ' fromLink' : ''}');
    final find = findSignin;
    if (find == null) return Future.error(StateError('no sign-in request'));
    return find(code: code, qr: qr, fromLink: fromLink);
  }
}

/// A screen lock that answers [answer], or waits for [release] when [hold] is set.
class FakeLock implements ScreenLock {
  FakeLock(this.answer);

  LockCheck answer;
  final reasons = <String>[];

  @override
  Future<LockCheck> confirm(String reason) async {
    reasons.add(reason);
    return answer;
  }
}

KeysError keysError(String code) => KeysError(code);
