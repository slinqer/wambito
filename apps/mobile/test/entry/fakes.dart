import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/auth_api.dart';
import 'package:wambito/api/passkeys.dart';
import 'package:wambito/api/session.dart';
import 'package:wambito/app.dart';
import 'package:wambito/home/home_controller.dart';
import 'package:wambito/home/home_cache.dart';
import 'package:wambito/home/home_repository.dart';
import 'package:wambito/home/widget_snapshot.dart';
import 'package:wambito/review/review_repository.dart';

import '../home/fakes.dart';
import '../review/fakes.dart' show FakeReviewRepository;
import '../support/plain_account.dart';

/// An auth server in memory: records every call, answers with made-up tokens, and fails a call
/// when told to.
class FakeAuthApi implements AuthApi {
  final calls = <String>[];

  /// What the next call of that name throws (then cleared): an [AuthFailure], or anything else a
  /// call can throw (a timeout, a socket error, a bug).
  final failures = <String, Object>{};

  /// What `GET /v1/me` says about `isAnonymous`, per token.
  final guests = <String, bool>{};

  /// Whether `GET /v1/me` says the account has not finished the welcome (`onboardingCompletedAt` is
  /// null), per token. A token not here is an account that has.
  final pendingOnboarding = <String, bool>{};

  /// Whether an account that signs in with an email or a passkey from now on is a new one, that has
  /// not been through the welcome.
  bool newAccounts = false;

  /// Who `GET /v1/me` says every token is, and how many passkeys the server lists for them.
  String account = 'user-1';
  int passkeysOnAccount = 0;

  /// Whether the passkey signs in a guest (a guest can add one, spec section 4.3).
  bool passkeyBelongsToGuest = false;

  var _tokens = 0;
  String _newToken(String kind) => '$kind-token-${++_tokens}';

  void _fail(String name) {
    final failure = failures.remove(name);
    if (failure != null) throw failure;
  }

  @override
  Future<String> signInAsGuest() async {
    calls.add('signInAsGuest');
    _fail('signInAsGuest');
    final token = _newToken('guest');
    guests[token] = true;
    return token;
  }

  @override
  Future<void> sendCode(String email) async {
    calls.add('sendCode $email');
    _fail('sendCode');
  }

  @override
  Future<String> verifyCode(String email, String code) async {
    calls.add('verifyCode $email $code');
    _fail('verifyCode');
    final token = _newToken('email');
    guests[token] = false;
    pendingOnboarding[token] = newAccounts;
    return token;
  }

  @override
  Future<bool> isGuest(String token) async {
    calls.add('isGuest $token');
    _fail('isGuest');
    return guests[token] ?? false;
  }

  @override
  Future<AccountStanding> standing(String token) async {
    calls.add('isGuest $token');
    _fail('isGuest');
    final guest = guests[token] ?? false;
    return AccountStanding(
      guest: guest,
      // Like the API's profile: a guest has no welcome to finish.
      onboardingPending: !guest && (pendingOnboarding[token] ?? false),
      userId: account,
    );
  }

  @override
  Future<void> completeOnboarding(String token) async {
    calls.add('completeOnboarding $token');
    _fail('completeOnboarding');
    pendingOnboarding[token] = false;
  }

  @override
  Future<String> accountId(String token) async {
    calls.add('accountId $token');
    _fail('accountId');
    return account;
  }

  /// While set, `passkeyCount` waits for it (a server that accepts the connection and then says
  /// nothing).
  Completer<void>? holdPasskeyCount;

  @override
  Future<int?> passkeyCount(String token) async {
    calls.add('passkeyCount $token');
    _fail('passkeyCount');
    await holdPasskeyCount?.future;
    return passkeysOnAccount;
  }

  /// The passkeys the server lists for the account (Settings), oldest first; `passkeyCount` counts
  /// these when there are any.
  final passkeyItems = <PasskeyItem>[];

  /// While set, `listPasskeys` waits for it.
  Completer<void>? holdListPasskeys;

  @override
  Future<List<PasskeyItem>> listPasskeys(String token) async {
    calls.add('listPasskeys $token');
    _fail('listPasskeys');
    await holdListPasskeys?.future;
    return [...passkeyItems];
  }

  @override
  Future<void> deletePasskey(String token, String id) async {
    calls.add('deletePasskey $id');
    _fail('deletePasskey');
    passkeyItems.removeWhere((item) => item.id == id);
  }

  @override
  Future<void> claimSend(String token, String email) async {
    calls.add('claimSend $token $email');
    _fail('claimSend');
  }

  @override
  Future<void> claimVerify(String token, String email, String code) async {
    calls.add('claimVerify $token $email $code');
    _fail('claimVerify');
    guests[token] = false;
    // A guest never went through the welcome: the claimed account has not finished it either.
    pendingOnboarding[token] = true;
  }

  @override
  Future<PasskeyChallenge> passkeySignInOptions() async {
    calls.add('passkeySignInOptions');
    _fail('passkeySignInOptions');
    return const PasskeyChallenge(optionsJson: '{"challenge":"sign-in"}', cookie: 'c=1');
  }

  @override
  Future<String> passkeySignIn(PasskeyChallenge challenge, String responseJson) async {
    calls.add('passkeySignIn $responseJson');
    _fail('passkeySignIn');
    final token = _newToken('passkey');
    guests[token] = passkeyBelongsToGuest;
    pendingOnboarding[token] = newAccounts;
    return token;
  }

  @override
  Future<PasskeyChallenge> passkeyRegisterOptions(String token) async {
    calls.add('passkeyRegisterOptions $token');
    _fail('passkeyRegisterOptions');
    return const PasskeyChallenge(optionsJson: '{"challenge":"register"}', cookie: 'c=2');
  }

  @override
  Future<void> passkeyRegister(
    String token,
    PasskeyChallenge challenge,
    String responseJson,
  ) async {
    calls.add('passkeyRegister $token $responseJson');
    _fail('passkeyRegister');
    // The server has the new one: the next listing shows it.
    passkeyItems.add(
      PasskeyItem(
        id: 'pk-${passkeyItems.length + 1}',
        createdAt: registeredAt ?? DateTime.utc(2026, 10, 21, 10),
        synced: true,
      ),
    );
  }

  /// When a passkey registered through [passkeyRegister] counts as made.
  DateTime? registeredAt;

  @override
  Future<void> signOut(String token) async {
    calls.add('signOut $token');
    _fail('signOut');
    final hold = holdSignOut;
    if (hold != null) await hold.future;
  }

  /// While set, signOut waits for it (a server that accepts the connection and then says nothing).
  Completer<void>? holdSignOut;
}

/// The phone's passkey prompt, answered at once.
class FakePasskeys implements Passkeys {
  FakePasskeys({this.isSupported = true, this.hasPasskey = false});

  bool isSupported;

  /// Whether the phone has a passkey for this server at once (a provider such as Proton Pass holds
  /// one made on the web): [getAvailable] answers with it, else with `NO_CREDENTIAL`. [get], which
  /// may show the provider's own picker, always answers.
  bool hasPasskey;
  final calls = <String>[];

  /// Thrown by the next `get` or `create` instead of answering (then cleared).
  Object? failure;

  /// While set, `create` waits for it (the person has the prompt open).
  Completer<void>? holdCreate;

  @override
  Future<bool> supported() async => isSupported;

  @override
  Future<String> get(String optionsJson) async {
    calls.add('get $optionsJson');
    final error = failure;
    failure = null;
    if (error != null) throw error;
    return '{"assertion":true}';
  }

  @override
  Future<String> getAvailable(String optionsJson) async {
    calls.add('getAvailable $optionsJson');
    final error = failure;
    failure = null;
    if (error != null) throw error;
    if (!hasPasskey) throw const AuthFailure(code: 'NO_CREDENTIAL', status: 400);
    return '{"assertion":true}';
  }

  @override
  Future<String> create(String optionsJson) async {
    calls.add('create $optionsJson');
    await holdCreate?.future;
    final error = failure;
    failure = null;
    if (error != null) throw error;
    return '{"attestation":true}';
  }
}

/// Secure storage in memory, holding [token] already when given (a returning person).
void mockStorage({String? token, bool guest = false, bool onboarding = false}) {
  FlutterSecureStorage.setMockInitialValues({
    if (token != null) ...{
      SessionStore.tokenKey: token,
      SessionStore.guestKey: guest ? 'true' : 'false',
      if (onboarding) SessionStore.onboardingKey: 'pending',
    },
  });
}

/// The app in Spanish with [auth] and [passkeys] in place of the real server and phone.
Future<ProviderContainer> pumpApp(
  WidgetTester tester, {
  required FakeAuthApi auth,
  FakePasskeys? passkeys,
  Locale locale = const Locale('es'),
  List<Override> overrides = const [],
  bool plain = true,
}) async {
  tester.platformDispatcher.localesTestValue = [locale];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  final container = ProviderContainer(
    overrides: [
      // The account is `plain`: the vault's screens are test/vault's business, not these.
      if (plain) plainAccount(),
      // The tests settle the frames: a running time bar would wait a toast's life out.
      toastBarAnimatesProvider.overrideWithValue(false),
      authApiProvider.overrideWithValue(auth),
      passkeysProvider.overrideWithValue(passkeys ?? FakePasskeys(isSupported: false)),
      // Home, once reached, reads an empty month from memory instead of the network.
      homeRepositoryProvider.overrideWithValue(FakeHomeRepository()),
      reviewRepositoryProvider.overrideWithValue(FakeReviewRepository(FakeHomeRepository())),
      widgetStoreProvider.overrideWithValue(FakeWidgetStore()),
      homeCacheStoreProvider.overrideWithValue(FakeCacheStore()),
      widgetSnapshotWriterProvider.overrideWithValue(
        (summary, {required currency, required locale, required timezone}) async {},
      ),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const WambitoApp()),
  );
  await tester.pumpAndSettle();
  return container;
}
