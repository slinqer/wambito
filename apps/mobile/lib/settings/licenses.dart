import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import 'android_libraries.dart';

/// What About's licence page lists besides the Dart packages. Flutter collects the LICENSE file of
/// every Dart package, and its own engine and framework, by itself. Everything else the app ships
/// is added here:
///  * the Android (Kotlin and Java) libraries, from assets/licenses/android-libraries.json, which
///    scripts/gen-android-licenses.dart writes from the POMs of the release classpath (and CI
///    checks is not stale), each under the licence its POM declares;
///  * the speech engine, JNA and the voice models, and what their native libraries carry inside:
///    OpenBLAS and CLAPACK (with libf2c) in libvosk.so, libffi in libjnidispatch.so;
///  * the precise voice model's runtime, sherpa-onnx (an AAR that scripts/fetch-sherpa-onnx.sh
///    installs with a POM that declares Apache-2.0, so it is in the Android list too and is
///    handled here like Vosk), the Canary and Parakeet models (CC BY 4.0, NVIDIA, downloaded
///    like the Vosk ones), and what the AAR's two native libraries carry: onnxruntime 1.28.2 and what is
///    linked into it (libonnxruntime.so), and what sherpa-onnx's CMakeLists.txt and cmake/*.cmake
///    at v2.0.1 link into libsherpa-onnx-jni.so;
///  * the app's own sounds, and the app.
/// The notices are in the ARB files; the licence texts are as their authors published them.

const _apache = 'assets/licenses/apache-2.0.txt';
const _agpl = 'assets/licenses/agpl-3.0.txt';
const _bsdGlance = 'assets/licenses/glance-protobuf-bsd-3-clause.txt';
const _libraries = 'assets/licenses/android-libraries.json';

// Inside the native libraries of vosk-android 0.3.75 (vosk-api's android/lib/build-vosk.sh) and of
// JNA 5.18.1 (its native/libffi), as the projects publish them: OpenBLAS v0.3.20's LICENSE,
// netlib's CLAPACK 3.2.1 COPYING and its F2CLIBS/libf2c/Notice, libffi v3.4.4's LICENSE. A test
// pins those two versions: upgrading either means checking these again.
const _openBlas = 'assets/licenses/openblas-bsd-3-clause.txt';
const _clapack = 'assets/licenses/clapack-bsd.txt';
const _libf2c = 'assets/licenses/libf2c-notice.txt';
const _libffi = 'assets/licenses/libffi-mit.txt';

// The precise voice model and the AAR of sherpa-onnx 2.0.1, as their projects publish the texts:
// Creative Commons' legal code of CC BY 4.0, onnxruntime v1.28.2's LICENSE (the version inside
// libonnxruntime.so, from its strings and sherpa-onnx's cmake/onnxruntime-android-*.cmake), and
// the texts of what is linked in: nlohmann/json v3.12.0, utf8proc v2.12.0, hclust-cpp (fastcluster),
// darts-clone 0.32 (the header simple-sentencepiece v0.7 includes), kissfft (which kaldi-native-fbank
// v1.22.4 links), Eigen (in both libraries), and inside libonnxruntime.so Protocol Buffers, RE2,
// cpuinfo, SafeInt, GSL, date and Boost.Mp11 (the deps of onnxruntime v1.28.2's cmake/deps.txt its
// Android build compiles in). The Apache-2.0 ones (kaldi-native-fbank 1.22.4, kaldi-decoder 0.3.0,
// kaldifst 1.8.0, OpenFst 1.8.5, simple-sentencepiece 0.7; Abseil, ONNX, FlatBuffers and KleidiAI)
// use the Apache text. A test pins sherpa-onnx 2.0.1: upgrading it means checking the AAR's
// libraries and these entries again (docs/superpowers/reports/2026-11-06-sherpa-onnx-from-source-spike.md
// lists how they were found).
const _ccBy = 'assets/licenses/cc-by-4.0.txt';
const _onnxruntime = 'assets/licenses/onnxruntime-mit.txt';
const _nlohmann = 'assets/licenses/nlohmann-json-mit.txt';
const _utf8proc = 'assets/licenses/utf8proc-license.txt';
const _fastcluster = 'assets/licenses/fastcluster-bsd-2-clause.txt';
const _darts = 'assets/licenses/darts-clone-bsd-2-clause.txt';
const _protobuf = 'assets/licenses/protobuf-bsd-3-clause.txt';
const _re2 = 'assets/licenses/re2-bsd-3-clause.txt';
const _cpuinfo = 'assets/licenses/cpuinfo-bsd-2-clause.txt';
const _safeint = 'assets/licenses/safeint-mit.txt';
const _gsl = 'assets/licenses/gsl-mit.txt';
const _date = 'assets/licenses/date-mit.txt';
const _boost = 'assets/licenses/boost-1.0.txt';
const _eigen = 'assets/licenses/eigen-mpl-2.0.txt';
const _kissfft = 'assets/licenses/kissfft-bsd-3-clause.txt';

// The fonts and the licence file each ships (assets/fonts, pubspec.yaml; scripts/check-licenses.sh
// checks every font has one). Both are SIL OFL 1.1, from Google Fonts' repository.
const _fredokaOfl = 'assets/fonts/Fredoka-OFL.txt';
const _nunitoOfl = 'assets/fonts/Nunito-OFL.txt';

const _vosk = 'com.alphacephei:vosk-android';
const _jna = 'net.java.dev.jna:jna';
const _sherpa = 'com.k2fsa.sherpa.onnx:sherpa-onnx';

/// The text of a library whose licence is not the plain Apache one: the BSD-3-Clause that
/// `androidx.glance:glance-appwidget-external-protobuf` publishes inside its jar.
const _ownText = {'androidx.glance:glance-appwidget-external-protobuf': _bsdGlance};

String _textAssetFor(AndroidLibrary library) {
  final own = _ownText[library.id];
  if (own != null) return own;
  if (library.license == 'Apache-2.0') return _apache;
  // JNA is "Apache-2.0 OR LGPL-2.1-or-later" and is used under Apache; it has its own entry.
  throw StateError('No licence text for ${library.id}: ${library.license}');
}

/// The licences Flutter does not collect by itself, as [LicenseEntry]s (texts read from [bundle],
/// notices in [l10n]'s language).
Stream<LicenseEntry> extraLicenseEntries(AssetBundle bundle, AppLocalizations l10n) async* {
  Future<String> load(String asset) => bundle.loadString(asset);

  final apache = await load(_apache);
  final libraries = parseLibraries(await load(_libraries));
  AndroidLibrary? find(String id) => libraries.where((l) => l.id == id).firstOrNull;
  String name(AndroidLibrary library) => '${library.id} ${library.version}';

  for (final (model, language) in [
    ('vosk-model-small-es-0.42', l10n.settingsLanguageEs),
    ('vosk-model-small-en-us-0.15', l10n.settingsLanguageEn),
    ('vosk-model-small-it-0.22', l10n.settingsLanguageIt),
    ('vosk-model-small-pt-0.3', l10n.settingsLanguagePt),
  ]) {
    yield LicenseEntryWithLineBreaks([model], '${l10n.licenseNoticeModel(language)}\n\n$apache');
  }

  final vosk = find(_vosk);
  if (vosk != null) {
    yield LicenseEntryWithLineBreaks([
      'vosk-android ${vosk.version}',
    ], '${l10n.licenseNoticeVosk}\n\n$apache');
    yield LicenseEntryWithLineBreaks([
      'OpenBLAS 0.3.20',
    ], '${l10n.licenseNoticeOpenBlas}\n\n${await load(_openBlas)}');
    yield LicenseEntryWithLineBreaks([
      'CLAPACK 3.2.1',
    ], '${l10n.licenseNoticeClapack}\n\n${await load(_clapack)}\n\n${await load(_libf2c)}');
  }
  final jna = find(_jna);
  if (jna != null) {
    yield LicenseEntryWithLineBreaks(['JNA ${jna.version}'], '${l10n.licenseNoticeJna}\n\n$apache');
    yield LicenseEntryWithLineBreaks([
      'libffi 3.4.4',
    ], '${l10n.licenseNoticeLibffi}\n\n${await load(_libffi)}');
  }
  // The precise voice model's runtime is in the build (not in the F-Droid one): sherpa-onnx, the
  // Canary and Parakeet models it runs, and the libraries inside the AAR's two native libraries.
  final sherpa = find(_sherpa);
  if (sherpa != null) {
    yield LicenseEntryWithLineBreaks([
      'Canary-180M flash, NVIDIA',
    ], '${l10n.licenseNoticeCanary}\n\n${await load(_ccBy)}');
    yield LicenseEntryWithLineBreaks([
      'Parakeet TDT 0.6B v3, NVIDIA',
    ], '${l10n.licenseNoticeParakeet}\n\n${await load(_ccBy)}');
    yield LicenseEntryWithLineBreaks([
      'sherpa-onnx ${sherpa.version}',
    ], '${l10n.licenseNoticeSherpa}\n\n$apache');
    yield LicenseEntryWithLineBreaks([
      'onnxruntime 1.28.2',
    ], '${l10n.licenseNoticeOnnxruntime}\n\n${await load(_onnxruntime)}');
    yield LicenseEntryWithLineBreaks([
      'Abseil',
      'ONNX',
      'FlatBuffers',
      'KleidiAI',
    ], '${l10n.licenseNoticeOrtApache}\n\n$apache');
    for (final (name, notice, asset) in [
      ('Protocol Buffers', l10n.licenseNoticeProtobuf, _protobuf),
      ('RE2', l10n.licenseNoticeRe2, _re2),
      ('cpuinfo', l10n.licenseNoticeCpuinfo, _cpuinfo),
      ('SafeInt', l10n.licenseNoticeSafeint, _safeint),
      ('GSL', l10n.licenseNoticeGsl, _gsl),
      ('date', l10n.licenseNoticeDate, _date),
      ('Boost.Mp11', l10n.licenseNoticeMp11, _boost),
      ('Eigen', l10n.licenseNoticeEigen, _eigen),
    ]) {
      yield LicenseEntryWithLineBreaks([name], '$notice\n\n${await load(asset)}');
    }
    yield LicenseEntryWithLineBreaks([
      'kaldi-native-fbank 1.22.4',
      'kaldi-decoder 0.3.0',
      'kaldifst 1.8.0',
      'OpenFst 1.8.5',
      'simple-sentencepiece 0.7',
    ], '${l10n.licenseNoticeSherpaNative}\n\n$apache');
    for (final (name, notice, asset) in [
      ('nlohmann/json 3.12.0', l10n.licenseNoticeNlohmann, _nlohmann),
      ('utf8proc 2.12.0', l10n.licenseNoticeUtf8proc, _utf8proc),
      ('fastcluster (hclust-cpp)', l10n.licenseNoticeFastcluster, _fastcluster),
      ('darts-clone 0.32', l10n.licenseNoticeDarts, _darts),
      ('kissfft', l10n.licenseNoticeKissfft, _kissfft),
    ]) {
      yield LicenseEntryWithLineBreaks([name], '$notice\n\n${await load(asset)}');
    }
  }
  // The rest, one entry per licence text: every library under what its own POM declares.
  const handled = {_vosk, _jna, _sherpa};
  final groups = <String, List<AndroidLibrary>>{};
  for (final library in libraries.where((l) => !handled.contains(l.id))) {
    (groups[_textAssetFor(library)] ??= []).add(library);
  }
  for (final MapEntry(key: asset, value: group) in groups.entries) {
    final notice = asset == _apache
        ? l10n.licenseNoticeLibraries('Apache-2.0')
        : l10n.licenseNoticeBsd;
    yield LicenseEntryWithLineBreaks([
      for (final l in group) name(l),
    ], '$notice\n\n${await load(asset)}');
  }

  for (final (name, source, role, asset) in [
    (
      'Fredoka',
      'https://github.com/hafontia/Fredoka-One',
      l10n.licenseNoticeFontRoleDisplay,
      _fredokaOfl,
    ),
    ('Nunito', 'https://github.com/googlefonts/nunito', l10n.licenseNoticeFontRoleText, _nunitoOfl),
  ]) {
    yield LicenseEntryWithLineBreaks([
      name,
    ], '${l10n.licenseNoticeFont(name, source, role)}\n\n${await load(asset)}');
  }

  final agpl = await load(_agpl);
  yield LicenseEntryWithLineBreaks([
    'Wambito feedback sounds',
  ], '${l10n.licenseNoticeSounds}\n\n$agpl');
  yield LicenseEntryWithLineBreaks(['Wambito'], '${l10n.licenseNoticeApp}\n\n$agpl');
}

var _registered = false;
var _language = const Locale('es');

/// The language the notices are written in when the licence page opens. About sets it from the
/// app's own language just before showing the page.
void setLicenseLanguage(Locale locale) =>
    _language = AppLocalizations.supportedLocales.contains(Locale(locale.languageCode))
    ? Locale(locale.languageCode)
    : const Locale('es');

/// Adds [extraLicenseEntries] to Flutter's registry, once, so About's licence page lists them with
/// the packages'. Called at the start of the app.
void registerExtraLicenses() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(
    () => extraLicenseEntries(rootBundle, lookupAppLocalizations(_language)),
  );
}
