import '../api/gen/wambito_api.dart';
import '../core/records.dart' show captureSources;
import '../l10n/app_localizations.dart';

/// "por revisar · de Revolut" for a movement detected from a notification and not confirmed yet;
/// null for any other. A source this version does not know (a newer phone's) gets the plain mark.
String? reviewMarkOf(AppLocalizations l10n, Transaction tx) {
  if (!tx.needsReview) return null;
  final source = tx.captureSource;
  return l10n.reviewMark(captureSources.contains(source) ? source! : '');
}
