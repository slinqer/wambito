import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../capture_auto/capture_platform.dart';
import '../home/home_cache.dart';
import '../home/widget_sync.dart';
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
    _sendQueuedCaptures(token, userId);
  }

  /// Tells Android whose the queue of detected captures is now, so it drops another account's and
  /// sends the rest (`sendQueued`, R15): what a 401 kept is sent once its account signs in again.
  /// Asks the server for the account id only when [userId] is not known and there is an Android
  /// side. Not waited for, and a failure (offline) only leaves the queue for the next sign-in or
  /// start: nothing is sent to an account that could not be told.
  void _sendQueuedCaptures(String token, String? userId) {
    final platform = ref.read(autoCapturePlatformProvider);
    Future<void> send() async {
      if (await platform.status() == null) return;
      final id = userId ?? await _auth.accountId(token);
      if (!ref.mounted || state.stored?.token != token) return;
      await platform.sendQueued(id);
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

  /// "Probar sin correo": a new guest.
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
  Future<void> verifyCode(String email, String code, {bool replaceGuest = false}) async {
    await ready;
    _guardGuest(replaceGuest);
    final token = await _auth.verifyCode(email, code);
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
    await _forgetVault();
    await _forgetWidget();
    _forgetCaptures();
    await _store.clear();
    state = SessionState.signedOut;
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
      final found = id ?? account?.profile.id;
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
          (a) => a != null && a.inferred
              ? ref.read(freshVaultAccountProvider.future).then(of)
              : of(a),
        )
        .catchError((Object _) => FinanceVerdict.unknown);
    client.dio.interceptors.add(FinanceGuard(() => verdict));
  }
  return client;
});
