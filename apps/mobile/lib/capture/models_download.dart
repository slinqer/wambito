// The voice models: not in the APK, downloaded on first 🎤 use after an opt-in that shows the size
// (founder ruling, Task 12). Each is the official Vosk zip, re-published as an asset of this
// repo's GitHub release `voice-models-v1`, checked against the SHA-256 below before it is ever
// unzipped or loaded. A download cut short resumes where it stopped.
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'engine/voice_channel.dart';

/// Where the models are downloaded from: this repo's release, one zip per model.
final voiceModelsReleaseUrl = Uri.parse(
  'https://github.com/slinqer/wambito/releases/download/voice-models-v1',
);

/// One language's Vosk model (Apache-2.0, https://alphacephei.com/vosk/models).
class VoiceModel {
  const VoiceModel({
    required this.locale,
    required this.name,
    required this.bytes,
    required this.unzippedBytes,
    required this.sha256,
    this.minRamBytes,
  });

  /// `es`, `en`, `it` or `pt`.
  final String locale;

  /// The model's name, which is also its zip's name and the one folder inside it.
  final String name;

  /// The zip's size, shown before anything is downloaded.
  final int bytes;

  /// The model's size once unzipped (the sum of the zip's entries): checked as free space first.
  final int unzippedBytes;

  /// The zip's SHA-256, lowercase hex: of the official file, published unchanged.
  final String sha256;

  /// A precise model's own RAM floor, asked of the phone (`deviceQualifies`); null is the
  /// platform's default (3 GB).
  final int? minRamBytes;

  String get fileName => '$name.zip';
}

/// The models, by language: the voice spike's choice (Vosk small).
const voiceModels = {
  'es': VoiceModel(
    locale: 'es',
    name: 'vosk-model-small-es-0.42',
    bytes: 39817833,
    unzippedBytes: 60286598,
    sha256: '09b239888f633ef2f0b4e09736e3d9936acfd810bc65d53fad45261762c6511f',
  ),
  'en': VoiceModel(
    locale: 'en',
    name: 'vosk-model-small-en-us-0.15',
    bytes: 41205931,
    unzippedBytes: 70898967,
    sha256: '30f26242c4eb449f948e42cb302dd7a686cb29a3423a8367f99ff41780942498',
  ),
  'it': VoiceModel(
    locale: 'it',
    name: 'vosk-model-small-it-0.22',
    bytes: 49665141,
    unzippedBytes: 91299150,
    sha256: '9ec65e75861d1c6c2e457cccd932705340dcdf233f5b239f00733b4de0bf3267',
  ),
  // Trained mostly on Brazilian speech: European Portuguese is labelled beta until the spike
  // (docs/superpowers/reports/2026-10-26-it-pt-voice-spike.md) passes.
  'pt': VoiceModel(
    locale: 'pt',
    name: 'vosk-model-small-pt-0.3',
    bytes: 32453112,
    unzippedBytes: 53552717,
    sha256: '6e1ce909032e1afa7a88e68a3d628ecafff302bdf195befab308826c395e93b7',
  ),
};

/// Where the precise models are downloaded from: the second release, with the Canary and Parakeet
/// zips.
final preciseModelsReleaseUrl = Uri.parse(
  'https://github.com/slinqer/wambito/releases/download/voice-models-v2',
);

/// NVIDIA Canary 180M Flash int8 (CC-BY-4.0), the precise model that re-transcribes a recording on
/// release. One model serves Spanish and English, so one download installs both.
const _canary = VoiceModel(
  locale: 'es',
  name: 'sherpa-onnx-nemo-canary-180m-flash-en-es-de-fr-int8',
  bytes: 150137764,
  unzippedBytes: 207170046,
  sha256: '65bf6fb27f22c506b217d1847c2a61ad0d8a734eed6a6842d4e735dfed10776b',
);

/// NVIDIA Parakeet TDT 0.6B v3 int8 (CC-BY-4.0), the precise model for Italian and Portuguese: one
/// zip for both, about three times Canary's size, so only on phones sold with 6 GB of RAM or more
/// (about 5.5 GiB reported; the floor is 5 GiB).
const _parakeet = VoiceModel(
  locale: 'it',
  name: 'sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8',
  bytes: 477666406,
  unzippedBytes: 670478772,
  sha256: 'f7f4d4f9a04ef10d77a99eb9ad3c1a616393c031cbf0232febfac51dc3bd937d',
  minRamBytes: 5 * 1024 * 1024 * 1024,
);

/// The precise model by language: Canary for Spanish and English, Parakeet for Italian and
/// Portuguese.
const preciseModels = {'es': _canary, 'en': _canary, 'it': _parakeet, 'pt': _parakeet};

/// A download that did not end with a model ready to use.
class ModelDownloadFailure implements Exception {
  const ModelDownloadFailure({this.corrupt = false, this.cancelled = false, this.noSpace = false});

  /// The file was complete but not the published one (its SHA-256 differs); it was deleted.
  final bool corrupt;

  /// The person stopped it. What came is kept, to resume.
  final bool cancelled;

  /// The phone has too little free space for the zip and the unzipped model; nothing was fetched.
  final bool noSpace;

  @override
  String toString() =>
      'ModelDownloadFailure(corrupt: $corrupt, cancelled: $cancelled, noSpace: $noSpace)';
}

/// Where models live on the phone, and what Dart cannot do on its own there.
abstract interface class ModelFiles {
  /// An app-private directory (no backup) for the models.
  Future<String> modelsDirectory();

  /// Unzips [zip] into the directory [into].
  Future<void> unzip(String zip, String into);

  /// Frees a model the recognizer has loaded (before its files are deleted).
  Future<void> releaseModels();

  /// The bytes free where the models go; null when the phone cannot tell.
  Future<int?> freeBytes();
}

/// The downloaded models: which are ready, getting one, deleting them all.
class ModelStore {
  ModelStore({
    required this._files,
    required this._http,
    Uri? releaseUrl,
    this._models = voiceModels,
  }) : _releaseUrl = releaseUrl ?? voiceModelsReleaseUrl;

  final ModelFiles _files;

  /// A plain client: never the API's, which carries the session token.
  final Dio _http;
  final Uri _releaseUrl;
  final Map<String, VoiceModel> _models;
  final _running = <String, Future<void>>{};

  /// The model for [locale]; null when there is none (every language the app speaks has one). A
  /// language is never given another language's model: Spanish audio would be read with English
  /// words, and the other way round.
  VoiceModel? modelFor(String locale) => _models[locale];

  /// Whether [locale] has a voice model to download at all.
  bool hasModel(String locale) => _models.containsKey(locale);

  Future<String> _voiceDir() async => '${await _files.modelsDirectory()}/voice';

  /// The model's folder, when it is downloaded, verified and unzipped; otherwise null.
  Future<String?> installedPath(String locale) async {
    final model = modelFor(locale);
    if (model == null) return null;
    final dir = await _voiceDir();
    final ready = File('$dir/${model.name}.ready');
    if (!ready.existsSync() || (await ready.readAsString()).trim() != model.sha256) return null;
    final path = '$dir/${model.name}';
    return Directory(path).existsSync() ? path : null;
  }

  /// Downloads [locale]'s model, resuming a partial file, verifies its SHA-256, unzips it and marks
  /// it ready. [onProgress] gets the bytes so far (resumed ones included) and the total. Throws a
  /// [ModelDownloadFailure]. A second call while one runs joins it.
  Future<void> download(
    String locale, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancel,
  }) {
    final model = modelFor(locale);
    // No model for this language: the same failure as a download that did not work.
    if (model == null) return Future.error(const ModelDownloadFailure());
    return _running[model.name] ??= _download(model, onProgress, cancel).whenComplete(() {
      // A block, not `=>`: remove returns this very future, which whenComplete would wait for.
      _running.remove(model.name);
    });
  }

  Future<void> _download(
    VoiceModel model,
    void Function(int received, int total)? onProgress,
    CancelToken? cancel,
  ) async {
    try {
      await _fetchAndInstall(model, onProgress, cancel);
    } on ModelDownloadFailure {
      rethrow;
    } on DioException catch (error) {
      throw ModelDownloadFailure(cancelled: CancelToken.isCancel(error));
    } on Object {
      // Anything else (a full disk, a file that cannot be written or read) ends the same way: the
      // offer comes back with Reintentar. What came is kept; it is never used unverified.
      throw ModelDownloadFailure(cancelled: cancel?.isCancelled ?? false);
    }
  }

  Future<void> _fetchAndInstall(
    VoiceModel model,
    void Function(int received, int total)? onProgress,
    CancelToken? cancel,
  ) async {
    final dir = await _voiceDir();
    await Directory(dir).create(recursive: true);
    final part = File('$dir/${model.fileName}.part');
    var from = part.existsSync() ? part.lengthSync() : 0;
    if (from > model.bytes) {
      await part.delete();
      from = 0;
    }
    // Room for the rest of the zip and the unzipped model, which exist together for a moment.
    // When the phone cannot tell, it goes ahead: a full disk then fails the write, and the hash
    // still guards what is used.
    final free = await _freeBytes();
    if (free != null && free < model.bytes - from + model.unzippedBytes) {
      throw const ModelDownloadFailure(noSpace: true);
    }

    if (from < model.bytes) {
      final response = await _http.getUri<ResponseBody>(
        _releaseUrl.replace(path: '${_releaseUrl.path}/${model.fileName}'),
        cancelToken: cancel,
        options: Options(
          responseType: ResponseType.stream,
          headers: {if (from > 0) HttpHeaders.rangeHeader: 'bytes=$from-'},
          validateStatus: (status) => status == 200 || status == 206 || status == 416,
        ),
      );
      // 416: nothing left to send, the file is whole; check it below.
      if (response.statusCode != 416) {
        // 200: the whole file again (the server ignored Range), so it starts over.
        if (response.statusCode == 200) from = 0;
        if (response.statusCode == 206 && _rangeStart(response.headers) != from) {
          // Not the bytes that come next: appending them would spoil the file. Start over.
          await part.delete();
          throw const ModelDownloadFailure();
        }
        final sink = part.openWrite(mode: from == 0 ? FileMode.write : FileMode.append);
        var received = from;
        try {
          onProgress?.call(received, model.bytes);
          await for (final chunk in response.data!.stream) {
            // Never more than the model's size, whatever the server sends.
            final room = model.bytes - received;
            sink.add(chunk.length <= room ? chunk : chunk.sublist(0, room));
            received += chunk.length <= room ? chunk.length : room;
            onProgress?.call(received, model.bytes);
            if (received >= model.bytes) break;
          }
        } finally {
          // Write errors (a full disk) surface here; the catch in _download maps them.
          await sink.close();
        }
      }
    }

    final digest = await sha256.bind(part.openRead()).first;
    if (digest.toString() != model.sha256) {
      await part.delete();
      throw const ModelDownloadFailure(corrupt: true);
    }
    final target = Directory('$dir/${model.name}');
    if (target.existsSync()) await target.delete(recursive: true);
    // Unzipped under a temporary name first, so a half-unzipped model is never taken for one.
    final staging = Directory('$dir/.unzip-${model.name}');
    if (staging.existsSync()) await staging.delete(recursive: true);
    await staging.create(recursive: true);
    try {
      await _files.unzip(part.path, staging.path);
      await Directory('${staging.path}/${model.name}').rename(target.path);
    } finally {
      if (staging.existsSync()) await staging.delete(recursive: true);
    }
    await File('$dir/${model.name}.ready').writeAsString(model.sha256, flush: true);
    await part.delete();
  }

  Future<int?> _freeBytes() async {
    try {
      return await _files.freeBytes();
    } on Object {
      return null;
    }
  }

  /// The first byte of a 206 answer (`Content-Range: bytes <start>-<end>/<size>`), or null.
  static int? _rangeStart(Headers headers) {
    final value = headers.value(HttpHeaders.contentRangeHeader);
    final match = value == null ? null : RegExp(r'^bytes (\d+)-').firstMatch(value.trim());
    return match == null ? null : int.parse(match.group(1)!);
  }

  /// Deletes [locale]'s model (folder, `.ready` and any `.part`), freeing the loaded ones first.
  /// The other store's files in the same directory stay.
  Future<void> deleteModel(String locale) async {
    final model = modelFor(locale);
    if (model == null) return;
    await _files.releaseModels();
    final dir = await _voiceDir();
    final folder = Directory('$dir/${model.name}');
    if (folder.existsSync()) await folder.delete(recursive: true);
    for (final path in ['$dir/${model.name}.ready', '$dir/${model.fileName}.part']) {
      final file = File(path);
      if (file.existsSync()) await file.delete();
    }
  }

  /// Deletes every downloaded model (and partial download), freeing a loaded one first. Settings
  /// calls it (Task 14); the next 🎤 asks to download again.
  Future<void> deleteModels() async {
    await _files.releaseModels();
    final dir = Directory(await _voiceDir());
    if (dir.existsSync()) await dir.delete(recursive: true);
  }
}

/// The phone's model store: Vosk's on Android; on iOS, which has no Vosk, the precise store (the
/// one `PreciseEngine` reads its folder from), so the same download offer, progress and deletion
/// serve it.
final modelStoreProvider = Provider<ModelStore>((ref) {
  if (defaultTargetPlatform == TargetPlatform.iOS) return ref.watch(preciseModelStoreProvider);
  return ModelStore(
    files: ref.watch(voiceChannelProvider),
    http: Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        // Between two chunks of the body, not for the whole file.
        receiveTimeout: const Duration(seconds: 30),
      ),
    ),
  );
});

/// The precise model's store: the same download and verification, from the v2 release.
final preciseModelStoreProvider = Provider<ModelStore>(
  (ref) => ModelStore(
    files: ref.watch(voiceChannelProvider),
    http: Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
      ),
    ),
    releaseUrl: preciseModelsReleaseUrl,
    models: preciseModels,
  ),
);

/// Whether the precise model is offered for [locale] (a `voiceLocale`): the phone qualifies (arm64,
/// enough RAM for that language's model, sherpa-onnx linked) and the language has one.
final preciseEligibleProvider = FutureProvider.family<bool, String>((ref, locale) async {
  final model = preciseModels[locale];
  if (model == null) return false;
  // A channel that never answers must not hold the capture sheet: no answer means not eligible.
  return ref
      .watch(voiceChannelProvider)
      .deviceQualifies(minRamBytes: model.minRamBytes)
      .timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          // The family is not auto-dispose, so a kept timeout would answer false for the whole
          // process: forget it (once it has answered), and the next read asks again.
          Timer.run(() {
            if (ref.mounted) ref.invalidateSelf();
          });
          return false;
        },
      );
});

/// Deletes the downloaded voice models (Settings, Task 14, adds the button).
Future<void> deleteModels(WidgetRef ref) => ref.read(modelStoreProvider).deleteModels();
