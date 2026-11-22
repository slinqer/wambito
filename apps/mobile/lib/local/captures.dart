// The phone's side of apps/api/src/services/captures.ts: the id of a merchant-memory record and
// the validator of `POST /v1/captures` (`createCaptureSchema` of packages/core/src/capture.ts).
// The save and the learning themselves run inside the backend's store transaction (backend.dart).
import '../core/records.dart' show captureSources;
import '../core/schemas.dart';
import 'ids.dart';

/// The id of the sealed `merchant` record that remembers [merchantKey] for [userId]. It is made,
/// not random, so every device of the account converges on one record per merchant.
String merchantRecordId(String userId, String merchantKey) =>
    uuidv5(uuidv5(seedNamespace, userId), 'merchant:$merchantKey');

/// `z.iso.datetime()`: a UTC date and time, `Z` only, seconds required, any fraction.
final _isoDatetime = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$');

bool _isDatetime(String value) => _isoDatetime.hasMatch(value) && DateTime.tryParse(value) != null;

/// `createCaptureSchema`: the capture the notification code parsed.
final createCaptureSchema = ObjectSchema({
  'kind': fEnum(['expense', 'income']),
  'amount': fInt(
    refinements: [
      ((n) => n > 0, 'Too small: expected number to be >0'),
      ((n) => n <= 9007199254740991, 'Amount is too large'),
    ],
  ),
  'currency': fString(
    refine: RegExp(r'^[A-Z]{3}$').hasMatch,
    refineMessage: 'Expected a 3-letter uppercase ISO currency code',
  ),
  'merchant': fString(trim: true, min: 1, max: 120),
  'capturedAt': fString(refine: _isDatetime, refineMessage: 'Invalid ISO datetime'),
  'source': fEnum(captureSources),
});
