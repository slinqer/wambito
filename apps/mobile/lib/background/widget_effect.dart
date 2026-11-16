import '../home/vault_widget.dart';
import '../home/widget_snapshot.dart';
import '../local/backend.dart';

/// The `widget` effect of a background run (D10, D11): the home-screen widget drawn from the vault
/// the run just synced ([writeVaultWidget]), even when the sync could not reach the server.
///
/// [hideAmount] is asked at the moment of the write; a choice that cannot be read hides the amount
/// (never written in the clear by guess). [owns] says whether [userId] is still the signed-in
/// account, so a session that ended or changed meanwhile writes nothing (the same check the app's
/// `WidgetSync` makes).
Future<void> Function(String userId, LocalBackend backend) widgetEffect({
  required WidgetStore store,
  required Future<bool> Function() hideAmount,
  required String theme,
  required String locale,
  required DateTime Function() now,
  required Future<bool> Function(String userId) owns,
}) => (userId, backend) async {
  final hide = await hideAmount();
  await writeVaultWidget(
    userId: userId,
    backend: backend,
    store: store,
    hideAmount: hide,
    theme: theme,
    locale: locale,
    now: now().toUtc(),
    stillOwner: () => owns(userId),
  );
};
