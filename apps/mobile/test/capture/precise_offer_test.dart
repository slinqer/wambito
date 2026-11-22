import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/capture/models_download.dart';
import 'package:wambito/capture/precise_offer.dart';
import 'package:wambito/feedback/stored_flag.dart';

import '../settings/fakes.dart' show FakeFlagStore;
import 'fakes.dart';

void main() {
  late FakeModelStore vosk;
  late FakeModelStore canary;
  late FakeFlagStore store;
  var eligible = true;

  PreciseOffer offer() => PreciseOffer(
    locale: 'es',
    eligible: () async => eligible,
    vosk: vosk,
    precise: canary,
    store: store,
  );

  setUp(() {
    vosk = FakeModelStore(installed: true);
    canary = FakeModelStore();
    store = FakeFlagStore();
    eligible = true;
  });

  test('offers to someone with vosk, an eligible phone and no answer yet', () async {
    expect(await offer().shouldOffer(), isTrue);
  });

  test('one-time: after an answer, yes or no, it never comes back', () async {
    await offer().answer(accepted: false);
    expect(await offer().shouldOffer(), isFalse);
    store.value = null;
    await offer().answer(accepted: true);
    expect(await offer().shouldOffer(), isFalse);
  });

  test('not offered without vosk, with canary, or on a phone that does not qualify', () async {
    vosk.installed = false;
    expect(await offer().shouldOffer(), isFalse);
    vosk.installed = true;
    canary.installed = true;
    expect(await offer().shouldOffer(), isFalse);
    canary.installed = false;
    eligible = false;
    expect(await offer().shouldOffer(), isFalse);
  });

  test('on iOS there is no Vosk to improve: no offer, and nothing joins a Vosk download', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(await offer().shouldOffer(), isFalse);
    expect(await offer().wantsWithVosk(), isFalse);
  });

  test('a flag store that throws means no offer, not a crash', () async {
    final broken = PreciseOffer(
      locale: 'es',
      eligible: () async => true,
      vosk: vosk,
      precise: canary,
      store: _Broken(),
    );
    expect(await broken.shouldOffer(), isFalse);
    await broken.answer(accepted: false);
  });

  test('the provider keeps the answer under wambito.voice.preciseOffer', () async {
    final keys = <String>[];
    final container = ProviderContainer(
      overrides: [
        modelStoreProvider.overrideWithValue(vosk),
        preciseModelStoreProvider.overrideWithValue(canary),
        preciseEligibleProvider.overrideWith((ref, locale) async => true),
        flagStoreProvider.overrideWith((ref, key) {
          keys.add(key);
          return store;
        }),
      ],
    );
    addTearDown(container.dispose);
    expect(await container.read(preciseOfferProvider('es')).shouldOffer(), isTrue);
    await container.read(preciseOfferProvider('es')).answer(accepted: false);
    expect(keys, ['wambito.voice.preciseOffer']);
    expect(store.value, isFalse);
  });
}

class _Broken implements FlagStore {
  @override
  Future<bool?> read() => throw StateError('x');
  @override
  Future<void> write(bool on) => throw StateError('x');
  @override
  Future<void> clear() => throw StateError('x');
}
