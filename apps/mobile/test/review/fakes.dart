import 'package:wambito/api/gen/wambito_api.dart';
import 'package:wambito/home/home_repository.dart';
import 'package:wambito/review/review_repository.dart';

import '../home/fakes.dart';
import '../home/fixtures.dart';

/// A transaction the phone detected and the person has not looked at yet.
Transaction detected(
  String id,
  String date,
  int amount, {
  String? name,
  String categoryId = 'cat-groceries',
  String source = 'revolut',
}) => tx(id, date, amount, name: name, categoryId: categoryId).rebuild(
  (b) => b
    ..needsReview = true
    ..source_ = TransactionSource_Enum.capture
    ..captureSource = source,
);

/// The server's side of the review inbox, over [home]'s transactions. Records every call, and fails
/// the next one named when told to.
class FakeReviewRepository implements ReviewRepository {
  FakeReviewRepository(this.home);

  final FakeHomeRepository home;

  /// `pending`, `confirm id1,id2`.
  final calls = <String>[];
  final failures = <String, Object>{};

  /// Runs on each confirm after it is recorded; throwing fails that one request.
  void Function()? beforeConfirm;

  void _call(String name) {
    calls.add(name);
    final failure = failures.remove(name.split(' ').first);
    if (failure != null) throw failure;
  }

  @override
  Future<List<Transaction>> pending() async {
    _call('pending');
    return home.items.where((t) => t.needsReview).toList();
  }

  @override
  Future<void> confirm(List<String> ids) async {
    _call('confirm ${ids.join(',')}');
    beforeConfirm?.call();
    // All or nothing: an id the account does not have answers 404 and nothing changes.
    if (ids.any((id) => !home.items.any((t) => t.id == id))) {
      throw const HomeFailure(404, code: 'not_found');
    }
    for (final id in ids) {
      final index = home.items.indexWhere((t) => t.id == id);
      home.items[index] = home.items[index].rebuild((b) => b.needsReview = false);
    }
  }
}
