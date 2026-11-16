/// The pure parts of scripts/gen-android-licenses.dart: reading the release classpath that Gradle
/// prints, a POM's licences, and the file About reads (assets/licenses/android-libraries.json).
library;

export 'package:wambito/settings/android_libraries.dart';

/// A resolved artifact before its licence is known.
class ResolvedLibrary {
  const ResolvedLibrary(this.id, this.version);

  final String id;
  final String version;

  /// The upstream release: a library scripts/build-native-deps.sh built from source is published
  /// as `<release>-src` (vosk-android 0.3.75-src, jna 5.18.1-src) and is that release's code.
  String get release => version.endsWith(_fromSource)
      ? version.substring(0, version.length - _fromSource.length)
      : version;
}

const _fromSource = '-src';

/// Where scripts/build-native-deps.sh writes the POM of a library built from source: the local
/// repository android/third_party/m2, relative to apps/mobile (Gradle never caches its files).
String localRepositoryPom(String group, String artifact, String version) =>
    'android/third_party/m2/${group.replaceAll('.', '/')}/$artifact/$version/$artifact-$version.pom';

/// Flutter's engine and embedding (`io.flutter`): their licences are Flutter's own, already in the
/// licence page that Flutter builds.
const _leftToFlutter = 'io.flutter:';

/// The artifacts of `./gradlew :app:dependencies --configuration releaseRuntimeClasspath`, once
/// each, at the version Gradle resolved ("a -> b" means b), sorted by id. Constraints `(c)` only
/// pin versions and ship nothing.
List<ResolvedLibrary> resolvedLibraries(String gradleOutput) {
  final versions = <String, String>{};
  final line = RegExp(
    r'^[ |+\\-]*([\w.\-]+):([\w.\-]+):([\w.\-]+?)(?: -> ([\w.\-]+))?(?: \((?:\*|n)\))?\s*$',
  );
  for (final raw in gradleOutput.split('\n')) {
    if (raw.contains('(c)')) continue;
    final match = line.firstMatch(raw);
    if (match == null) continue;
    final id = '${match.group(1)}:${match.group(2)}';
    if (id.startsWith(_leftToFlutter)) continue;
    versions[id] = match.group(4) ?? match.group(3)!;
  }
  final ids = versions.keys.toList()..sort();
  return [for (final id in ids) ResolvedLibrary(id, versions[id]!)];
}

/// The `<name>`s inside a POM's own `<licenses>` (not its parent's), or none.
List<String> pomLicenses(String pom) {
  final own = pom.replaceAll(RegExp(r'<parent>.*?</parent>', dotAll: true), '');
  final block = RegExp(r'<licenses>(.*?)</licenses>', dotAll: true).firstMatch(own);
  if (block == null) return const [];
  return [
    for (final license in RegExp(r'<license>(.*?)</license>', dotAll: true).allMatches(block[1]!))
      RegExp(r'<name>(.*?)</name>', dotAll: true).firstMatch(license[1]!)?[1]?.trim() ?? '',
  ].where((name) => name.isNotEmpty).toList();
}

/// A POM's parent as (group, artifact, version), or null.
(String, String, String)? pomParent(String pom) {
  final parent = RegExp(r'<parent>(.*?)</parent>', dotAll: true).firstMatch(pom)?[1];
  if (parent == null) return null;
  String? tag(String name) => RegExp('<$name>(.*?)</$name>').firstMatch(parent)?[1]?.trim();
  final group = tag('groupId');
  final artifact = tag('artifactId');
  final version = tag('version');
  if (group == null || artifact == null || version == null) return null;
  return (group, artifact, version);
}

/// A licence the generator has no decision for. Add it to [normalizeLicenses] on purpose.
class UnknownLicense implements Exception {
  UnknownLicense(this.names);

  final List<String> names;

  @override
  String toString() => 'UnknownLicense($names)';
}

String _normalizeOne(String name) {
  final lower = name.toLowerCase();
  if (lower.contains('apache') && lower.contains('2')) return 'Apache-2.0';
  if (lower == 'bsd-3-clause') return 'BSD-3-Clause';
  if (lower == 'lgpl-2.1-or-later') return 'LGPL-2.1-or-later';
  throw UnknownLicense([name]);
}

/// The POM's licence names as one name: the spellings of Apache 2.0 are one; several names mean a
/// choice between them ("A OR B", in alphabetical order).
String normalizeLicenses(List<String> names) {
  if (names.isEmpty) throw UnknownLicense(names);
  final normal = {for (final name in names) _normalizeOne(name)}.toList()..sort();
  return normal.join(' OR ');
}
