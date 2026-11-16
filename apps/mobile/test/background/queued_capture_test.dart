import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/background/queued_capture.dart';

void main() {
  // The keys of Kotlin's `ParsedCapture.toJson()` plus the queue's `key`.
  Map<String, Object?> json([Map<String, Object?> extra = const {}]) => {
    'key': 'k-1',
    'kind': 'expense',
    'amount': 1250,
    'currency': 'EUR',
    'merchant': 'Mercadona',
    'capturedAt': '2026-11-04T15:00:00.000Z',
    'source': 'revolut',
    ...extra,
  };

  test('reads what Kotlin queues', () {
    final c = QueuedCapture.fromJson(json());
    expect(c.key, 'k-1');
    expect(c.kind, 'expense');
    expect(c.amount, 1250);
    expect(c.currency, 'EUR');
    expect(c.merchant, 'Mercadona');
    expect(c.capturedAt, '2026-11-04T15:00:00.000Z');
    expect(c.source, 'revolut');
  });

  test('the body of POST /v1/captures has the five fields and no key', () {
    expect(QueuedCapture.fromJson(json()).body, {
      'kind': 'expense',
      'amount': 1250,
      'currency': 'EUR',
      'merchant': 'Mercadona',
      'capturedAt': '2026-11-04T15:00:00.000Z',
      'source': 'revolut',
    });
  });

  test('an amount is whole cents, never a float', () {
    expect(() => QueuedCapture.fromJson(json({'amount': 12.5})), throwsFormatException);
    expect(QueuedCapture.fromJson(json({'amount': 1250.0})).amount, 1250);
  });

  test('a missing or mistyped field is a format error', () {
    for (final field in ['key', 'kind', 'amount', 'currency', 'merchant', 'capturedAt', 'source']) {
      expect(() => QueuedCapture.fromJson(json()..remove(field)), throwsFormatException);
    }
    expect(() => QueuedCapture.fromJson(json({'merchant': 7})), throwsFormatException);
  });
}
