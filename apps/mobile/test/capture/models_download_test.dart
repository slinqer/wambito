// The voice model download (lib/capture/models_download.dart) against a fake HTTP server on this
// machine, standing in for the repo's GitHub release (tag voice-models-v1), which does not exist
// yet. The server honours Range, can cut a download short, redirect, or ignore Range.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/capture/engine/voice_channel.dart';
import 'package:wambito/capture/models_download.dart';

/// A zip's bytes for the tests: what is in it does not matter, the unzip is faked.
final _payload = Uint8List.fromList(List<int>.generate(300 * 1024, (i) => (i * 31 + 7) % 251));

class _FakeServer {
  late final HttpServer _server;

  /// Every request: its path and Range header.
  final requests = <({String path, String? range})>[];

  /// The next response stops after this many body bytes, then the connection drops.
  int? cutAfter;

  /// Answers 200 with the whole file even when a Range is asked for.
  var ignoreRange = false;

  /// Sends `/release/...` to `/objects/...` with a 302 first, as GitHub does.
  var redirect = false;

  /// Sends the body in small pieces, slowly.
  var slow = false;

  /// A 206 answer says it starts here instead of where it was asked to.
  int? wrongRangeStart;

  Uint8List body = _payload;

  Uri get base => Uri.parse('http://127.0.0.1:${_server.port}/release');

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final range = request.headers.value(HttpHeaders.rangeHeader);
    requests.add((path: request.uri.path, range: range));
    final response = request.response;
    if (redirect && request.uri.path.startsWith('/release/')) {
      await response.redirect(
        request.uri.replace(path: request.uri.path.replaceFirst('/release/', '/objects/')),
        status: HttpStatus.found,
      );
      return;
    }
    var from = 0;
    var status = HttpStatus.ok;
    String? contentRange;
    final match = range == null ? null : RegExp(r'^bytes=(\d+)-$').firstMatch(range);
    if (match != null && !ignoreRange) {
      from = wrongRangeStart ?? int.parse(match.group(1)!);
      wrongRangeStart = null;
      if (from >= body.length) {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        await response.close();
        return;
      }
      status = HttpStatus.partialContent;
      contentRange = 'bytes $from-${body.length - 1}/${body.length}';
    }
    final slice = body.sublist(from);
    final cut = cutAfter;
    if (cut != null) {
      cutAfter = null;
      // Raw HTTP, so the connection can drop mid-body.
      final socket = await response.detachSocket(writeHeaders: false);
      socket.write(
        'HTTP/1.1 $status X\r\n'
        'content-length: ${slice.length}\r\n'
        '${contentRange == null ? '' : 'content-range: $contentRange\r\n'}'
        'connection: close\r\n\r\n',
      );
      socket.add(slice.sublist(0, cut));
      await socket.flush();
      socket.destroy();
      return;
    }
    response.statusCode = status;
    if (contentRange != null) response.headers.set(HttpHeaders.contentRangeHeader, contentRange);
    response.contentLength = slice.length;
    if (slow) {
      for (var i = 0; i < slice.length; i += 16 * 1024) {
        response.add(slice.sublist(i, i + 16 * 1024 > slice.length ? slice.length : i + 16 * 1024));
        await response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await response.close();
      return;
    }
    response.add(slice);
    await response.close();
  }
}

class _FakeFiles implements ModelFiles {
  _FakeFiles(this.root);

  final Directory root;
  final unzipped = <String>[];
  var released = 0;

  /// Free space where the models go; null: unknown.
  int? free = 1 << 40;

  /// The free-space question fails outright.
  var freeFails = false;

  @override
  Future<int?> freeBytes() async {
    if (freeFails) throw StateError('statfs failed');
    return free;
  }

  @override
  Future<String> modelsDirectory() async => root.path;

  @override
  Future<void> unzip(String zip, String into) async {
    unzipped.add(zip);
    // The official zips hold one folder named after the model.
    final name = zip.split('/').last.replaceAll(RegExp(r'\.zip(\.part)?$'), '');
    await Directory('$into/$name/am').create(recursive: true);
  }

  @override
  Future<void> releaseModels() async => released++;
}

VoiceModel _model(Uint8List bytes) => VoiceModel(
  locale: 'es',
  name: 'vosk-model-small-es-0.42',
  bytes: bytes.length,
  unzippedBytes: bytes.length * 2,
  sha256: sha256.convert(bytes).toString(),
);

VoiceModel _modelNamed(String locale, String name, Uint8List bytes) => VoiceModel(
  locale: locale,
  name: name,
  bytes: bytes.length,
  unzippedBytes: bytes.length * 2,
  sha256: sha256.convert(bytes).toString(),
);

void main() {
  late _FakeServer server;
  late Directory root;
  late _FakeFiles files;

  setUp(() async {
    server = _FakeServer();
    await server.start();
    root = await Directory.systemTemp.createTemp('voice-models');
    files = _FakeFiles(root);
  });

  tearDown(() async {
    await server.close();
    await root.delete(recursive: true);
  });

  ModelStore store({VoiceModel? model}) => ModelStore(
    files: files,
    http: Dio(),
    releaseUrl: server.base,
    models: {'es': model ?? _model(_payload)},
  );

  test('the constants name this repo\'s release, one official zip per language', () {
    expect(
      voiceModelsReleaseUrl.toString(),
      'https://github.com/slinqer/wambito/releases/download/voice-models-v1',
    );
    expect(voiceModels['es']!.fileName, 'vosk-model-small-es-0.42.zip');
    expect(voiceModels['en']!.fileName, 'vosk-model-small-en-us-0.15.zip');
    expect(voiceModels['it']!.fileName, 'vosk-model-small-it-0.22.zip');
    expect(voiceModels['pt']!.fileName, 'vosk-model-small-pt-0.3.zip');
    for (final model in voiceModels.values) {
      expect(model.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(model.bytes, greaterThan(30 * 1000 * 1000));
      expect(model.unzippedBytes, greaterThan(model.bytes));
    }
  });

  test('nothing is installed at first; a download verifies, unzips and installs', () async {
    final s = store();
    expect(await s.installedPath('es'), isNull);
    final progress = <int>[];
    await s.download(
      'es',
      onProgress: (received, total) {
        expect(total, _payload.length);
        progress.add(received);
      },
    );
    expect(progress.last, _payload.length);
    expect(files.unzipped, hasLength(1));
    expect(await s.installedPath('es'), '${root.path}/voice/vosk-model-small-es-0.42');
    expect(server.requests.single.path, '/release/vosk-model-small-es-0.42.zip');
    // The zip is gone once unzipped: only the model takes room.
    expect(File('${root.path}/voice/vosk-model-small-es-0.42.zip.part').existsSync(), isFalse);
  });

  test('a download cut short resumes where it stopped (Range), and only the rest comes', () async {
    final s = store();
    server.cutAfter = 100 * 1024;
    await expectLater(s.download('es'), throwsA(isA<ModelDownloadFailure>()));
    expect(await s.installedPath('es'), isNull);
    final part = File('${root.path}/voice/vosk-model-small-es-0.42.zip.part');
    expect(part.lengthSync(), 100 * 1024);

    await s.download('es');
    expect(server.requests.last.range, 'bytes=${100 * 1024}-');
    expect(await s.installedPath('es'), isNotNull);
  });

  test('a server that ignores Range starts the file over instead of appending', () async {
    final s = store();
    server.cutAfter = 50 * 1024;
    await expectLater(s.download('es'), throwsA(isA<ModelDownloadFailure>()));
    server.ignoreRange = true;
    await s.download('es');
    expect(await s.installedPath('es'), isNotNull);
  });

  test('a redirect (GitHub sends release assets elsewhere) is followed', () async {
    server.redirect = true;
    await store().download('es');
    expect(server.requests.map((r) => r.path), [
      '/release/vosk-model-small-es-0.42.zip',
      '/objects/vosk-model-small-es-0.42.zip',
    ]);
  });

  test('a resume through the redirect still asks for the rest only', () async {
    server.redirect = true;
    final s = store();
    server.cutAfter = 120 * 1024;
    await expectLater(s.download('es'), throwsA(isA<ModelDownloadFailure>()));
    await s.download('es');
    expect(server.requests.last.path, '/objects/vosk-model-small-es-0.42.zip');
    expect(server.requests.last.range, 'bytes=${120 * 1024}-');
    expect(await s.installedPath('es'), isNotNull);
  });

  test('a file whose SHA-256 is not the constant is thrown away and never used', () async {
    server.body = Uint8List.fromList([..._payload]..[10] ^= 0xff);
    final s = store();
    await expectLater(
      s.download('es'),
      throwsA(isA<ModelDownloadFailure>().having((f) => f.corrupt, 'corrupt', isTrue)),
    );
    expect(files.unzipped, isEmpty);
    expect(await s.installedPath('es'), isNull);
    expect(File('${root.path}/voice/vosk-model-small-es-0.42.zip.part').existsSync(), isFalse);
  });

  test('a cancelled download keeps what came, to resume later', () async {
    final s = store();
    final cancel = CancelToken();
    server.slow = true;
    final done = s.download(
      'es',
      cancel: cancel,
      onProgress: (received, _) {
        if (received > 0) cancel.cancel();
      },
    );
    await expectLater(
      done,
      throwsA(isA<ModelDownloadFailure>().having((f) => f.cancelled, 'cancelled', isTrue)),
    );
    expect(await s.installedPath('es'), isNull);
    final kept = File('${root.path}/voice/vosk-model-small-es-0.42.zip.part').lengthSync();
    expect(kept, inExclusiveRange(0, _payload.length));
  });

  test('a file error while writing (a full disk, say) is a ModelDownloadFailure', () async {
    // The partial file's path is taken by a folder: writing fails, and the error surfaces when
    // the file is closed.
    await Directory('${root.path}/voice/vosk-model-small-es-0.42.zip.part').create(recursive: true);
    await expectLater(
      store().download('es'),
      throwsA(isA<ModelDownloadFailure>().having((f) => f.cancelled, 'cancelled', isFalse)),
    );
    expect(await store().installedPath('es'), isNull);
  });

  test('a models folder that cannot be made is a ModelDownloadFailure too', () async {
    await File('${root.path}/voice').writeAsString('not a folder');
    await expectLater(store().download('es'), throwsA(isA<ModelDownloadFailure>()));
  });

  test('not enough free space for the zip and the model refuses before downloading', () async {
    files.free = _payload.length * 2;
    await expectLater(
      store().download('es'),
      throwsA(isA<ModelDownloadFailure>().having((f) => f.noSpace, 'noSpace', isTrue)),
    );
    expect(server.requests, isEmpty);
    files.free = _payload.length * 3;
    await store().download('es');
    expect(await store().installedPath('es'), isNotNull);
  });

  test('free space unknown, or its question failing, goes ahead: the hash still guards', () async {
    files.free = null;
    await store().download('es');
    expect(await store().installedPath('es'), isNotNull);
    await store().deleteModels();
    files.freeFails = true;
    await store().download('es');
    expect(await store().installedPath('es'), isNotNull);
  });

  test(
    'a 206 that starts somewhere else than asked is refused, and the next try starts over',
    () async {
      final s = store();
      server.cutAfter = 100 * 1024;
      await expectLater(s.download('es'), throwsA(isA<ModelDownloadFailure>()));
      server.wrongRangeStart = 50 * 1024;
      await expectLater(s.download('es'), throwsA(isA<ModelDownloadFailure>()));
      await s.download('es');
      expect(server.requests.last.range, isNull, reason: 'started over');
      expect(await s.installedPath('es'), isNotNull);
    },
  );

  test('a server sending more than the model\'s size is cut at the size', () async {
    server.body = Uint8List.fromList([..._payload, ...List<int>.filled(64 * 1024, 7)]);
    // The model is the payload: what comes after it is never written.
    final s = store(model: _model(_payload));
    await s.download('es');
    expect(await s.installedPath('es'), isNotNull);
  });

  test('deleteModels removes every model and frees the loaded one', () async {
    final s = store();
    await s.download('es');
    await s.deleteModels();
    expect(await s.installedPath('es'), isNull);
    expect(Directory('${root.path}/voice').existsSync(), isFalse);
    expect(files.released, 1);
  });

  test('English phones get the English model', () async {
    final en = VoiceModel(
      locale: 'en',
      name: 'vosk-model-small-en-us-0.15',
      bytes: _payload.length,
      unzippedBytes: _payload.length * 2,
      sha256: sha256.convert(_payload).toString(),
    );
    final s = ModelStore(
      files: files,
      http: Dio(),
      releaseUrl: server.base,
      models: {'es': _model(_payload), 'en': en},
    );
    expect(s.modelFor('en')!.name, 'vosk-model-small-en-us-0.15');
    await s.download('en');
    expect(await s.installedPath('en'), isNotNull);
    expect(await s.installedPath('es'), isNull);
  });

  test('a language with no model is never given the Spanish one', () async {
    final s = ModelStore(
      files: files,
      http: Dio(),
      releaseUrl: server.base,
      models: {'es': _model(_payload)},
    );
    // The Spanish model is on the phone: it is not the answer for anyone else.
    await s.download('es');
    expect(await s.installedPath('es'), isNotNull);
    for (final language in ['it', 'pt', 'fr']) {
      expect(s.hasModel(language), isFalse, reason: language);
      expect(s.modelFor(language), isNull, reason: language);
      expect(await s.installedPath(language), isNull, reason: language);
      await expectLater(
        s.download(language),
        throwsA(isA<ModelDownloadFailure>()),
        reason: language,
      );
    }
    expect(s.hasModel('es'), isTrue);
  });

  test('the shipped list has the four models, each with the published size and SHA-256', () {
    expect(voiceModels.keys.toSet(), {'es', 'en', 'it', 'pt'});
    final it = voiceModels['it']!;
    expect(it.name, 'vosk-model-small-it-0.22');
    expect(it.bytes, 49665141);
    expect(it.unzippedBytes, 91299150);
    expect(it.sha256, '9ec65e75861d1c6c2e457cccd932705340dcdf233f5b239f00733b4de0bf3267');
    final pt = voiceModels['pt']!;
    expect(pt.name, 'vosk-model-small-pt-0.3');
    expect(pt.bytes, 32453112);
    expect(pt.unzippedBytes, 53552717);
    expect(pt.sha256, '6e1ce909032e1afa7a88e68a3d628ecafff302bdf195befab308826c395e93b7');
    for (final entry in voiceModels.entries) {
      expect(entry.value.locale, entry.key);
    }
    expect({for (final m in voiceModels.values) m.name}, hasLength(4), reason: 'no name twice');
  });

  test('each language is given its own model, and no other', () {
    final s = ModelStore(files: files, http: Dio());
    expect(s.modelFor('es')!.name, 'vosk-model-small-es-0.42');
    expect(s.modelFor('en')!.name, 'vosk-model-small-en-us-0.15');
    expect(s.modelFor('it')!.name, 'vosk-model-small-it-0.22');
    expect(s.modelFor('pt')!.name, 'vosk-model-small-pt-0.3');
    for (final language in ['es', 'en', 'it', 'pt']) {
      expect(s.hasModel(language), isTrue, reason: language);
    }
    for (final language in ['fr', 'de', 'pt-BR', '']) {
      expect(s.modelFor(language), isNull, reason: language);
    }
  });

  test(
    'deleteModels also removes the Italian and Portuguese models and their partial files',
    () async {
      final it = _modelNamed('it', 'vosk-model-small-it-0.22', _payload);
      final pt = _modelNamed('pt', 'vosk-model-small-pt-0.3', _payload);
      final s = ModelStore(
        files: files,
        http: Dio(),
        releaseUrl: server.base,
        models: {'es': _model(_payload), 'it': it, 'pt': pt},
      );
      await s.download('it');
      await s.download('pt');
      await File('${root.path}/voice/vosk-model-small-es-0.42.zip.part').writeAsBytes([1, 2, 3]);
      expect(await s.installedPath('it'), '${root.path}/voice/vosk-model-small-it-0.22');
      expect(await s.installedPath('pt'), '${root.path}/voice/vosk-model-small-pt-0.3');
      expect(server.requests.map((r) => r.path), [
        '/release/vosk-model-small-it-0.22.zip',
        '/release/vosk-model-small-pt-0.3.zip',
      ]);
      await s.deleteModels();
      expect(await s.installedPath('it'), isNull);
      expect(await s.installedPath('pt'), isNull);
      expect(Directory('${root.path}/voice').existsSync(), isFalse);
      expect(files.released, 1);
    },
  );

  group('the precise model', () {
    final canaryBytes = _payload;
    final canary = _modelNamed(
      'es',
      'sherpa-onnx-nemo-canary-180m-flash-en-es-de-fr-int8',
      canaryBytes,
    );

    ModelStore preciseStore() => ModelStore(
      files: files,
      http: Dio(),
      releaseUrl: server.base,
      models: {'es': canary, 'en': canary},
    );

    test('the constants name the v2 release and the one canary zip for es and en', () {
      expect(
        preciseModelsReleaseUrl.toString(),
        'https://github.com/slinqer/wambito/releases/download/voice-models-v2',
      );
      expect(preciseModels.keys, unorderedEquals(['es', 'en', 'it', 'pt']));
      final model = preciseModels['es']!;
      expect(identical(model, preciseModels['en']), isTrue);
      expect(model.name, 'sherpa-onnx-nemo-canary-180m-flash-en-es-de-fr-int8');
      expect(model.bytes, 150137764);
      expect(model.unzippedBytes, 207170046);
      expect(model.sha256, '65bf6fb27f22c506b217d1847c2a61ad0d8a734eed6a6842d4e735dfed10776b');
      expect(model.minRamBytes, isNull);
    });

    test('it and pt share one parakeet zip from the same release, for 5 GiB phones', () {
      final model = preciseModels['it']!;
      expect(identical(model, preciseModels['pt']), isTrue);
      expect(model.name, 'sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8');
      expect(model.bytes, 477666406);
      expect(model.unzippedBytes, 670478772);
      expect(model.sha256, 'f7f4d4f9a04ef10d77a99eb9ad3c1a616393c031cbf0232febfac51dc3bd937d');
      expect(model.minRamBytes, 5 * 1024 * 1024 * 1024);
    });

    test('en and es share one precise download', () async {
      final s = preciseStore();
      await s.download('es');
      expect(await s.installedPath('en'), isNotNull);
      expect(await s.installedPath('en'), await s.installedPath('es'));
    });

    test('deleteModel removes only that model', () async {
      final vosk = store();
      await vosk.download('es');
      final precise = preciseStore();
      await precise.download('es');
      final preciseDir = await precise.installedPath('es');
      await precise.deleteModel('en');
      expect(await precise.installedPath('es'), isNull);
      expect(Directory(preciseDir!).existsSync(), isFalse);
      expect(File('$preciseDir.ready').existsSync(), isFalse);
      expect(await vosk.installedPath('es'), isNotNull);
      expect(files.released, 1);
    });

    test('deleteModel also removes a partial download', () async {
      final s = preciseStore();
      server.cutAfter = 1000;
      await expectLater(s.download('es'), throwsA(isA<ModelDownloadFailure>()));
      final part = File('${root.path}/voice/${canary.fileName}.part');
      expect(part.existsSync(), isTrue);
      await s.deleteModel('es');
      expect(part.existsSync(), isFalse);
    });

    test('a precise model for all four languages', () {
      final s = ModelStore(files: files, http: Dio(), models: preciseModels);
      for (final locale in ['es', 'en', 'it', 'pt']) {
        expect(s.hasModel(locale), isTrue, reason: locale);
      }
      expect(s.hasModel('fr'), isFalse);
    });

    group('preciseEligibleProvider', () {
      Future<bool> eligible(
        String locale, {
        required bool qualifies,
        _QualifyingPlatform? platform,
      }) async {
        final container = ProviderContainer(
          overrides: [
            voiceChannelProvider.overrideWithValue(platform ?? _QualifyingPlatform(qualifies)),
          ],
        );
        addTearDown(container.dispose);
        return container.read(preciseEligibleProvider(locale).future);
      }

      test('is false when the device does not qualify', () async {
        expect(await eligible('es', qualifies: false), isFalse);
      });

      test('is true for the four languages on a device that qualifies, false for others', () async {
        for (final locale in ['es', 'en', 'it', 'pt']) {
          expect(await eligible(locale, qualifies: true), isTrue, reason: locale);
        }
        expect(await eligible('fr', qualifies: true), isFalse);
      });

      test("asks the phone for the model's RAM floor: parakeet's for it and pt", () async {
        final platform = _QualifyingPlatform(true);
        await eligible('it', qualifies: true, platform: platform);
        await eligible('es', qualifies: true, platform: platform);
        expect(platform.asked, [5 * 1024 * 1024 * 1024, null]);
      });

      test('a timed-out answer is not kept: the next read asks again', () async {
        final platform = _SlowThenQualifyingPlatform();
        final container = ProviderContainer(
          overrides: [voiceChannelProvider.overrideWithValue(platform)],
        );
        addTearDown(container.dispose);
        expect(await container.read(preciseEligibleProvider('es').future), isFalse);
        await Future<void>.delayed(Duration.zero); // a later open of the sheet
        expect(await container.read(preciseEligibleProvider('es').future), isTrue);
        expect(platform.asked, 2);
      });
    });
  });

  group('on iOS', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('the model store is the precise one: Canary for es, Parakeet for it', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final store = container.read(modelStoreProvider);
      expect(identical(store, container.read(preciseModelStoreProvider)), isTrue);
      expect(store.modelFor('es'), preciseModels['es']);
      expect(store.modelFor('it'), preciseModels['it']);
      expect(store.modelFor('es')!.name, contains('canary'));
      expect(store.modelFor('it')!.name, contains('parakeet'));
    });

    test('on Android it is still Vosk\'s', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(modelStoreProvider).modelFor('es'), voiceModels['es']);
    });
  });
}

class _QualifyingPlatform implements VoicePlatform {
  _QualifyingPlatform(this.qualifies);

  final bool qualifies;
  final asked = <int?>[];

  @override
  Future<bool> deviceQualifies({int? minRamBytes}) async {
    asked.add(minRamBytes);
    return qualifies;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
}

class _SlowThenQualifyingPlatform implements VoicePlatform {
  var asked = 0;

  @override
  Future<bool> deviceQualifies({int? minRamBytes}) {
    asked++;
    // The first answer never comes (the 2 s timeout answers false); the second is immediate.
    return asked == 1 ? Completer<bool>().future : Future.value(true);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
}
