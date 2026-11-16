/// One capture Kotlin parsed from a notification and queued while no app was open (D1: the
/// notification text is never stored, Dart does not parse again). The keys are those of Kotlin's
/// `ParsedCapture.toJson()` plus the queue's own `key`, which stays the same across runs: it is the
/// `Idempotency-Key` of the capture's `POST /v1/captures` and what the acknowledgement names.
class QueuedCapture {
  const QueuedCapture({
    required this.key,
    required this.kind,
    required this.amount,
    required this.currency,
    required this.merchant,
    required this.capturedAt,
    required this.source,
  });

  /// Throws [FormatException] when a field is missing or mistyped. [amount] is whole cents: a whole
  /// number sent as a double is read as an int, a fraction is refused.
  factory QueuedCapture.fromJson(Map<Object?, Object?> json) {
    String text(String name) {
      final value = json[name];
      if (value is! String) throw FormatException('queued capture: $name is not text');
      return value;
    }

    final amount = json['amount'];
    final cents = switch (amount) {
      final int n => n,
      final double d when d == d.truncateToDouble() && d.isFinite => d.toInt(),
      _ => throw const FormatException('queued capture: amount is not whole cents'),
    };
    return QueuedCapture(
      key: text('key'),
      kind: text('kind'),
      amount: cents,
      currency: text('currency'),
      merchant: text('merchant'),
      capturedAt: text('capturedAt'),
      source: text('source'),
    );
  }

  final String key;
  final String kind;

  /// Integer cents.
  final int amount;
  final String currency;
  final String merchant;

  /// An ISO UTC date and time.
  final String capturedAt;

  /// The wire name of the source (`revolut`, `google_wallet`).
  final String source;

  /// The body of `POST /v1/captures`.
  Map<String, Object?> get body => {
    'kind': kind,
    'amount': amount,
    'currency': currency,
    'merchant': merchant,
    'capturedAt': capturedAt,
    'source': source,
  };
}
