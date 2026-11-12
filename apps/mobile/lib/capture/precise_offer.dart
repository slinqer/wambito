import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../feedback/stored_flag.dart';
import 'models_download.dart';

/// The one-time offer of the precise voice model to someone who already has Vosk's: "Mejorar la
/// precisión (+N MB)", shown in the capture sheet before listening. Whatever the person answers is
/// remembered on the phone (like the other small flags), so it never comes back; a download that
/// fails is not an answer, so it is offered again.
class PreciseOffer {
  PreciseOffer({
    required this.locale,
    required this.eligible,
    required this.vosk,
    required this.precise,
    required this.store,
  });

  /// The voice's language (a `voiceLocale`).
  final String locale;

  /// Whether this phone and language get the precise model at all.
  final Future<bool> Function() eligible;
  final ModelStore vosk;
  final ModelStore precise;

  /// Where the answer is kept: nothing there means it was never answered.
  final FlagStore store;

  /// Whether to offer now: the phone gets the precise model, Vosk's is installed, the precise one
  /// is not, and the person has not answered.
  Future<bool> shouldOffer() async {
    // iOS has no Vosk to improve on: its one model is the precise one, offered as the download.
    if (defaultTargetPlatform == TargetPlatform.iOS) return false;
    try {
      if (!await eligible()) return false;
      if (await vosk.installedPath(locale) == null) return false;
      if (await precise.installedPath(locale) != null) return false;
      return await store.read() == null;
    } on Object {
      // Not knowing is not a reason to interrupt: the sheet just listens.
      return false;
    }
  }

  /// Whether the first-use download of Vosk also fetches the precise model: the phone gets it, it
  /// is not installed for [locale] already, and the person has not said no (or switched it off).
  Future<bool> wantsWithVosk() async {
    // No Vosk download for it to join on iOS.
    if (defaultTargetPlatform == TargetPlatform.iOS) return false;
    try {
      if (!await eligible()) return false;
      if (await precise.installedPath(locale) != null) return false;
      return await store.read() != false;
    } on Object {
      return false;
    }
  }

  /// Remembers the answer: [accepted] true once the precise model is installed, false for "Ahora no".
  Future<void> answer({required bool accepted}) async {
    try {
      await store.write(accepted);
    } on Object {
      // Not kept: it is offered once more at the next start.
    }
  }
}

/// The offer for a voice language.
final preciseOfferProvider = Provider.family<PreciseOffer, String>(
  (ref, locale) => PreciseOffer(
    locale: locale,
    eligible: () => ref.read(preciseEligibleProvider(locale).future),
    vosk: ref.read(modelStoreProvider),
    precise: ref.read(preciseModelStoreProvider),
    store: ref.read(flagStoreProvider('wambito.voice.preciseOffer')),
  ),
);
