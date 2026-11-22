// Quick capture (spec section 6.1.4) on home, with a fixed transcript in place of audio.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/gen/wambito_api.dart';
import 'package:wambito/capture/capture_repository.dart';
import 'package:wambito/capture/capture_note.dart';
import 'package:wambito/capture/capture_sheet.dart';
import 'package:wambito/capture/engine/speech_engine.dart';
import 'package:wambito/capture/mic_level.dart';
import 'package:wambito/capture/models_download.dart';
import 'package:wambito/feedback/stored_flag.dart';
import 'package:wambito/home/home_repository.dart';
import 'package:wambito/ui/lk_theme.dart';
import 'package:wambito/ui/press_button.dart';
import 'package:wambito/ui/toast.dart';

import '../home/fakes.dart';
import '../home/fixtures.dart';
import '../home/home_harness.dart';
import '../settings/fakes.dart' show FakeFlagStore;
import 'fakes.dart';

const _sentence = 'gasté 15 mil en almuerzo y 3 lukas en uber';

/// A store that has a model until the engine is first asked to listen.
class _FlippingModels extends FakeModelStore {
  var has = true;

  @override
  bool hasModel(String locale) => has;
}

class _FlippingEngine extends FakeSpeechEngine {
  _FlippingEngine(this.models, {super.failure});

  final _FlippingModels models;

  @override
  Stream<String> listen({required String locale}) {
    models.has = false;
    return super.listen(locale: locale);
  }
}

class _Env {
  _Env(
    this.server,
    this.capture,
    this.engine,
    this.models,
    this.harness,
    this.celebrated, {
    required this.precise,
    required this.offerFlag,
    required this.log,
  });
  final FakeHomeRepository server;
  final FakeCaptureRepository capture;
  final FakeSpeechEngine engine;
  final FakeModelStore models;
  final FakeModelStore precise;
  final FakeFlagStore offerFlag;
  final List<String> log;
  final HomeHarness harness;
  final List<List<Transaction>> celebrated;
}

Future<_Env> _pump(
  WidgetTester tester, {
  List<List<String>> heard = const [
    ['gasté 15 mil', _sentence],
  ],
  SpeechFailure? failure,
  bool available = true,
  Locale locale = const Locale('es'),
  FakeFlagStore? noteFlag,
  bool warm = false,
  bool eligible = false,
  bool voskInstalled = false,
  FakeFlagStore? offerFlag,
  bool ios = false,
}) async {
  final server = FakeHomeRepository(
    categoryList: [
      category('cat-food', 'Comida', icon: '🍽️'),
      category('cat-uber', 'Uber', icon: '🚕'),
      category('cat-salary', 'Nómina', kind: 'income', icon: '💰'),
    ],
    items: [tx('coffee', '2026-10-20', -450000, name: 'Café', categoryId: 'cat-food')],
  );
  final capture = FakeCaptureRepository(server);
  final engine = FakeSpeechEngine(
    transcripts: [...heard],
    failure: failure,
    availableAnswer: available,
  )..warm = warm;
  final log = <String>[];
  final models = FakeModelStore(installed: voskInstalled, log: log);
  final precise = FakeModelStore(models: preciseModels, log: log);
  final answered = offerFlag ?? FakeFlagStore();
  final celebrated = <List<Transaction>>[];
  final harness = await pumpHome(
    tester,
    server,
    locale: locale,
    overrides: [
      captureRepositoryProvider.overrideWithValue(capture),
      speechEngineProvider.overrideWithValue(engine),
      // On iOS the app's model store is the precise one, as the provider itself returns.
      modelStoreProvider.overrideWithValue(ios ? precise : models),
      preciseModelStoreProvider.overrideWithValue(precise),
      preciseEligibleProvider.overrideWith((ref, locale) async => eligible),
      batchSavedFeedbackProvider.overrideWithValue(celebrated.add),
      // Where the first-use note's flag is kept: nothing kept yet unless a test says so.
      flagStoreProvider.overrideWith(
        (ref, key) => switch (key) {
          'setting.capture.note' => noteFlag ?? FakeFlagStore(),
          'wambito.voice.preciseOffer' => answered,
          _ => FakeFlagStore(),
        },
      ),
    ],
  );
  return _Env(
    server,
    capture,
    engine,
    models,
    harness,
    celebrated,
    precise: precise,
    offerFlag: answered,
    log: log,
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('home.capture')));
  await tester.pumpAndSettle();
}

/// Opens it while something keeps moving (a spinner), so it never settles.
Future<void> _openMoving(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('home.capture')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

PressButton _save(WidgetTester tester) =>
    tester.widget<PressButton>(find.byKey(const Key('capture.save')));

Future<void> _pickCategory(WidgetTester tester, int card, String id) async {
  final pick = find.byKey(Key('capture.card.$card.pick'));
  if (pick.evaluate().isNotEmpty) {
    await tester.tap(pick);
    await tester.pumpAndSettle();
  }
  final chip = find.byKey(Key('capture.card.$card.category.$id'));
  await tester.ensureVisible(chip);
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

/// Lets the 8 s of a Deshacer toast pass.
Future<void> _letTimersEnd(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 12));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a fixed transcript "$_sentence" shows two cards and GUARDAR 2', (tester) async {
    final env = await _pump(tester);
    await _open(tester);
    expect(env.engine.listens, 1);
    expect(find.byKey(const Key('capture.card.0')), findsOneWidget);
    expect(find.byKey(const Key('capture.card.1')), findsOneWidget);
    expect(find.byKey(const Key('capture.card.2')), findsNothing);
    expect(find.text(r'−$15.000'), findsOneWidget);
    expect(find.text(r'−$3.000'), findsOneWidget);
    expect(find.text('GUARDAR 2'), findsOneWidget);
    expect(find.text(_sentence), findsOneWidget);
  });

  testWidgets('GUARDAR is disabled until every card has a category', (tester) async {
    await _pump(tester);
    await _open(tester);
    // "uber" is a category's name; "almuerzo" is no category's.
    expect(find.text('ELIGE CATEGORÍA'), findsOneWidget);
    expect(_save(tester).onPressed, isNull);
    await _pickCategory(tester, 0, 'cat-food');
    expect(find.text('ELIGE CATEGORÍA'), findsNothing);
    expect(_save(tester).onPressed, isNotNull);
  });

  testWidgets('a removed card is not saved, and GUARDAR counts what is left', (tester) async {
    final env = await _pump(tester);
    await _open(tester);
    await tester.tap(find.byKey(const Key('capture.card.0.remove')));
    await tester.pumpAndSettle();
    expect(find.text('GUARDAR 1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('capture.save')));
    await tester.pumpAndSettle();
    expect(env.capture.calls.single, endsWith('Uber:300000'));
    await _letTimersEnd(tester);
  });

  testWidgets('an unread fragment shows "No entendí: «…»" and can be completed by hand', (
    tester,
  ) async {
    final env = await _pump(
      tester,
      heard: [
        ['gasté 15 mil en almuerzo y 9,50 en café'],
      ],
    );
    await _open(tester);
    expect(find.text('No entendí: «9,50 en café»'), findsOneWidget);
    expect(find.text('GUARDAR 1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('capture.unread.0.complete')));
    await tester.pumpAndSettle();
    expect(find.text('No entendí: «9,50 en café»'), findsNothing);
    expect(find.text('Falta el monto'), findsOneWidget);
    expect(find.text('GUARDAR 2'), findsOneWidget);
    expect(_save(tester).onPressed, isNull);

    await tester.enterText(find.byKey(const Key('capture.card.1.amount')), '9500');
    await tester.enterText(find.byKey(const Key('capture.card.1.name')), 'café');
    await tester.pumpAndSettle();
    await _pickCategory(tester, 1, 'cat-food');
    await _pickCategory(tester, 0, 'cat-food');
    expect(_save(tester).onPressed, isNotNull);
    await tester.tap(find.byKey(const Key('capture.save')));
    await tester.pumpAndSettle();
    expect(env.capture.calls.single, endsWith('Almuerzo:1500000,Café:950000'));
    await _letTimersEnd(tester);
  });

  testWidgets('saving shows one celebration with the total and one Deshacer that removes both', (
    tester,
  ) async {
    final env = await _pump(tester);
    await _open(tester);
    await _pickCategory(tester, 0, 'cat-food');
    await tester.tap(find.byKey(const Key('capture.save')));
    await tester.pumpAndSettle();

    // The sheet closed; home has both rows; one toast, with the total.
    expect(find.byKey(const Key('capture.sheet')), findsNothing);
    expect(env.capture.calls, hasLength(1));
    expect(find.byType(ToastLayer), findsOneWidget);
    expect(find.text(r'¡Listo! 2 movimientos por $18.000'), findsOneWidget);
    expect(find.text('Deshacer'), findsOneWidget);
    expect(find.text('Almuerzo'), findsOneWidget);
    expect(find.text('Uber'), findsWidgets);
    // Task 13's hook heard about it once, with both rows.
    expect(env.celebrated.single.map((t) => t.name), ['Almuerzo', 'Uber']);

    await tester.tap(find.text('Deshacer'));
    await tester.pumpAndSettle();
    expect(env.capture.calls.last, 'undo batch-1,batch-2');
    expect(env.server.items.map((t) => t.id), ['coffee']);
    expect(find.text('Almuerzo'), findsNothing);
    expect(find.text('Quitados: 2 movimientos'), findsOneWidget);
    await _letTimersEnd(tester);
  });

  testWidgets('a server error keeps the sheet, and Reintentar resends with the same key', (
    tester,
  ) async {
    final env = await _pump(tester);
    await _open(tester);
    await _pickCategory(tester, 0, 'cat-food');
    env.capture.failures['save'] = const HomeFailure(503);
    await tester.tap(find.byKey(const Key('capture.save')));
    await tester.pumpAndSettle();
    // The server failed: the sheet stays, with Reintentar.
    expect(find.byKey(const Key('capture.sheet')), findsOneWidget);
    await tester.tap(find.byKey(const Key('capture.retry')));
    await tester.pumpAndSettle();

    expect(env.capture.keys, hasLength(2));
    expect(env.capture.keys[0], env.capture.keys[1], reason: 'Reintentar reuses the key');
    expect(env.server.items.where((t) => t.id.startsWith('batch-')), hasLength(2));
    expect(find.byKey(const Key('capture.sheet')), findsNothing);
    await _letTimersEnd(tester);
  });

  testWidgets('a lost answer: the batch waits on the phone and goes up later, exactly 2 rows', (
    tester,
  ) async {
    final env = await _pump(tester);
    await _open(tester);
    await _pickCategory(tester, 0, 'cat-food');
    env.capture.loseNextAnswer = true;
    await tester.tap(find.byKey(const Key('capture.save')));
    await tester.pumpAndSettle();

    // The sheet closes and says the rows go up when the network is back; home shows them,
    // marked as not uploaded yet.
    expect(find.byKey(const Key('capture.sheet')), findsNothing);
    expect(find.text('Sin conexión. Los subimos cuando vuelva la red.'), findsOneWidget);
    expect(find.byKey(const Key('row.unsent')), findsNWidgets(2));

    // The queue tries again a few seconds later, with the same key: the server answers with the
    // rows it already has.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(env.capture.keys, hasLength(2));
    expect(env.capture.keys[0], env.capture.keys[1], reason: 'the retry reuses the key');
    expect(env.server.items.where((t) => t.id.startsWith('batch-')), hasLength(2));
    expect(find.byKey(const Key('row.unsent')), findsNothing);
    expect(find.text('Almuerzo'), findsOneWidget);
    await _letTimersEnd(tester);
  });

  testWidgets('a change after a failed save makes a new key', (tester) async {
    final env = await _pump(tester);
    await _open(tester);
    await _pickCategory(tester, 0, 'cat-food');
    env.capture.failures['save'] = const HomeFailure(500);
    await tester.tap(find.byKey(const Key('capture.save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('capture.card.1.remove')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('capture.save')));
    await tester.pumpAndSettle();
    expect(env.capture.keys[0], isNot(env.capture.keys[1]));
    await _letTimersEnd(tester);
  });

  testWidgets('microphone permission denied shows the typing field with one sentence on why', (
    tester,
  ) async {
    final env = await _pump(
      tester,
      failure: const SpeechFailure(SpeechFailureKind.permissionDenied),
    );
    await _open(tester);
    expect(find.byKey(const Key('capture.field')), findsOneWidget);
    // A sentence typed keeps the phone's suggestion strip; autocorrect never rewrites an amount.
    final typing = tester.widget<EditableText>(find.byKey(const Key('capture.field')));
    expect(typing.enableSuggestions, isTrue);
    expect(typing.autocorrect, isFalse);
    expect(
      find.text('Sin permiso para el micrófono no puedo escucharte, así que escríbelo aquí.'),
      findsOneWidget,
    );
    // Typing works as well as speaking.
    await tester.enterText(find.byKey(const Key('capture.field')), _sentence);
    await tester.tap(find.byKey(const Key('capture.read')));
    await tester.pumpAndSettle();
    expect(find.text('GUARDAR 2'), findsOneWidget);
    expect(env.engine.listens, 1);
  });

  testWidgets('no engine available behaves the same', (tester) async {
    final env = await _pump(tester, available: false);
    await _open(tester);
    expect(env.engine.listens, 0);
    expect(find.byKey(const Key('capture.field')), findsOneWidget);
    expect(
      find.text('Este teléfono no puede escuchar con Wambito, así que escríbelo aquí.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('capture.listen')), findsNothing);
  });

  for (final (language, sentence, save, offer) in [
    ('it', 'ho speso quindici euro per il pranzo', 'SALVA 1', 'SCARICA'),
    ('pt', 'gastei quinze euros no almoço', 'GUARDAR 1', 'DESCARREGAR'),
  ]) {
    testWidgets('in $language the sheet listens and reads what it hears', (tester) async {
      final env = await _pump(
        tester,
        locale: Locale(language),
        heard: [
          [sentence],
        ],
      );
      await _open(tester);
      expect(env.engine.listens, 1);
      expect(env.engine.locales, [language], reason: 'its own voice, never the Spanish one');
      expect(find.text(save), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('in $language the opt-in names its own model\'s size', (tester) async {
      final env = await _pump(
        tester,
        locale: Locale(language),
        failure: const SpeechFailure(SpeechFailureKind.noModel),
      );
      await _open(tester);
      final mb = (voiceModels[language]!.bytes / 1e6).round();
      expect(find.text('$offer $mb MB'), findsOneWidget);
      await tester.tap(find.byKey(const Key('capture.offer.download')));
      await tester.pumpAndSettle();
      expect(env.models.downloads, 1);
      expect(env.models.downloaded, [language], reason: 'never the Spanish model');
      expect(env.engine.listens, 2);
    });
  }

  for (final (language, why) in [
    ('it', 'Per ora non ti ascolto in questa lingua, quindi scrivilo qui.'),
    ('pt', 'Por agora não te ouço neste idioma, por isso escreve aqui.'),
  ]) {
    testWidgets(
      'in $language a late "no model" (a language that has none) types, and never offers a download',
      (tester) async {
        // The language has a model when listening starts (so listen() goes ahead), and none by the
        // time the engine says noModel: the late branch must still end on the typing field.
        final models = _FlippingModels();
        final engine = _FlippingEngine(
          models,
          failure: const SpeechFailure(SpeechFailureKind.noModel),
        );
        final server = FakeHomeRepository(
          categoryList: [category('cat-food', 'Comida', icon: '🍽️')],
          items: [tx('coffee', '2026-10-20', -450000, name: 'Café', categoryId: 'cat-food')],
        );
        await pumpHome(
          tester,
          server,
          locale: Locale(language),
          overrides: [
            captureRepositoryProvider.overrideWithValue(FakeCaptureRepository(server)),
            speechEngineProvider.overrideWithValue(engine),
            modelStoreProvider.overrideWithValue(models),
          ],
        );
        await _open(tester);
        expect(engine.listens, 1, reason: 'listening started, then the engine said noModel');
        expect(find.byKey(const Key('capture.offer.download')), findsNothing);
        expect(find.byKey(const Key('capture.field')), findsOneWidget);
        expect(find.text(why), findsOneWidget);
        expect(models.downloads, 0);
      },
    );
  }

  testWidgets('without the model, an opt-in shows its size; declining leaves the typing field', (
    tester,
  ) async {
    final env = await _pump(tester, failure: const SpeechFailure(SpeechFailureKind.noModel));
    await _open(tester);
    final mb = (voiceModels['es']!.bytes / 1e6).round();
    expect(find.text('DESCARGAR $mb MB'), findsOneWidget);
    await tester.tap(find.byKey(const Key('capture.offer.decline')));
    await tester.pumpAndSettle();
    expect(env.models.downloads, 0);
    expect(find.byKey(const Key('capture.field')), findsOneWidget);
  });

  testWidgets('accepting the opt-in downloads the model, then listens', (tester) async {
    final env = await _pump(tester, failure: const SpeechFailure(SpeechFailureKind.noModel));
    await _open(tester);
    await tester.tap(find.byKey(const Key('capture.offer.download')));
    await tester.pumpAndSettle();
    expect(env.models.downloads, 1);
    expect(env.engine.listens, 2);
    expect(find.text('GUARDAR 2'), findsOneWidget);
  });

  group('on iOS the precise model is the only one', () {
    const noModel = SpeechFailure(SpeechFailureKind.noModel);

    // The framework checks the override is back before tearDown runs, so the tests reset it.
    void ios() {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
    }

    void reset() => debugDefaultTargetPlatformOverride = null;

    testWidgets('a phone that does not qualify types, with the no-engine note and no offer', (
      tester,
    ) async {
      ios();
      final env = await _pump(tester, locale: const Locale('it'), ios: true);
      await _open(tester);
      expect(find.byKey(const Key('capture.offer.download')), findsNothing);
      expect(find.byKey(const Key('capture.field')), findsOneWidget);
      expect(find.byKey(const Key('capture.note')), findsOneWidget);
      expect(env.engine.listens, 0);
      reset();
    });

    testWidgets('a phone that qualifies, with no model yet: the offer shows Canary\'s size', (
      tester,
    ) async {
      ios();
      final env = await _pump(tester, failure: noModel, eligible: true, ios: true);
      await _open(tester);
      final mb = (preciseModels['es']!.bytes / 1e6).round();
      expect(find.text('DESCARGAR $mb MB'), findsOneWidget);
      expect(env.precise.downloads, 0);
      reset();
    });
  });

  group('the precise model (canary)', () {
    const noModel = SpeechFailure(SpeechFailureKind.noModel);
    final voskMb = voiceModels['es']!.bytes;
    final canaryMb = preciseModels['es']!.bytes;
    final joint = ((voskMb + canaryMb) / 1e6).round();

    testWidgets('an eligible phone sees the joint size, and vosk lands before canary', (
      tester,
    ) async {
      final env = await _pump(tester, failure: noModel, eligible: true);
      await _open(tester);
      expect(find.text('DESCARGAR $joint MB'), findsOneWidget);
      await tester.tap(find.byKey(const Key('capture.offer.download')));
      await tester.pumpAndSettle();
      expect(env.log, [voiceModels['es']!.name, preciseModels['es']!.name]);
      expect(env.precise.downloaded, ['es']);
      expect(env.engine.listens, 2);
    });

    testWidgets('canary already installed: the offer is vosk\'s size and downloads only vosk', (
      tester,
    ) async {
      // e.g. es Vosk and Canary, the app switched to a language whose Vosk is missing.
      final env = await _pump(tester, failure: noModel, eligible: true);
      env.precise.installed = true;
      await _open(tester);
      expect(find.text('DESCARGAR ${(voskMb / 1e6).round()} MB'), findsOneWidget);
      await tester.tap(find.byKey(const Key('capture.offer.download')));
      await tester.pumpAndSettle();
      expect(env.log, [voiceModels['es']!.name]);
      expect(env.precise.downloads, 0);
    });

    testWidgets('a recorded "no" to the precise model: the joint offer is vosk only', (
      tester,
    ) async {
      final env = await _pump(
        tester,
        failure: noModel,
        eligible: true,
        offerFlag: FakeFlagStore(false),
      );
      await _open(tester);
      expect(find.text('DESCARGAR ${(voskMb / 1e6).round()} MB'), findsOneWidget);
      await tester.tap(find.byKey(const Key('capture.offer.download')));
      await tester.pumpAndSettle();
      expect(env.log, [voiceModels['es']!.name]);
      expect(env.precise.downloads, 0);
      expect(env.offerFlag.value, isFalse, reason: 'the "no" stays');
    });

    testWidgets('one progress bar runs over both downloads', (tester) async {
      final env = await _pump(tester, failure: noModel, eligible: true);
      env.precise.gate = Completer<void>();
      await _open(tester);
      await tester.tap(find.byKey(const Key('capture.offer.download')));
      await tester.pump(const Duration(milliseconds: 100));
      final done = ((voskMb + canaryMb ~/ 2) / (voskMb + canaryMb) * 100).floor();
      expect(find.text('Descargando la voz… $done %'), findsOneWidget);
      env.precise.gate!.complete();
      await tester.pumpAndSettle();
      expect(env.engine.listens, 2);
    });

    testWidgets('vosk lands first, and listening works when canary fails', (tester) async {
      final env = await _pump(tester, failure: noModel, eligible: true);
      env.precise.failure = const ModelDownloadFailure();
      await _open(tester);
      await tester.tap(find.byKey(const Key('capture.offer.download')));
      await tester.pumpAndSettle();
      expect(env.models.downloads, 1);
      expect(env.precise.downloads, 1);
      expect(env.engine.listens, 2, reason: 'it listens with vosk');
      expect(find.byKey(const Key('capture.offer.download')), findsNothing);
      expect(env.offerFlag.value, isNull, reason: 'a failure is not an answer');
      expect(
        find.text('No pudimos descargar el modelo preciso. Inténtalo otra vez.'),
        findsOneWidget,
      );
    });

    testWidgets('a joint download that installs canary records the offer as answered', (
      tester,
    ) async {
      final env = await _pump(tester, failure: noModel, eligible: true);
      await _open(tester);
      await tester.tap(find.byKey(const Key('capture.offer.download')));
      await tester.pumpAndSettle();
      expect(env.offerFlag.value, isTrue);
    });

    testWidgets('canary switched off in Settings: the sheet listens, with no offer', (
      tester,
    ) async {
      // Settings records the switch's answer; the canary files are gone.
      final env = await _pump(
        tester,
        eligible: true,
        voskInstalled: true,
        offerFlag: FakeFlagStore(false),
      );
      expect(env.precise.installed, isFalse);
      await _open(tester);
      expect(find.byKey(const Key('capture.offer.precise.accept')), findsNothing);
      expect(env.engine.listens, 1);
    });

    testWidgets('a phone that does not qualify sees today\'s offer and gets no canary', (
      tester,
    ) async {
      final env = await _pump(tester, failure: noModel);
      await _open(tester);
      expect(find.text('DESCARGAR ${(voskMb / 1e6).round()} MB'), findsOneWidget);
      await tester.tap(find.byKey(const Key('capture.offer.download')));
      await tester.pumpAndSettle();
      expect(env.precise.downloads, 0);
    });

    testWidgets('someone with vosk is offered canary once, before listening', (tester) async {
      final env = await _pump(tester, eligible: true, voskInstalled: true);
      await _open(tester);
      expect(env.engine.listens, 0);
      expect(find.text('Mejorar la precisión (+${(canaryMb / 1e6).round()} MB)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('capture.offer.precise.decline')));
      await tester.pumpAndSettle();
      expect(env.precise.downloads, 0);
      expect(env.offerFlag.value, isFalse);
      expect(env.engine.listens, 1);
    });

    testWidgets('the one-time offer shows once: answered, it listens at once', (tester) async {
      final env = await _pump(
        tester,
        eligible: true,
        voskInstalled: true,
        offerFlag: FakeFlagStore(false),
      );
      await _open(tester);
      expect(find.byKey(const Key('capture.offer.precise.accept')), findsNothing);
      expect(env.engine.listens, 1);
    });

    testWidgets('"Mejorar" downloads canary only, records it, then listens', (tester) async {
      final env = await _pump(tester, eligible: true, voskInstalled: true);
      await _open(tester);
      await tester.tap(find.byKey(const Key('capture.offer.precise.accept')));
      await tester.pumpAndSettle();
      expect(env.models.downloads, 0);
      expect(env.precise.downloaded, ['es']);
      expect(env.offerFlag.value, isTrue);
      expect(env.engine.listens, 1);
    });

    testWidgets('"Mejorar" that fails still listens, and the offer stays open', (tester) async {
      final env = await _pump(tester, eligible: true, voskInstalled: true);
      env.precise.failure = const ModelDownloadFailure();
      await _open(tester);
      await tester.tap(find.byKey(const Key('capture.offer.precise.accept')));
      await tester.pumpAndSettle();
      expect(env.engine.listens, 1);
      expect(env.offerFlag.value, isNull);
      expect(
        find.text('No pudimos descargar el modelo preciso. Inténtalo otra vez.'),
        findsOneWidget,
      );
    });

    testWidgets('someone who already has canary is not offered it', (tester) async {
      final env = await _pump(tester, eligible: true, voskInstalled: true);
      env.precise.installed = true;
      await _open(tester);
      expect(find.byKey(const Key('capture.offer.precise.accept')), findsNothing);
      expect(env.engine.listens, 1);
    });
  });

  testWidgets('a corrupt download says so and offers it again', (tester) async {
    final env = await _pump(tester, failure: const SpeechFailure(SpeechFailureKind.noModel));
    env.models.failure = const ModelDownloadFailure(corrupt: true);
    await _open(tester);
    await tester.tap(find.byKey(const Key('capture.offer.download')));
    await tester.pumpAndSettle();
    expect(find.text('La voz llegó dañada y la borramos. Inténtalo de nuevo.'), findsOneWidget);
    expect(find.byKey(const Key('capture.offer.download')), findsOneWidget);
  });

  testWidgets('opened to type (listen: false), nothing listens', (tester) async {
    final env = await _pump(tester);
    final context = tester.element(find.byKey(const Key('home.add')));
    // ignore: unawaited_futures
    openCapture(context, listen: false);
    await tester.pumpAndSettle();
    expect(env.engine.listens, 0);
    expect(find.byKey(const Key('capture.field')), findsOneWidget);
  });

  testWidgets('in English the copy is English', (tester) async {
    await _pump(
      tester,
      locale: const Locale('en'),
      heard: [
        ['spent 15 on lunch and 3 on uber'],
      ],
    );
    await _open(tester);
    expect(find.text('SAVE 2'), findsOneWidget);
    expect(find.text('PICK A CATEGORY'), findsOneWidget);
  });

  testWidgets('"¿En qué gastaste?" shows only once the engine is ready', (tester) async {
    final env = await _pump(tester);
    env.engine.hold = true;
    await _openMoving(tester);
    expect(find.text('¿En qué gastaste?'), findsNothing);
    expect(find.text('Preparando el micrófono…'), findsOneWidget);
    env.engine.held!.add('');
    await tester.pump();
    expect(find.text('¿En qué gastaste?'), findsOneWidget);
    expect(find.text('Preparando el micrófono…'), findsNothing);
    await env.engine.held!.close();
    await tester.pumpAndSettle();
  });

  testWidgets('refining shows the label over the heard text', (tester) async {
    final env = await _pump(tester);
    env.engine.hold = true;
    await _openMoving(tester);
    env.engine.held!
      ..add('')
      ..add('gasté 15 mil');
    await tester.pump();
    expect(find.text('Refinando…'), findsNothing);
    env.engine.refiningController.add(true);
    await tester.pump();
    expect(find.text('Refinando…'), findsOneWidget);
    expect(find.text('gasté 15 mil'), findsOneWidget);
    final heard = tester.widget<Text>(find.byKey(const Key('capture.heard')));
    final muted = tester.element(find.byKey(const Key('capture.heard'))).lkColors.inkMuted;
    expect(heard.style?.color, muted);
    expect(find.bySemanticsLabel('Refinando…'), findsOneWidget);
    final live = tester.getSemantics(find.byKey(const Key('capture.refining')));
    expect(live.flagsCollection.isLiveRegion, isTrue);
    env.engine.refiningController.add(false);
    await tester.pump();
    expect(find.text('Refinando…'), findsNothing);
    await env.engine.held!.close();
    await tester.pumpAndSettle();
  });

  testWidgets('Listo is disabled while refining, Escribir is not', (tester) async {
    final env = await _pump(tester);
    env.engine.hold = true;
    await _openMoving(tester);
    env.engine.held!
      ..add('')
      ..add('gasté 15 mil');
    await tester.pump();
    PressButton button(String key) => tester.widget<PressButton>(find.byKey(Key(key)));
    expect(button('capture.stop').onPressed, isNotNull);
    env.engine.refiningController.add(true);
    await tester.pump();
    expect(button('capture.stop').onPressed, isNull);
    expect(button('capture.type').onPressed, isNotNull);
    env.engine.refiningController.add(false);
    await tester.pump();
    expect(button('capture.stop').onPressed, isNotNull);
    await env.engine.held!.close();
    await tester.pumpAndSettle();
  });

  testWidgets('the preview follows the refined text', (tester) async {
    final env = await _pump(tester);
    env.engine.hold = true;
    await _openMoving(tester);
    env.engine.held!
      ..add('')
      ..add('dos euros en cafe');
    await tester.pump();
    env.engine.refiningController.add(true);
    await tester.pump();
    env.engine.held!.add('Dos euros en café.');
    env.engine.refiningController.add(false);
    await tester.pump();
    expect(find.text('Refinando…'), findsNothing);
    await env.engine.held!.close();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('capture.card.0')), findsOneWidget);
    expect(find.text('Dos euros en café.'), findsOneWidget);
    expect(find.text(r'−$2'), findsOneWidget);
  });

  Future<_Env> refiningNow(WidgetTester tester) async {
    final env = await _pump(tester);
    env.engine.hold = true;
    await _openMoving(tester);
    env.engine.held!
      ..add('')
      ..add('gasté 15 mil');
    await tester.pump();
    env.engine.refiningController.add(true);
    await tester.pump();
    expect(find.text('Refinando…'), findsOneWidget);
    return env;
  }

  testWidgets('a listen error while refining takes the label away', (tester) async {
    final env = await refiningNow(tester);
    env.engine.held!.addError(const SpeechFailure(SpeechFailureKind.failed));
    await tester.pumpAndSettle();
    expect(find.text('Refinando…'), findsNothing);
    expect(find.byKey(const Key('capture.field')), findsOneWidget);
  });

  testWidgets('Escribir while refining takes the label away', (tester) async {
    final env = await refiningNow(tester);
    await tester.tap(find.byKey(const Key('capture.type')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Refinando…'), findsNothing);
    expect(find.byKey(const Key('capture.field')), findsOneWidget);
    unawaited(env.engine.held?.close());
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('closing the sheet while refining throws nothing', (tester) async {
    final env = await refiningNow(tester);
    Navigator.of(tester.element(find.byKey(const Key('capture.stop')))).pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('capture.stop')), findsNothing);
    env.engine.refiningController.add(false);
    env.engine.refiningController.add(true);
    await tester.pump();
    unawaited(env.engine.held?.close());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a new listen starts with no label', (tester) async {
    final env = await refiningNow(tester);
    await tester.tap(find.byKey(const Key('capture.type')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('capture.listen')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Refinando…'), findsNothing);
    env.engine.held!.add('');
    await tester.pump();
    expect(find.text('Refinando…'), findsNothing);
    await env.engine.held!.close();
    await tester.pumpAndSettle();
  });

  testWidgets('going to the background stops listening at once and keeps what was heard', (
    tester,
  ) async {
    final env = await _pump(tester);
    env.engine.hold = true;
    await _openMoving(tester);
    env.engine.held!
      ..add('')
      ..add('gasté 15 mil');
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(env.engine.cancels, 0, reason: 'a dialog over the app is not the background');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pumpAndSettle();
    expect(env.engine.cancels, 1);
    expect(env.engine.stops, greaterThanOrEqualTo(1));
    expect(find.byKey(const Key('capture.field')), findsOneWidget);
    expect(find.text('gasté 15 mil'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(env.engine.listens, 1, reason: 'coming back does not listen by itself');
  });

  testWidgets('a download that fails leaves Descargando with a message and Reintentar', (
    tester,
  ) async {
    final env = await _pump(tester, failure: const SpeechFailure(SpeechFailureKind.noModel));
    env.models.failure = const ModelDownloadFailure();
    await _open(tester);
    await tester.tap(find.byKey(const Key('capture.offer.download')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Descargando'), findsNothing);
    expect(
      find.text(
        'No se pudo descargar la voz. Revisa tu internet e inténtalo de nuevo; seguirá donde quedó.',
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('capture.offer.download')),
        matching: find.text('REINTENTAR'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('capture.offer.download')));
    await tester.pumpAndSettle();
    expect(env.models.downloads, 2);
    expect(find.text('GUARDAR 2'), findsOneWidget);
  });

  testWidgets('any other error from the download comes back to the offer too', (tester) async {
    final env = await _pump(tester, failure: const SpeechFailure(SpeechFailureKind.noModel));
    env.models.error = const FileSystemException('No space left on device');
    await _open(tester);
    await tester.tap(find.byKey(const Key('capture.offer.download')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Descargando'), findsNothing);
    expect(find.byKey(const Key('capture.offer.download')), findsOneWidget);
  });

  testWidgets('too little free space says how much the voice needs', (tester) async {
    final env = await _pump(tester, failure: const SpeechFailure(SpeechFailureKind.noModel));
    env.models.failure = const ModelDownloadFailure(noSpace: true);
    await _open(tester);
    await tester.tap(find.byKey(const Key('capture.offer.download')));
    await tester.pumpAndSettle();
    final model = voiceModels['es']!;
    final mb = ((model.bytes + model.unzippedBytes) / 1e6).round();
    expect(
      find.text('No hay espacio en el teléfono: la voz necesita unos $mb MB libres.'),
      findsOneWidget,
    );
  });

  testWidgets('in English a failed download says so and offers Retry', (tester) async {
    final env = await _pump(
      tester,
      locale: const Locale('en'),
      failure: const SpeechFailure(SpeechFailureKind.noModel),
    );
    env.models.failure = const ModelDownloadFailure();
    await _open(tester);
    await tester.tap(find.byKey(const Key('capture.offer.download')));
    await tester.pumpAndSettle();
    expect(find.textContaining("The voice didn't download"), findsOneWidget);
    expect(find.text('TRY AGAIN'), findsOneWidget);
  });

  testWidgets('after a failed save, a change that changes nothing keeps the key: 2 rows', (
    tester,
  ) async {
    final env = await _pump(tester);
    await _open(tester);
    await _pickCategory(tester, 0, 'cat-food');
    env.capture.failures['save'] = const HomeFailure(503);
    await tester.tap(find.byKey(const Key('capture.save')));
    await tester.pumpAndSettle();
    // The same category picked again: the batch is what it was.
    await tester.tap(find.text('almuerzo'));
    await tester.pumpAndSettle();
    await _pickCategory(tester, 0, 'cat-food');
    await tester.tap(find.byKey(const Key('capture.save')));
    await tester.pumpAndSettle();
    expect(env.capture.keys, hasLength(2));
    expect(env.capture.keys[0], env.capture.keys[1]);
    expect(env.server.items.where((t) => t.id.startsWith('batch-')), hasLength(2));
    await _letTimersEnd(tester);
  });

  testWidgets('A, then B, then A again keeps A\'s key: still exactly 2 rows', (tester) async {
    final env = await _pump(tester);
    await _open(tester);
    await _pickCategory(tester, 0, 'cat-food');
    env.capture.failures['save'] = const HomeFailure(503);
    await tester.tap(find.byKey(const Key('capture.save')));
    await tester.pumpAndSettle();
    // B: another category, saved and refused; then A again.
    await tester.tap(find.text('almuerzo'));
    await tester.pumpAndSettle();
    await _pickCategory(tester, 0, 'cat-uber');
    env.capture.failures['save'] = const HomeFailure(500);
    await tester.tap(find.byKey(const Key('capture.save')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('almuerzo'));
    await tester.pumpAndSettle();
    await _pickCategory(tester, 0, 'cat-food');
    await tester.tap(find.byKey(const Key('capture.save')));
    await tester.pumpAndSettle();
    expect(env.capture.keys, hasLength(3));
    expect(env.capture.keys[1], isNot(env.capture.keys[0]));
    expect(env.capture.keys[2], env.capture.keys[0]);
    expect(env.server.items.where((t) => t.id.startsWith('batch-')), hasLength(2));
    await _letTimersEnd(tester);
  });

  testWidgets('if the app goes to the background before listening starts, it waits to be back', (
    tester,
  ) async {
    final env = await _pump(tester);
    env.engine.availableGate = Completer<void>();
    await _openMoving(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    env.engine.availableGate!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(env.engine.listens, 0, reason: 'the microphone never opens unseen');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(env.engine.listens, 1);
    expect(find.text('GUARDAR 2'), findsOneWidget);
  });

  group('the first-use note', () {
    const note = 'Te escucho aquí mismo: lo que dices no sale de tu teléfono.';

    testWidgets('the first time, it shows under the prompt', (tester) async {
      final env = await _pump(tester);
      env.engine.hold = true;
      await _openMoving(tester);
      env.engine.held!.add('');
      await tester.pump();
      expect(find.text('¿En qué gastaste?'), findsOneWidget);
      expect(find.text(note), findsOneWidget);
      await env.engine.held!.close();
      await tester.pumpAndSettle();
    });

    testWidgets('once a capture was saved, it never shows again', (tester) async {
      final noteFlag = FakeFlagStore(false);
      final env = await _pump(tester, noteFlag: noteFlag);
      env.engine.hold = true;
      await _openMoving(tester);
      env.engine.held!.add('');
      await tester.pump();
      expect(find.text('¿En qué gastaste?'), findsOneWidget);
      expect(find.text(note), findsNothing);
      await env.engine.held!.close();
      await tester.pumpAndSettle();
    });

    testWidgets('it is kept as seen only when a capture is saved, not when one is opened', (
      tester,
    ) async {
      final noteFlag = FakeFlagStore();
      await _pump(tester, noteFlag: noteFlag);
      await _open(tester);
      expect(noteFlag.value, isNull, reason: 'a sheet that read a sentence has saved nothing yet');
      await _pickCategory(tester, 0, 'cat-food');
      await tester.tap(find.byKey(const Key('capture.save')));
      await tester.pumpAndSettle();
      expect(noteFlag.value, isFalse, reason: 'the first successful capture: no more note');
      await _letTimersEnd(tester);
    });

    testWidgets('a save that fails keeps the note for the next time', (tester) async {
      final noteFlag = FakeFlagStore();
      final env = await _pump(tester, noteFlag: noteFlag);
      await _open(tester);
      await _pickCategory(tester, 0, 'cat-food');
      env.capture.failures['save'] = const HomeFailure(500);
      await tester.tap(find.byKey(const Key('capture.save')));
      await tester.pumpAndSettle();
      expect(noteFlag.value, isNull);
    });

    testWidgets('opened to type, listening again later still shows it the first time', (
      tester,
    ) async {
      final env = await _pump(tester);
      env.engine.hold = true;
      await _openMoving(tester);
      env.engine.held!.add('');
      await tester.pump();
      expect(find.text(note), findsOneWidget);
      await tester.tap(find.byKey(const Key('capture.type')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(note), findsNothing, reason: 'the typing field has no note');
      await tester.tap(find.byKey(const Key('capture.listen')));
      await tester.pump(const Duration(milliseconds: 300));
      env.engine.held!.add('');
      await tester.pump();
      expect(find.text(note), findsOneWidget);
      await env.engine.held!.close();
      await tester.pumpAndSettle();
    });

    test('it is a stored flag, on until the first capture', () {
      final container = ProviderContainer(
        overrides: [flagStoreProvider.overrideWith((ref, key) => FakeFlagStore())],
      );
      addTearDown(container.dispose);
      expect(container.read(captureNoteProvider), isTrue);
      expect(container.read(captureNoteProvider.notifier), isA<StoredFlag>());
    });
  });

  group('listening starts at once when the engine is warm', () {
    testWidgets('no "preparing" state: the prompt and the level show from the first frame', (
      tester,
    ) async {
      final env = await _pump(tester, warm: true);
      env.engine.hold = true;
      await _openMoving(tester);
      // Nothing has come from the engine yet: not even its first event.
      expect(env.engine.listens, 1);
      expect(find.text('Preparando el micrófono…'), findsNothing);
      expect(find.text('¿En qué gastaste?'), findsOneWidget);
      expect(find.byType(MicLevel), findsOneWidget);
      await env.engine.held!.close();
      await tester.pumpAndSettle();
    });

    testWidgets('not warm: "preparing" shows until the engine says it listens', (tester) async {
      final env = await _pump(tester, warm: false);
      env.engine.hold = true;
      await _openMoving(tester);
      expect(find.text('Preparando el micrófono…'), findsOneWidget);
      expect(find.text('¿En qué gastaste?'), findsNothing);
      env.engine.held!.add('');
      await tester.pump();
      expect(find.text('Preparando el micrófono…'), findsNothing);
      expect(find.text('¿En qué gastaste?'), findsOneWidget);
      await env.engine.held!.close();
      await tester.pumpAndSettle();
    });

    testWidgets('listening again after the first time is warm too', (tester) async {
      final env = await _pump(tester, warm: false);
      env.engine.hold = true;
      await _openMoving(tester);
      env.engine.held!.add('');
      await tester.pump();
      await tester.tap(find.byKey(const Key('capture.type')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('capture.listen')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Preparando el micrófono…'), findsNothing);
      await env.engine.held!.close();
      await tester.pumpAndSettle();
    });

    testWidgets('the sheet never loads or records on its own: only a listen does', (tester) async {
      final env = await _pump(tester, warm: true);
      await tester.tap(find.byKey(const Key('home.capture')));
      await tester.pump();
      // Opened to type (listen: false) asks nothing of the microphone.
      expect(env.engine.listens, lessThanOrEqualTo(1));
      await tester.pumpAndSettle();
    });
  });

  group('the live microphone level', () {
    testWidgets('while listening, the bars follow the engine\'s levels', (tester) async {
      final env = await _pump(tester, warm: true);
      env.engine.hold = true;
      await _openMoving(tester);
      final bars = find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('mic.bar.'),
      );
      expect(bars, findsWidgets);
      final last = find.byKey(const Key('mic.bar.${MicLevel.defaultBars - 1}'));
      final quiet = tester.getSize(last).height;
      env.engine.levelsController.add(0.9);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.getSize(last).height, greaterThan(quiet + 20));
      await env.engine.held!.close();
      await tester.pumpAndSettle();
    });

    testWidgets('it is gone with the listening stage', (tester) async {
      final env = await _pump(tester, warm: true);
      env.engine.hold = true;
      await _openMoving(tester);
      expect(find.byType(MicLevel), findsOneWidget);
      await tester.tap(find.byKey(const Key('capture.type')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(MicLevel), findsNothing);
      expect(env.engine.levelsController.hasListener, isFalse);
    });
  });
}
