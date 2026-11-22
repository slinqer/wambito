import '../local/backend.dart';
import '../notices/due_list.dart';
import '../notices/notice_platform.dart';

/// The `due` effect of a background run (D12): "Hoy vence…" for a `preview` account, computed from
/// the vault the run just synced and handed to the phone as days and names ([dueListOf]); nothing
/// is asked of the server. The same as the app's own pass (lib/notices/notice_sync.dart), so a
/// payment that came from another device is announced without the app being opened.
///
/// [enabled] is the Settings switch. A switch off, or notices not allowed, cancels the list.
/// [owns] says whether [userId] is still the signed-in account, asked right before the hand-over so
/// a session that ended or changed meanwhile hands nothing over; the list carries [userId] as its
/// owner, and the phone posts nothing for another account's.
Future<void> Function(String userId, LocalBackend backend) dueEffect({
  required NoticePlatform platform,
  required Future<bool> Function() enabled,
  required String language,
  required DateTime Function() now,
  required Future<bool> Function(String userId) owns,
}) => (userId, backend) async {
  if (!await owns(userId)) return;
  if (!await enabled()) {
    await platform.cancelDue();
    return;
  }
  if (await platform.permission() != NoticePermission.granted) {
    await platform.cancelDue();
    return;
  }
  final list = await dueListOf(backend, now: now().toUtc());
  if (list == null || !await owns(userId)) return;
  await platform.scheduleDueList(
    zone: list.zone,
    language: language,
    owner: userId,
    days: list.days,
  );
};
