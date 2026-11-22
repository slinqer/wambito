import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/gen/wambito_api.dart';
import 'package:wambito/l10n/app_localizations.dart';
import 'package:wambito/review/review_mark.dart';

final _es = lookupAppLocalizations(const Locale('es'));

/// A movement as the local backend or the API sends it, decoded by the generated client.
Transaction _detected(String? captureSource, {bool needsReview = true}) =>
    standardSerializers.deserializeWith(Transaction.serializer, {
      'id': '0190a8a0-0000-7000-8000-000000000001',
      'name': 'Juan Valdez',
      'amount': -18000,
      'currency': 'COP',
      'date': '2026-11-22',
      'status': 'paid',
      'note': null,
      'categoryId': '0190a8a0-0000-7000-8000-000000000002',
      'recurrenceId': null,
      'importId': null,
      'source': 'capture',
      'needsReview': needsReview,
      'captureSource': captureSource,
      'createdAt': '2026-11-22T15:00:00.000Z',
      'updatedAt': '2026-11-22T15:00:00.000Z',
    })!;

void main() {
  test('names each known source', () {
    expect(reviewMarkOf(_es, _detected('revolut')), 'por revisar · de Revolut');
    expect(reviewMarkOf(_es, _detected('google_wallet')), 'por revisar · de Google Wallet');
    expect(reviewMarkOf(_es, _detected('apple_wallet')), 'por revisar · de Apple Wallet');
  });

  test('a source this version does not know still decodes, with the plain mark', () {
    expect(reviewMarkOf(_es, _detected('some_future_bank')), 'por revisar');
    expect(reviewMarkOf(_es, _detected(null)), 'por revisar');
  });

  test('a confirmed movement has no mark', () {
    expect(reviewMarkOf(_es, _detected('apple_wallet', needsReview: false)), isNull);
  });
}
