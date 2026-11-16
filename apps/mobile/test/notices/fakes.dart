import 'package:wambito/notices/due_list.dart';
import 'package:wambito/notices/notice_backend.dart';
import 'package:wambito/notices/notice_platform.dart';

/// Android's side of the notices in memory: what was scheduled or cancelled, and the permission.
class FakeNoticePlatform implements NoticePlatform {
  FakeNoticePlatform({this.permissionState = NoticePermission.askable, this.systemAnswer = true});

  /// What Android says about the notification permission.
  NoticePermission permissionState;

  /// What the person answers to Android's own prompt.
  bool systemAnswer;

  /// Every call, in order: `scheduleDue America/Bogota es`, `cancelDue`, `scheduleGuest es`...
  final calls = <String>[];

  List<String> callsNamed(String name) => calls.where((c) => c.split(' ').first == name).toList();

  void clear() => calls.clear();

  @override
  Future<void> scheduleDue({required String zone, required String language}) async =>
      calls.add('scheduleDue $zone $language');

  /// The days of every `scheduleDueList`, in order.
  final dueLists = <List<DueDay>>[];

  @override
  Future<void> scheduleDueList({
    required String zone,
    required String language,
    required String owner,
    required List<DueDay> days,
  }) async {
    dueLists.add(days);
    calls.add('scheduleDueList $zone $language $owner');
  }

  @override
  Future<void> cancelDue() async => calls.add('cancelDue');

  @override
  Future<void> scheduleGuest({required String language}) async => calls.add('scheduleGuest $language');

  @override
  Future<void> cancelGuest() async => calls.add('cancelGuest');

  @override
  Future<NoticePermission> permission() async => permissionState;

  @override
  Future<bool> requestPermission() async {
    calls.add('requestPermission');
    if (systemAnswer) permissionState = NoticePermission.granted;
    return systemAnswer;
  }
}

/// What the notices ask of the server, in memory.
class FakeNoticeBackend implements NoticeBackend {
  FakeNoticeBackend({this.timezone = 'America/Bogota', this.hasRecurring = false});

  String timezone;
  bool hasRecurring;

  /// The next call throws this (then cleared): offline, say.
  Object? failure;
  int calls = 0;

  @override
  Future<NoticeFacts> facts() async {
    calls++;
    final failing = failure;
    if (failing != null) {
      failure = null;
      throw failing;
    }
    return NoticeFacts(timezone: timezone, hasRecurring: hasRecurring);
  }
}
