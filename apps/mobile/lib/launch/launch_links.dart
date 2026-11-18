import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../add/add_sheet.dart';
import '../api/session.dart';
import '../capture/capture_sheet.dart';
import '../home/home_controller.dart';
import '../review/review_controller.dart';
import '../local/signin_approval.dart' show isSigninQr;
import '../router.dart';
import '../settings/security/approve_signin_screen.dart' show openSigninApprovalsProvider;
import '../settings/security/security_api.dart' show securityApiProvider;

/// What a `wambito://` link asks for (spec section 7.1): the widget's ＋ (`wambito://add`, the add
/// sheet with the keypad ready) and its 🎤, also the Quick Settings tile's (`wambito://capture`,
/// quick capture listening). `wambito://due` is the "Hoy vence…" notice's (spec section 7.2): home,
/// where the payments due today are listed first. `wambito://progress` is the guest warning's:
/// "Guarda tu progreso", over home. `wambito://home` is a tap on the widget itself (its figures, its
/// face, any area but the buttons): home. `wambito://review` and `wambito://review/<id>` are the
/// detected-transaction notification's "Cambiar" and the like: the review inbox, with that
/// transaction open in the editor when an id comes ([launchReviewIdOf]). `wambito://signin?id=…&key=…`
/// is a web sign-in's QR opened by the system camera (phone-first spec 8.1, ruling 14): the
/// approval, only while the vault is open ([launchSigninQrOf]).
enum LaunchAction { add, capture, due, progress, home, review, signin }

/// The scheme of the links the app builds.
const launchScheme = 'wambito';

/// The link that asks for [action]: `wambito://<action>`.
Uri launchLinkOf(LaunchAction action) => Uri(scheme: launchScheme, host: action.name);

/// The action [link] asks for, or null for any other link.
LaunchAction? launchActionOf(String? link) {
  final uri = Uri.tryParse(link ?? '');
  if (uri == null || uri.scheme != launchScheme) return null;
  if (uri.host == 'review') {
    // Nothing, or exactly one segment: the transaction's id.
    return uri.pathSegments.where((s) => s.isNotEmpty).length <= 1 && !uri.path.startsWith('//')
        ? LaunchAction.review
        : null;
  }
  if (uri.path.isNotEmpty && uri.path != '/') return null;
  return switch (uri.host) {
    'add' => LaunchAction.add,
    'capture' => LaunchAction.capture,
    'due' => LaunchAction.due,
    'progress' => LaunchAction.progress,
    'home' => LaunchAction.home,
    'signin' => LaunchAction.signin,
    _ => null,
  };
}

/// The transaction id of a `wambito://review/<id>` link; null for `wambito://review` and any other.
String? launchReviewIdOf(String? link) {
  if (launchActionOf(link) != LaunchAction.review) return null;
  final id = Uri.parse(link!).pathSegments.where((s) => s.isNotEmpty).firstOrNull;
  return id;
}

/// The QR of a `wambito://signin?id=<uuid>&key=<key>` link, exactly as the browser shows it; null
/// for any other link (no query, another shape).
String? launchSigninQrOf(String? link) {
  if (launchActionOf(link) != LaunchAction.signin) return null;
  return isSigninQr(link!) ? link : null;
}

/// Where `wambito://` links come from: Android (MainActivity.kt) keeps them away from the router
/// and hands them over here. Tests replace it.
abstract interface class LaunchLinkSource {
  /// The link the app was started with (a cold start from the widget or the tile), once; null when
  /// there was none or it was already taken.
  Future<String?> takeInitial();

  /// Links that arrive while the app runs (the widget tapped with the app in the background).
  Stream<String> get links;
}

/// [LaunchLinkSource] over the `wambito/launch` channel. Android keeps the latest link until it is
/// taken; it says `linkArrived` when one comes in while the app runs, and the link is then taken.
/// A link that comes before Dart listens is taken at the start instead, so none is lost.
class ChannelLaunchLinkSource implements LaunchLinkSource {
  ChannelLaunchLinkSource() {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'linkArrived') return;
      final link = await _take();
      if (link != null) _links.add(link);
    });
  }

  static const _channel = MethodChannel('wambito/launch');
  final _links = StreamController<String>.broadcast();

  Future<String?> _take() async {
    try {
      return await _channel.invokeMethod<String>('take');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<String?> takeInitial() => _take();

  @override
  Stream<String> get links => _links.stream;
}

final launchLinkSourceProvider = Provider<LaunchLinkSource>((ref) => ChannelLaunchLinkSource());

/// Opens what a `wambito://` link asks for, at a cold start too: it waits for the stored session to
/// be read, then, signed in (and past the welcome), goes to home (closing whatever sheet or screen was open) and opens
/// the add sheet or quick capture listening there. Signed out it does nothing: the router already
/// shows the entry screen. Nor does it while a sheet holds the person's input (an add or edit sheet,
/// typed text or cards in capture): that is kept. A capture sheet already open is not replaced by a
/// second one: 🎤 brings it to listening.
class LaunchLinks {
  LaunchLinks(this._ref);

  /// The most a link waits for the server's word on the welcome.
  static const refreshWait = Duration(seconds: 3);

  final Ref _ref;
  StreamSubscription<String>? _subscription;

  void _start() {
    final source = _ref.read(launchLinkSourceProvider);
    _subscription = source.links.listen((link) => unawaited(open(link)));
    unawaited(source.takeInitial().then((link) => link == null ? null : open(link)));
  }

  /// Opens what [link] asks for; does nothing for any other link.
  Future<void> open(String link) async {
    final action = launchActionOf(link);
    if (action == null) return;
    final controller = _ref.read(sessionProvider.notifier);
    await controller.ready;
    // Whether the account has the welcome to do is the server's to say. An account the phone knows
    // has finished it (or is still at it) opens the link at once, with no wait at all: a cold tap of
    // the widget's 🎤 is not slowed by a round trip. One it does not know yet (a session stored before
    // the welcome, or whose profile could not be read) is asked, for a moment at most, so the link
    // never waits on a bad connection.
    final known = _ref.read(sessionProvider);
    if (known.status == SessionStatus.signedIn && !known.onboardingKnown) {
      try {
        await controller.refreshed.timeout(refreshWait);
      } on Object {
        // Offline or slow: what was kept stands.
      }
    }
    final session = _ref.read(sessionProvider);
    if (session.status != SessionStatus.signedIn) return;
    // An account with the welcome to do is sent to it from everywhere, and its link is dropped, as
    // the web's `requireOnboarded` drops the page it was going to: nothing opens over the welcome.
    if (session.onboardingPending) return;
    // 🎤 with a capture sheet already open: that sheet is brought to listening, whatever it holds
    // (typed text and cards stay), and no second one is stacked over it.
    if (action == LaunchAction.capture && _ref.read(openCaptureSheetsProvider).listenFromLink()) {
      return;
    }
    // A sheet with the person's input in it (add, edit or capture) is never thrown away for a link:
    // the link is dropped, and the sheet stays as it was (the app only comes to the front).
    if (_ref.read(sheetsWithInputProvider).any) return;
    // A web sign-in needs this phone's data open (an encrypted account, unlocked): otherwise the
    // link is dropped, and the person scans again once it is (ruling 14). A `plain` account has
    // nothing to approve with.
    // Nor while an approval is open: a link never swaps the request under the person's tap (P18).
    final signinQr = launchSigninQrOf(link);
    if (action == LaunchAction.signin &&
        (signinQr == null ||
            _ref.read(securityApiProvider) == null ||
            _ref.read(openSigninApprovalsProvider).any)) {
      return;
    }
    final router = _ref.read(routerProvider);
    router.go('/');
    // Home must be the page under the sheet before it opens: a sheet opened over the loading screen
    // would go with it. The router takes a frame or two to get there.
    for (var frame = 0; frame < 30 && router.state.uri.path != '/'; frame++) {
      await WidgetsBinding.instance.endOfFrame;
    }
    await WidgetsBinding.instance.endOfFrame;
    final context = router.routerDelegate.navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    // A sheet or dialog already open with nothing typed in it (an earlier link, the person's own
    // tap) gives way.
    Navigator.of(context).popUntil((route) => route.isFirst);
    switch (action) {
      case LaunchAction.add:
        unawaited(openAddSheet(context));
      case LaunchAction.capture:
        unawaited(openCapture(context, listen: true));
      case LaunchAction.due:
      case LaunchAction.home:
        // Home is the destination: today's payments sit at the top of its list, so it is the
        // current month, even when it was left on an earlier one. A home that was already loaded
        // is brought up to date, so the payment that fell due overnight is there.
        if (_ref.exists(homeProvider)) {
          unawaited(_ref.read(homeProvider.notifier).showCurrentMonth());
        }
      case LaunchAction.progress:
        // Only a guest has a progress to save; an account that has since claimed an email is on
        // home already.
        if (_ref.read(sessionProvider).isGuest) unawaited(router.push('/progress'));
      case LaunchAction.review:
        if (_ref.exists(homeProvider)) unawaited(_ref.read(homeProvider.notifier).refresh());
        _ref.invalidate(reviewProvider);
        final id = launchReviewIdOf(link);
        unawaited(router.push(id == null ? '/review' : '/review/${Uri.encodeComponent(id)}'));
      case LaunchAction.signin:
        unawaited(router.push('/settings/signin?qr=${Uri.encodeQueryComponent(signinQr!)}'));
    }
  }
}

/// Started by the app at once (app.dart), so a link the app was started with is not missed.
final launchLinksProvider = Provider<LaunchLinks>((ref) {
  final links = LaunchLinks(ref).._start();
  ref.onDispose(() => unawaited(links._subscription?.cancel()));
  return links;
});
