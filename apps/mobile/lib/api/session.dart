import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../capture_auto/capture_platform.dart';
import '../crypto/recovery.dart' show recoveryVerifier;
import '../home/home_cache.dart';
import '../home/widget_sync.dart';
import '../local/keys.dart' show keysParseRecoveryKey;
import '../offline/pending_saves.dart';
import '../storage/secure_storage.dart';
import 'auth_api.dart';
import 'client.dart';
import 'device.dart';
import 'server_url.dart';
import 'passkey_offer.dart';
import 'passkeys.dart';
import '../vault/encryption_mode.dart'
    show
        EncryptionMode,
        EncryptionStore,
        VaultAccount,
        encryptionStoreProvider,
        freshVaultAccountProvider,
        knownAccountProvider,
        knownPlainProvider,
        vaultAccountProvider,
        vaultOwnerProvider;
import '../vault/finance_guard.dart';
import '../vault/vault_providers.dart'
    show forgetVaultProvider, keyStorageProvider, staleVaultsProvider, vaultSessionProvider;

export 'auth_api.dart' show authApiProvider;
export 'passkeys.dart' show passkeysProvider, passkeysSupportedProvider;

/// The session kept on the phone: the bearer token, whether it belongs to a guest, and whether its
/// account still has the welcome to do.
class StoredSession {
  const StoredSession({
    required this.token,
    required this.guest,
    this.onboardingPending = false,
    this.onboardingKnown = true,
  });

  final String token;

  /// A guest's token is the only way back to their account (it has no email), so the app never
  /// replaces it without asking (spec section 4.2).
  final bool guest;

  /// The account has no `onboardingCompletedAt` yet: wherever it goes, it goes to the welcome first
  /// (the web's `requireOnboarded`). Never a guest's.
  final bool onboardingPending;

  /// Whether the phone knows how the welcome stands for this account (the server said it, or the
  /// person finished it here). A session stored before the app knew of the welcome, or whose profile
  /// could not be read at sign-in, does not: it is asked at the next start, and what must not wait
  /// on that (a widget's link) waits only for these.
  final bool onboardingKnown;
}

/// The session token in `flutter_secure_storage`, which encrypts it with a key kept in the Android
/// Keystore (spec section 6.3).
class SessionStore {
  SessionStore([FlutterSecureStorage storage = appSecureStorage]) : _storage = storage;

  static const tokenKey = 'session.token';
  static const guestKey = 'session.guest';
  static const onboardingKey = 'session.onboarding';

  final FlutterSecureStorage _storage;

  /// The stored session, or null. A token whose guest flag is missing reads as a guest: the safe
  /// side, since the app then asks before replacing it (and /v1/me corrects the flag).
  Future<StoredSession?> read() async {
    try {
      final token = await _storage.read(key: tokenKey);
      if (token == null || token.isEmpty) return null;
      final guest = await _storage.read(key: guestKey) != 'false';
      // Missing is an account that has finished: an older install never had a welcome to do, and
      // the start asks the server.
      final onboarding = await _storage.read(key: onboardingKey);
      return StoredSession(
        token: token,
        guest: guest,
        onboardingPending: !guest && onboarding == 'pending',
        // A guest has no welcome to know about.
        onboardingKnown: guest || onboarding == 'pending' || onboarding == 'done',
      );
    } on PlatformException {
      // The Keystore key is gone (a restored backup, a reset lock screen): nothing usable.
      return null;
    }
  }

  Future<void> write(
    String token, {
    required bool guest,
    bool onboardingPending = false,
    bool onboardingKnown = true,
  }) async {
    // The flags first: a token is never stored next to a stale "not a guest" or "welcome done".
    await _storage.write(key: guestKey, value: guest ? 'true' : 'false');
    if (onboardingPending && !guest) {
      await _storage.write(key: onboardingKey, value: 'pending');
    } else if (onboardingKnown && !guest) {
      await _storage.write(key: onboardingKey, value: 'done');
    } else {
      await _storage.delete(key: onboardingKey);
    }
    await _storage.write(key: tokenKey, value: token);
  }

  Future<void> clear() async {
    await _storage.delete(key: tokenKey);
    await _storage.delete(key: guestKey);
    await _storage.delete(key: onboardingKey);
  }
}

enum SessionStatus { loading, signedOut, signedIn }

/// Where the person stands: still reading the store, signed out, or signed in with [stored].
class SessionState {
  const SessionState._(this.status, this.stored, [this.offerPasskeyFor]);

  static const loading = SessionState._(SessionStatus.loading, null);
  static const signedOut = SessionState._(SessionStatus.signedOut, null);

  const SessionState.signedIn(StoredSession session, {String? offerPasskeyFor})
    : this._(SessionStatus.signedIn, session, offerPasskeyFor);

  final SessionStatus status;
  final StoredSession? stored;

  /// Set right after an email sign-in that is due the passkey offer (web: `shouldOfferPasskey`): the
  /// id of the account to offer a passkey to, until it answers ([SessionController.answerPasskeyOffer]).
  /// Never a guest's: a guest has "Guarda tu progreso".
  final String? offerPasskeyFor;

  bool get isGuest => stored?.guest ?? false;

  /// The signed-in account has the welcome to do (see [StoredSession.onboardingPending]).
  bool get onboardingPending => stored?.onboardingPending ?? false;

  /// The phone knows how the welcome stands for the signed-in account (see
  /// [StoredSession.onboardingKnown]).
  bool get onboardingKnown => stored?.onboardingKnown ?? true;
}

/// A sign-in with another account, or a sign-out, was asked for while a guest is signed in. Going
/// ahead would leave the guest's account unreachable, so the caller must first offer to save the
/// guest's progress (claim the email) or warn, and only then pass `replaceGuest: true` (sign-in)
/// or `discardGuest: true` (sign-out).
class GuestInTheWay implements Exception {
  const GuestInTheWay();
}

/// The sign-in flows (spec sections 4 and 6.1): a guest, an email code or magic link, or a
/// passkey; and the guest's claim of an email. Every token lands in [SessionStore].
class SessionController extends Notifier<SessionState> {
  /// The most a sign-out waits for the server to be told.
  static const signOutWait = Duration(seconds: 10);

  /// Done once the stored session has been read.
  late Future<void> ready;

  /// Done once the stored session has also been checked against the server (`/v1/me`).
  late Future<void> refreshed;

  SessionStore get _store => ref.read(sessionStoreProvider);
  AuthApi get _auth => ref.read(authApiProvider);
  Passkeys get _passkeys => ref.read(passkeysProvider);

  @override
  SessionState build() {
    final restored = _restore();
    ready = restored.then((_) {});
    refreshed = restored.then((stored) async {
      if (stored != null) await _refresh(stored);
    });
    return SessionState.loading;
  }

  Future<StoredSession?> _restore() async {
    // Before the first read: items kept with the old accessibility are rewritten (iOS only).
    await migrateKeychainAccessibility(appSecureStorage, backgroundReadableKeys);
    final stored = await _store.read();
    state = stored == null ? SessionState.signedOut : SessionState.signedIn(stored);
    if (stored == null) unawaited(_sweepSignedOut());
    return stored;
  }

  /// A signed-out start: the vaults of sessions that ended without a sign-out go (the web's
  /// `deleteStaleVaults(null)`), but the one of the account kept last, whose session expired: it
  /// waits for that account's next sign-in ([sessionExpired]). Not waited for; never fails.
  Future<void> _sweepSignedOut() async {
    try {
      final keep = await ref.read(encryptionStoreProvider).keptAccountId();
      if (!ref.mounted) return;
      await ref.read(staleVaultsProvider)(keep);
    } on Object {
      // Left for the next start.
    }
  }

  /// Asks the server who the stored token belongs to: a token it no longer knows signs out; a guest
  /// that has meanwhile claimed an email (or the other way round) gets the right flag, and so does
  /// an account whose welcome was done elsewhere. Offline, the stored session stands.
  Future<void> _refresh(StoredSession stored) async {
    try {
      final standing = await _auth.standing(stored.token);
      if (!ref.mounted || state.stored?.token != stored.token) return;
      // What the server says about the welcome wins over what was kept (another phone, or the web,
      // may have finished it).
      if (standing.guest != stored.guest ||
          standing.onboardingPending != stored.onboardingPending ||
          !stored.onboardingKnown) {
        await _signedIn(
          stored.token,
          guest: standing.guest,
          onboardingPending: standing.onboardingPending,
          userId: standing.userId,
        );
      } else {
        // The server still knows the session: captures kept through a 401 can go now.
        _sendQueuedCaptures(stored.token, standing.userId);
      }
    } on AuthFailure catch (failure) {
      // The vault stays for the account's next sign-in ([sessionExpired]).
      if (failure.status == 401 && state.stored?.token == stored.token) {
        await sessionExpired(token: stored.token);
      }
    }
  }

  Future<void> _signedIn(
    String token, {
    required bool guest,
    bool onboardingPending = false,
    bool onboardingKnown = true,
    String? offerPasskeyFor,
    String? userId,
    String? capturesFrom,
  }) async {
    // Another token is another session (a guest replaced by an email account, say): what the old
    // one left on this phone goes with it. The same token (a claim, a corrected flag) keeps it.
    final previous = state.stored?.token;
    if (previous != null && previous != token) await _forgetWidget();
    await _store.write(
      token,
      guest: guest,
      onboardingPending: onboardingPending,
      onboardingKnown: onboardingKnown,
    );
    // The app was closed while the session was being kept (a start that asked the server late).
    if (!ref.mounted) return;
    state = SessionState.signedIn(
      StoredSession(
        token: token,
        guest: guest,
        onboardingPending: !guest && onboardingPending,
        onboardingKnown: onboardingKnown,
      ),
      offerPasskeyFor: guest ? null : offerPasskeyFor,
    );
    ref.read(widgetSyncProvider).signedIn();
    _sendQueuedCaptures(token, userId, from: capturesFrom);
  }

  /// Tells Android whose the queue of detected captures is now, so it drops another account's and
  /// sends the rest (`sendQueued`, R15): what a 401 kept is sent once its account signs in again.
  /// Asks the server for the account id only when [userId] is not known and there is an Android
  /// side. Not waited for, and a failure (offline) only leaves the queue for the next sign-in or
  /// start: nothing is sent to an account that could not be told.
  ///
  /// [from]: the account whose data this one takes over (a merge, or its cancel): its captures are
  /// re-tagged instead of dropped; [CaptureHandover] keeps it (written before the token) for this
  /// session's later hand-overs, a restart's included, until one went through.
  void _sendQueuedCaptures(String token, String? userId, {String? from}) {
    final platform = ref.read(autoCapturePlatformProvider);
    final handover = ref.read(captureHandoverProvider);
    Future<void> send() async {
      if (await platform.status() == null) return;
      final id = userId ?? await _auth.accountId(token);
      if (!ref.mounted || state.stored?.token != token) return;
      final carried = from ?? await handover.fromFor(token);
      await platform.sendQueued(id, from: carried);
      if (carried != null) await handover.done(token);
    }

    unawaited(send().then<void>((_) {}, onError: (Object _) {}));
  }

  void _guardGuest(bool replaceGuest) {
    if (state.isGuest && !replaceGuest) throw const GuestInTheWay();
  }

  String _requireToken() {
    final token = state.stored?.token;
    if (token == null) throw StateError('Not signed in');
    return token;
  }

  /// The welcome's "Empezar" (Start): a new user without email.
  Future<void> startGuest() async {
    await ready;
    final token = await _auth.signInAsGuest();
    await _signedIn(token, guest: true);
  }

  /// Emails a sign-in code and magic link. Throws [GuestInTheWay] for a guest unless
  /// [replaceGuest] (the person was warned).
  Future<void> sendCode(String email, {bool replaceGuest = false}) async {
    await ready;
    _guardGuest(replaceGuest);
    await _auth.sendCode(email);
  }

  /// Signs in with the emailed code (typed, or from the magic link). Guarded like [sendCode].
  /// [keepCapturesOf]: a merge's sign-in (phone-first spec 7.2) passes the guest's account id, so
  /// the bank-notification captures and "Bien" confirms queued for it go to the new account instead
  /// of being dropped.
  Future<void> verifyCode(
    String email,
    String code, {
    bool replaceGuest = false,
    String? keepCapturesOf,
  }) async {
    await ready;
    _guardGuest(replaceGuest);
    // A merge waiting for this email's sign-in (the code, or its link) carries the guest's captures.
    final merging = ref.read(mergeSignInProvider);
    final mergeEmail = merging.email;
    keepCapturesOf ??=
        mergeEmail != null && mergeEmail.trim().toLowerCase() == email.trim().toLowerCase()
        ? merging.guestUserId
        : null;
    final token = await _auth.verifyCode(email, code);
    // Before the token: a process killed right after still hands the guest's captures over.
    if (keepCapturesOf != null) await ref.read(captureHandoverProvider).keep(token, keepCapturesOf);
    // The code is spent: the session is on the phone before anything else is asked, so a slow or
    // dropped connection can never leave a spent code and no session.
    await _store.write(token, guest: false);
    // After an email sign-in (code or magic link) a passkey may be offered; asking is a nicety, so a
    // failure just means no offer, and the answer is waited for only a few seconds.
    final offer = await ref.read(passkeyOfferProvider).dueFor(token);
    final standing = await _standing(token);
    await _signedIn(
      token,
      guest: false,
      onboardingPending: standing?.onboardingPending ?? false,
      onboardingKnown: standing != null,
      offerPasskeyFor: offer,
      userId: standing?.userId,
      capturesFrom: keepCapturesOf,
    );
  }

  /// How the account behind [token] stands (the welcome to do, its id); null when the server could
  /// not say. Not knowing lets the person in, and the next start asks again.
  Future<AccountStanding?> _standing(String token) async {
    try {
      return await _auth.standing(token);
    } on AuthFailure {
      return null;
    }
  }

  /// The welcome ended (finished or skipped): the account no longer has it to do.
  Future<void> onboardingDone() async {
    final stored = state.stored;
    if (stored == null || (!stored.onboardingPending && stored.onboardingKnown)) return;
    await _store.write(stored.token, guest: stored.guest);
    state = SessionState.signedIn(
      StoredSession(token: stored.token, guest: stored.guest),
      offerPasskeyFor: state.offerPasskeyFor,
    );
  }

  /// The passkey offer was answered ("Crear mi huella" or "Ahora no"): it is kept for the account,
  /// so this phone does not ask it again, and the offer is no longer pending.
  Future<void> answerPasskeyOffer() async {
    final id = state.offerPasskeyFor;
    final stored = state.stored;
    if (id == null || stored == null) return;
    await ref.read(passkeyOfferProvider).decide(id);
    if (state.stored?.token == stored.token) state = SessionState.signedIn(stored);
  }

  /// The passkey offer (`/entry/passkey-offer`) after a `preview` guest's claim, once its recovery
  /// key is done (`afterClaim`, lib/protect/protect_actions.dart: the only caller, so the offer
  /// comes once): `offerPasskeyFor` becomes the signed-in account's id when the offer is due for it
  /// (the phone has passkeys, the account none, and this phone never had the answer). The claim
  /// itself ([confirmClaim]) offers nothing.
  Future<void> offerPasskey() async {
    await ready;
    final stored = state.stored;
    if (stored == null || stored.guest) return;
    final id = await ref.read(passkeyOfferProvider).dueFor(stored.token);
    if (id == null || !ref.mounted || state.stored?.token != stored.token) return;
    state = SessionState.signedIn(state.stored!, offerPasskeyFor: id);
  }

  /// "Guardar mi progreso": mails the signed-in guest a code to claim [email].
  Future<void> claimEmail(String email) async {
    await ready;
    if (!state.isGuest) throw StateError('Only a guest claims an email');
    await _auth.claimSend(_requireToken(), email);
  }

  /// Gives the guest [email] with the claim code: the same user and token, no longer a guest.
  Future<void> confirmClaim(String email, String code) async {
    await ready;
    if (!state.isGuest) throw StateError('Only a guest claims an email');
    final token = _requireToken();
    await _auth.claimVerify(token, email, code);
    // The guest has been using the app: its start was its welcome, and the web's would only offer
    // to set up what it has. A failure here only means the next start sends it there.
    try {
      await _auth.completeOnboarding(token);
    } on AuthFailure {
      // See above.
    }
    await _signedIn(token, guest: false);
  }

  /// "Entrar con huella". Guarded like [sendCode].
  Future<void> signInWithPasskey({bool replaceGuest = false}) async {
    await ready;
    _guardGuest(replaceGuest);
    final challenge = await _auth.passkeySignInOptions();
    final assertion = await _passkeys.get(challenge.optionsJson);
    await _finishPasskeySignIn(challenge, assertion);
  }

  /// The email screen, on opening: signs in with a passkey the phone can offer at once (one made on
  /// the web and held by Proton Pass, say), showing nothing when there is none. True when it signed
  /// in. False, silently, when there was no passkey, the person closed the sheet, or the phone or
  /// the connection could not even ask: the email works as ever. Only a passkey the person chose
  /// and the server then refused throws [AuthFailure]. Guarded like [sendCode]: it never replaces
  /// a guest's session ([GuestInTheWay], before anything is asked).
  Future<bool> signInWithAvailablePasskey() async {
    await ready;
    _guardGuest(false);
    final PasskeyChallenge challenge;
    final String assertion;
    try {
      challenge = await _auth.passkeySignInOptions();
      assertion = await _passkeys.getAvailable(challenge.optionsJson);
    } on AuthFailure {
      return false;
    }
    await _finishPasskeySignIn(challenge, assertion);
    return true;
  }

  Future<void> _finishPasskeySignIn(PasskeyChallenge challenge, String assertion) async {
    final token = await _auth.passkeySignIn(challenge, assertion);
    // A guest can add a passkey (spec section 4.3), so the passkey may belong to one: ask, so a
    // guest stays a guest (warned on sign-out, offered "Guarda tu progreso"). If the server can't
    // say, the safe side is a guest, which /v1/me corrects at the next start.
    var guest = true;
    var pending = false;
    String? userId;
    try {
      final standing = await _auth.standing(token);
      guest = standing.guest;
      pending = standing.onboardingPending;
      userId = standing.userId;
    } on AuthFailure {
      guest = true;
    }
    await _signedIn(token, guest: guest, onboardingPending: pending, userId: userId);
  }

  /// "Use my recovery key": signs in with the typed key (`POST /v2/recovery/sign-in`), then holds
  /// it, as its 16 parsed bytes, for the vault gate, which opens the account's data with it without
  /// asking again (ruling 6). The text is parsed as Unlock parses it (lower case, spaces, dashes, O
  /// for 0): one that does not parse is `AuthFailure(code: 'bad_recovery_key', status: 400)` and
  /// nothing is sent. Only what the key derives (`lookup`, `auth`) leaves the phone, and it is
  /// zeroed once sent; the secret is zeroed on any failure, and is never kept as text nor written.
  /// Guarded like [sendCode].
  Future<void> signInWithRecoveryKey(String text) async {
    await ready;
    _guardGuest(false);
    final Uint8List secret;
    try {
      secret = keysParseRecoveryKey(text);
    } on Object {
      throw const AuthFailure(code: 'bad_recovery_key', status: 400);
    }
    final held = ref.read(signInRecoveryKeyProvider);
    var handedOver = false;
    try {
      final RecoverySignedInAs signedIn;
      final verifier = await recoveryVerifier(secret);
      try {
        signedIn = await _auth.recoverySignIn(verifier.lookup, verifier.auth);
      } finally {
        verifier.lookup.fillRange(0, verifier.lookup.length, 0);
        verifier.auth.fillRange(0, verifier.auth.length, 0);
      }
      final (:token, :userId) = signedIn;
      // Held for the account the server named, before the session changes: the gate that the new
      // session starts takes it.
      held.hold(userId, secret);
      handedOver = true;
      // The account may have no email: if the server cannot say, a guest (the safe side).
      final standing = await _standing(token);
      await _signedIn(
        token,
        guest: standing?.guest ?? true,
        onboardingPending: standing?.onboardingPending ?? false,
        onboardingKnown: standing != null,
        userId: userId,
      );
    } on Object {
      if (handedOver) held.clear();
      handedOver = false;
      rethrow;
    } finally {
      if (!handedOver) secret.fillRange(0, secret.length, 0);
    }
  }

  /// Adds a passkey on this phone to the signed-in user, a guest included (spec section 4.3).
  Future<void> registerPasskey() async {
    await ready;
    final token = _requireToken();
    final challenge = await _auth.passkeyRegisterOptions(token);
    final attestation = await _passkeys.create(challenge.optionsJson);
    await _auth.passkeyRegister(token, challenge, attestation);
  }

  /// Signs out. A guest's account has no email, so once the token is gone nobody can reach it:
  /// this throws [GuestInTheWay], changing nothing, unless [discardGuest] says the person was
  /// warned (Settings does) or the server itself has dropped the session (a 401).
  Future<void> signOut({bool discardGuest = false}) async {
    await ready;
    if (state.isGuest && !discardGuest) throw const GuestInTheWay();
    final token = state.stored?.token;
    if (token != null) {
      try {
        // Best effort, and never for long: a server that is down (the reason someone changes
        // server) must not hold the sign-out up. Forgetting the session here is what matters.
        await _auth.signOut(token).timeout(signOutWait);
      } on Object {
        // Offline, not answering, already gone, a 5xx, a failed TLS handshake, a bug in the call:
        // whatever went wrong there, the session is forgotten here all the same.
      }
    }
    ref.read(signInRecoveryKeyProvider).clear();
    await _forgetVault();
    await _forgetWidget();
    _forgetCaptures();
    await _store.clear();
    state = SessionState.signedOut;
  }

  /// A merge into an email account (phone-first spec 7.2) is called off after its sign-in (ruling
  /// 10): the anonymous session kept aside ([guestToken], account [guestUserId]) is the session again
  /// first, with its vault and keys as they were; then the email account's vault is forgotten by its
  /// id (only an id learned for that session, never the account kept last, which may be the guest);
  /// then that session is signed out on the server, best effort and not waited for. A process killed
  /// anywhere in between restarts in the guest's session with its data. The captures queued for the
  /// email account meanwhile are re-tagged for the guest.
  Future<void> returnToGuest(String guestToken, {String? guestUserId}) async {
    await ready;
    final token = state.stored?.token;
    if (token == null || token == guestToken) {
      await _signedIn(guestToken, guest: true, userId: guestUserId);
      return;
    }
    final accountId = await _accountIdOf(token);
    ref.read(signInRecoveryKeyProvider).clear();
    if (accountId != null && accountId != guestUserId) {
      await ref.read(captureHandoverProvider).keep(guestToken, accountId);
    }
    await _signedIn(
      guestToken,
      guest: true,
      userId: guestUserId,
      capturesFrom: accountId == guestUserId ? null : accountId,
    );
    if (accountId != null && accountId != guestUserId) {
      final keys = ref.read(keyStorageProvider);
      try {
        await ref.read(forgetVaultProvider)(accountId, keys);
      } on Object {
        try {
          await keys.deleteAll(accountId);
        } on Object {
          // Swept at a later sign-in (the account is not the guest's).
        }
      }
      await _forgetKept(accountId, token);
    }
    unawaited(_auth.signOut(token).timeout(signOutWait).then<void>((_) {}, onError: (Object _) {}));
  }

  /// The account of the session [token], as learned for it (the known account, else what was kept
  /// for that session); null when neither says.
  Future<String?> _accountIdOf(String token) async {
    final known = ref.read(knownAccountProvider);
    if (known.owner == sessionOwnerOf(token) && known.id != null) return known.id;
    try {
      return (await ref.read(encryptionStoreProvider).recall(token))?.profile.id;
    } on Object {
      return null;
    }
  }

  /// Forgets the mode kept for [userId], and the kept account when it is still [token]'s.
  Future<void> _forgetKept(String userId, String token) async {
    final store = ref.read(encryptionStoreProvider);
    try {
      if (await store.recall(token) != null) {
        await store.forget(userId);
      } else {
        await appSecureStorage.delete(key: EncryptionStore.modeKey(userId));
      }
    } on Object {
      // Personal but not secret; the next sweep takes it.
    }
  }

  /// The server no longer knows the session (it expired, or the account signed out everywhere): it
  /// ends here without telling the server, as [_refresh] does on a 401. The home cache, the saves
  /// waiting for the network and the widget's figures go, as at a sign-out; the vault of a `preview`
  /// account does not (spec 2026-11-12 sections 3 and 6.5 wipe it only at a sign-out and when this
  /// device was removed): its file, its keys and what was kept of the account wait for the same
  /// account's next sign-in, which finds them and sends the changes not sent yet. Another account's
  /// sign-in, or a signed-out start once another account was kept, sweeps them
  /// ([staleVaultsProvider]). The captures queued for the account stay for it too. [token] is the
  /// session that got the 401: a newer one is never ended by it.
  Future<void> sessionExpired({String? token}) async {
    await ready;
    final stored = state.stored?.token;
    if (stored == null || (token != null && token != stored)) return;
    ref.read(signInRecoveryKeyProvider).clear();
    await _forgetWidget();
    // A sign-in meanwhile (another token) is not undone.
    if (state.stored?.token != stored) return;
    await _store.clear();
    if (state.stored?.token == stored) state = SessionState.signedOut;
  }

  /// The account was deleted on the server (or the server says the session is gone, which comes to
  /// the same for this phone): its session ends here without asking the server to end it. The home
  /// cache and the saves waiting for the network go first and are waited for, then the widget says
  /// "Abre Wambito para empezar" and is redrawn, and the token goes last: a process that dies in
  /// between still finds the session, is told by the server it is gone, and puts the rest right at
  /// the next start.
  Future<void> accountDeleted() async {
    await ready;
    ref.read(signInRecoveryKeyProvider).clear();
    await clearHomeCache(ref.read(homeCacheStoreProvider));
    await clearPendingSaves(ref.read(pendingSavesStoreProvider));
    await _forgetVault();
    await ref.read(widgetSyncProvider).signedOut().timeout(widgetWait, onTimeout: () {});
    _forgetCaptures();
    await _store.clear();
    state = SessionState.signedOut;
  }

  /// A signed-in `preview` account's vault does not outlive its session: the vault file and every
  /// key of the account ([forgetVault]), then what the phone kept of the account (its profile and
  /// its mode). Waited for, and before the token goes: a process that dies in between still finds
  /// the session and puts the rest right at the next start. The account is the one the phone kept
  /// for this session ([EncryptionStore.recall]): no network is asked, and an account whose mode
  /// was never learned has no vault. A failure never keeps the person signed in; the keys go anyway.
  Future<void> _forgetVault({String? token}) async {
    token ??= state.stored?.token;
    if (token == null) return;
    final store = ref.read(encryptionStoreProvider);
    final String userId;
    try {
      // The account the app knows now, else what the phone kept for this session.
      final known = ref.read(knownAccountProvider);
      final id = known.owner == sessionOwnerOf(token) ? known.id : null;
      final account = id == null ? await store.recall(token) : null;
      // Else the account kept last: a session that expired kept it, and the person signed in
      // again but the server has not said who they are yet. Sign-out leaves no vault behind.
      final found = id ?? account?.profile.id ?? await store.keptAccountId();
      if (found == null) return;
      userId = found;
    } on Object {
      return;
    }
    final keys = ref.read(keyStorageProvider);
    try {
      await ref.read(forgetVaultProvider)(userId, keys);
    } on Object {
      // The file would not go: the keys still do, so what is left cannot be opened.
      try {
        await keys.deleteAll(userId);
      } on Object {
        // Nothing more to do; the next sign-in of this account finds it as it was.
      }
    }
    await store.forget(userId);
  }

  /// The captures detected from notifications and still waiting to be sent belong to the account
  /// that leaves: the next one must not receive them (Android's queue, `clearQueue`). Not waited
  /// for, like the home cache: signing out never hangs on it.
  void _forgetCaptures() {
    unawaited(
      ref.read(autoCapturePlatformProvider).clearQueue().then<void>((_) {}, onError: (Object _) {}),
    );
  }

  /// The most a sign-out waits for the widget's storage.
  static const widgetWait = Duration(seconds: 2);

  /// The widget on the home screen and the home cache hold the signed-in person's figures: signed
  /// out, neither may show them to the next person. The widget gets its signed-out snapshot
  /// ("Abre Wambito para empezar", no figure) and is redrawn (Review Focus 4) **before** the
  /// session is forgotten: if the process dies in between, the session is still there and the
  /// next start puts things right, while the other order would leave the figure on the home
  /// screen with nobody signed in. Waited for at most [widgetWait]: signing out never hangs on
  /// the widget's storage. The home cache is not waited for, nor are the saves still waiting for the
  /// network (lib/offline/pending_saves.dart), which go with it.
  Future<void> _forgetWidget() async {
    unawaited(clearHomeCache(ref.read(homeCacheStoreProvider)));
    unawaited(clearPendingSaves(ref.read(pendingSavesStoreProvider)));
    await ref.read(widgetSyncProvider).signedOut().timeout(widgetWait, onTimeout: () {});
  }
}

/// The recovery key typed at sign-in, held in memory for the vault gate (ruling 6): the parsed
/// 16-byte secret, never text, never written. One take: [take] hands it over once, to the gate of
/// the account it signed in to, which zeroes it after its one try; another account's take gets
/// nothing and the secret is zeroed. A new [hold] or [clear] (a sign-out) zeroes the one held.
class SignInRecoveryKey {
  String? _userId;
  Uint8List? _secret;

  void hold(String userId, Uint8List secret) {
    if (!identical(_secret, secret)) clear();
    _userId = userId;
    _secret = secret;
  }

  /// The held secret when it is [userId]'s, else null; nothing is held afterwards either way. The
  /// caller owns what it gets and zeroes it.
  Uint8List? take(String userId) {
    final secret = _secret;
    final owner = _userId;
    _secret = null;
    _userId = null;
    if (secret == null) return null;
    if (owner == userId) return secret;
    secret.fillRange(0, secret.length, 0);
    return null;
  }

  /// Zeroes and drops a held secret.
  void clear() {
    final secret = _secret;
    _secret = null;
    _userId = null;
    secret?.fillRange(0, secret.length, 0);
  }
}

/// A merge into an email account waiting for its sign-in (phone-first spec 7.2), set by the merge
/// (`lib/merge/merge_controller.dart`): an email sign-in to [email] takes over [guestUserId]'s
/// queued captures (`verifyCode`'s `keepCapturesOf`).
class MergeSignIn {
  String? email;
  String? guestUserId;
}

final mergeSignInProvider = Provider<MergeSignIn>((ref) => MergeSignIn());

/// Whether a `preview` guest's claim is finishing on the email screen (`afterClaim`: the recovery
/// key, then the passkey offer): the router leaves that screen open although the account has an
/// email now, so what comes after the claim is shown over it rather than lost to the redirect home.
class ClaimFinishing extends Notifier<bool> {
  @override
  bool build() => false;

  set finishing(bool value) => state = value;
}

final claimFinishingProvider = NotifierProvider<ClaimFinishing, bool>(ClaimFinishing.new);

/// The app's [SignInRecoveryKey] (memory only).
final signInRecoveryKeyProvider = Provider<SignInRecoveryKey>((ref) {
  final held = SignInRecoveryKey();
  ref.onDispose(held.clear);
  return held;
});

final sessionStoreProvider = Provider<SessionStore>((ref) => SessionStore());

final sessionProvider = NotifierProvider<SessionController, SessionState>(SessionController.new);

/// The network for the signed-in session (rebuilt when the token changes): never the vault's local
/// backend. The vault's keys and sync, and the account's mode, go through it.
final networkClientProvider = Provider<ApiClient>(
  (ref) => ApiClient.forServer(
    ref.watch(serverUrlProvider),
    token: ref.watch(sessionProvider.select((s) => s.stored?.token)),
    hints: ref.watch(deviceHintsProvider),
  ),
);

/// The API client the screens use (rebuilt when the token changes): the network, with the open
/// vault's interceptor in front when a `preview` account's vault is open, so its `/v1` routes are
/// answered on the phone. A Dio of its own: [networkClientProvider]'s never gets the interceptor.
///
/// Signed in to an account not known to be `plain` (`preview`, or its mode still loading or
/// failed), a [FinanceGuard] after it holds every `/v1` finance call the vault does not answer:
/// nothing of a `preview` account's finances goes to the server in clear, even before its vault
/// opens. The vault is always the signed-in session's ([vaultSessionProvider] is bound to it).
final apiClientProvider = Provider<ApiClient>((ref) {
  final vault = ref.watch(vaultSessionProvider);
  final owner = ref.watch(vaultOwnerProvider);
  final plain = ref.watch(knownPlainProvider);
  final client = ApiClient.forServer(
    ref.watch(serverUrlProvider),
    token: ref.watch(sessionProvider.select((s) => s.stored?.token)),
    hints: ref.watch(deviceHintsProvider),
  );
  if (vault != null) client.dio.interceptors.add(vault.interceptor);
  if (owner != null && !plain) {
    // The mode of this session's account, once known: plain goes, preview is locked, and a mode
    // that could not be learned (an error, another session's by then) fails as offline.
    FinanceVerdict of(VaultAccount? a) => a == null || a.owner != owner
        ? FinanceVerdict.unknown
        : a.mode == EncryptionMode.plain
        ? FinanceVerdict.plain
        : FinanceVerdict.locked;
    // An account only inferred `plain` (from its cache) waits for the server's word: a `preview`
    // one is refused, and without an answer the calls fail as offline (the cache's path).
    final verdict = ref
        .read(vaultAccountProvider.future)
        .then<FinanceVerdict>(
          (a) =>
              a != null && a.inferred ? ref.read(freshVaultAccountProvider.future).then(of) : of(a),
        )
        .catchError((Object _) => FinanceVerdict.unknown);
    client.dio.interceptors.add(FinanceGuard(() => verdict));
  }
  return client;
});
