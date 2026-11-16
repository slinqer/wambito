import '../api/gen/wambito_api.dart';
import '../local/backend.dart';
import 'widget_snapshot.dart';

/// Draws the home-screen widget of a `preview` account from its vault on this phone: the month's
/// figures come from `GET /v1/summary` (and the currency and zone from `GET /v1/me`) answered by
/// [backend], and the snapshot carries [userId] as its `owner`, so a widget never shows another
/// account's figures (D10). Used by the app (`WidgetSync`) and by the headless engine (the `widget`
/// effect of `runBackground`).
///
/// [stillOwner] is asked right before the write, with nothing awaited in between: false (the session
/// ended, another account signed in) writes nothing. Returns whether the snapshot was written; false
/// too when the vault did not answer a summary (the widget keeps what it had).
Future<bool> writeVaultWidget({
  required String userId,
  required LocalBackend backend,
  required WidgetStore store,
  required bool hideAmount,
  required String theme,
  required String locale,
  required DateTime now,
  required Future<bool> Function() stillOwner,
}) async {
  final me = await backend.handle('GET', '/v1/me', const {}, null);
  final summaryAnswer = await backend.handle('GET', '/v1/summary', const {}, null);
  if (me == null || me.status != 200 || me.body is! Map) return false;
  if (summaryAnswer == null || summaryAnswer.status != 200 || summaryAnswer.body is! Map) {
    return false;
  }
  final profile = (me.body! as Map).cast<String, Object?>();
  final currency = profile['currency'];
  final timezone = profile['timezone'];
  final summary = standardSerializers.deserializeWith(Summary.serializer, summaryAnswer.body);
  if (summary == null || currency is! String || timezone is! String) return false;
  final snapshot = signedInSnapshot(
    summary,
    currency: currency,
    locale: locale,
    hideAmount: hideAmount,
    theme: theme,
    updatedAt: now,
    timezone: timezone,
    owner: userId,
  );
  if (!await stillOwner()) return false;
  await saveWidgetSnapshot(store, snapshot);
  return true;
}
