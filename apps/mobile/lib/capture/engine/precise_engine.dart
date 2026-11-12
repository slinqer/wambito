import 'dart:async';

import 'package:flutter/services.dart';

import '../models_download.dart';
import 'speech_engine.dart';
import 'voice_channel.dart';
import 'vosk_engine.dart' show longestListen, nothingHeardLimit, refineLimit;

/// The iOS engine: the precise model (canary) alone, no Vosk. While the person speaks the native
/// side sends live partials (its last word hidden while recording); a pause after the last changed
/// partial ends the recording, and the precise model rewrites the whole sentence, whose text is the
/// final one. If the precise pass fails, is blank, or takes over [refineLimit], the last partial
/// stands. See docs/superpowers/specs/2026-11-12-ios-voice-design.md, section 2.
class PreciseEngine implements SpeechEngine {
  PreciseEngine({required this._channel, required this._models});

  /// How long a pause after the last changed partial ends listening.
  static const endOfSpeechPause = Duration(milliseconds: 1500);

  final VoicePlatform _channel;
  final ModelStore _models;
  _Session? _session;
  final _levels = StreamController<double>.broadcast();
  final _refining = StreamController<bool>.broadcast();

  @override
  Future<bool> available() => _channel.deviceQualifies();

  @override
  Stream<double> get levels => _levels.stream;

  @override
  Stream<bool> get refining => _refining.stream;

  @override
  Future<bool> isWarm({required String locale}) async {
    try {
      final path = await _models.installedPath(locale);
      if (path == null) return false;
      return await _channel.isWarmPrecise(precisePath: path, language: locale);
    } on Object {
      return false;
    }
  }

  @override
  Future<void> warmUp({required String locale}) async {
    try {
      final path = await _models.installedPath(locale);
      if (path == null) return;
      await _channel.warmUpPrecise(precisePath: path, language: locale);
    } on Object {
      // Not loaded in advance: the first listen loads it.
    }
  }

  @override
  Stream<String> listen({required String locale}) {
    final session = _Session(_channel, locale, _levels, _refining);
    _session = session;
    session.out = StreamController<String>(
      onListen: () => unawaited(session.begin(_models)),
      onCancel: session.cancel,
    );
    return session.out.stream;
  }

  @override
  Future<void> stop() async => _session?.stop();
}

class _Session {
  _Session(this._channel, this._locale, this._levels, this._refiningStates);

  final VoicePlatform _channel;
  final String _locale;
  final StreamController<double> _levels;
  final StreamController<bool> _refiningStates;
  late final StreamController<String> out;
  StreamSubscription<VoiceEvent>? _events;
  var _partial = '';
  var _stopping = false;

  /// The precise model's text, once it came and was not blank.
  String? _refined;
  var _refining = false;

  /// Bounds the refine from its `refining` event. Not among [_cancelTimers]: [stop] clears those,
  /// and stopping must not give the precise model unlimited time.
  Timer? _refineTimer;
  var _cancelled = false;
  Timer? _pause;
  Timer? _nothing;
  Timer? _longest;

  Future<void> begin(ModelStore models) async {
    try {
      final path = await models.installedPath(_locale);
      if (path == null) throw const SpeechFailure(SpeechFailureKind.noModel);
      final granted = await _channel.requestPermission();
      if (!granted) throw const SpeechFailure(SpeechFailureKind.permissionDenied);
      if (out.isClosed || _cancelled) return;
      _longest = Timer(longestListen, () => unawaited(stop()));
      _events = _channel
          .startPrecise(precisePath: path, language: _locale)
          .listen(_onEvent, onError: _fail, onDone: _finish);
    } on SpeechFailure catch (failure) {
      _fail(failure);
    } on PlatformException catch (error) {
      _fail(SpeechFailure(SpeechFailureKind.failed, error.code));
    }
  }

  void _onEvent(VoiceEvent event) {
    if (out.isClosed) return;
    switch (event) {
      case VoiceReady():
        // An empty first event: listening has really started (SpeechEngine.listen).
        _nothing ??= Timer(nothingHeardLimit, () => unawaited(stop()));
        out.add('');
      case VoiceLevel(:final value):
        if (_levels.hasListener) _levels.add(value);
      case VoicePartial(:final text):
        // The native side sends only changed partials; an empty or repeated one never restarts
        // the pause.
        if (text.trim().isEmpty || text == _partial) break;
        _partial = text;
        _nothing?.cancel();
        _pause?.cancel();
        _pause = Timer(PreciseEngine.endOfSpeechPause, () => unawaited(stop()));
        out.add(text);
      case VoiceRefining():
        _refining = true;
        if (_refiningStates.hasListener) _refiningStates.add(true);
        _refineTimer ??= Timer(refineLimit, _finish);
      case VoiceRefined(:final text):
        // Blank is as good as nothing: the last partial stands (done follows).
        if (text.trim().isNotEmpty) _refined = text;
      case VoiceRefineFailed():
        break;
      case VoiceDone():
        _finish();
      case VoiceError(:final code):
        _fail(
          SpeechFailure(switch (code) {
            'permission' => SpeechFailureKind.permissionDenied,
            'no_model' => SpeechFailureKind.noModel,
            _ => SpeechFailureKind.failed,
          }, code),
        );
      case VoiceResult():
        break; // Never sent on iOS.
    }
  }

  /// Lets go of the platform stream once, so the engine's own [cancel] (the closing output's
  /// onCancel) does not cancel it a second time.
  Future<void> _dropEvents() async {
    final events = _events;
    _events = null;
    await events?.cancel();
  }

  void _endRefine() {
    _refineTimer?.cancel();
    if (!_refining) return;
    _refining = false;
    if (_refiningStates.hasListener) _refiningStates.add(false);
  }

  void _fail(Object error) {
    _cancelTimers();
    _endRefine();
    if (out.isClosed) return;
    out.addError(
      error is SpeechFailure ? error : SpeechFailure(SpeechFailureKind.failed, '$error'),
    );
    unawaited(out.close());
    unawaited(_dropEvents());
  }

  void _finish() {
    _cancelTimers();
    if (out.isClosed) {
      _endRefine();
      return;
    }
    out.add(_refined ?? _partial);
    unawaited(out.close());
    unawaited(_dropEvents());
    _endRefine();
  }

  Future<void> stop() async {
    _cancelTimers();
    if (_stopping || out.isClosed || _events == null) return;
    _stopping = true;
    await _channel.stop();
  }

  Future<void> cancel() async {
    _cancelled = true;
    _cancelTimers();
    _endRefine();
    // Cancelling the platform stream stops the recording.
    await _events?.cancel();
  }

  void _cancelTimers() {
    _pause?.cancel();
    _nothing?.cancel();
    _longest?.cancel();
  }
}
