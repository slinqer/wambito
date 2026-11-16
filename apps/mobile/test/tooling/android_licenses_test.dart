import 'package:flutter_test/flutter_test.dart';

import '../../scripts/android_licenses_lib.dart';

const _deps = '''

------------------------------------------------------------
Project ':app'
------------------------------------------------------------

releaseRuntimeClasspath - Runtime classpath of '/release'.
+--- org.jetbrains.kotlin:kotlin-stdlib:2.4.0
|    +--- org.jetbrains:annotations:13.0 -> 23.0.0
|    +--- org.jetbrains.kotlin:kotlin-stdlib-jdk8:1.8.0 -> 1.9.0 (c)
|    \\--- org.jetbrains.kotlin:kotlin-stdlib-common:2.4.0 (c)
+--- androidx.credentials:credentials:1.6.0
|    +--- androidx.annotation:annotation:1.8.1 -> 1.9.1
|    |    \\--- androidx.annotation:annotation-jvm:1.9.1
|    |         \\--- org.jetbrains.kotlin:kotlin-stdlib:1.9.24 -> 2.4.0 (*)
|    \\--- androidx.core:core:1.8.0 -> 1.15.0
\\--- io.flutter:flutter_embedding_release:1.0.0-deb287481e
''';

String _pom(List<String> licenses, {String? parent}) =>
    '''
<project>
  ${parent == null ? '' : '<parent><groupId>g</groupId><artifactId>$parent</artifactId><version>1</version></parent>'}
  <groupId>g</groupId><artifactId>a</artifactId>
  ${licenses.isEmpty ? '' : '<licenses>${licenses.map((n) => '<license><name>$n</name><url>u</url></license>').join()}</licenses>'}
</project>''';

void main() {
  group('the release classpath', () {
    test('lists each resolved artifact once, at the version that wins', () {
      final libraries = resolvedLibraries(_deps);
      expect(
        [for (final l in libraries) '${l.id} ${l.version}'],
        [
          'androidx.annotation:annotation 1.9.1',
          'androidx.annotation:annotation-jvm 1.9.1',
          'androidx.core:core 1.15.0',
          'androidx.credentials:credentials 1.6.0',
          'org.jetbrains.kotlin:kotlin-stdlib 2.4.0',
          'org.jetbrains:annotations 23.0.0',
        ],
      );
    });

    test('constraints (c) are not dependencies, and Flutter\'s own engine is left to Flutter', () {
      final ids = [for (final l in resolvedLibraries(_deps)) l.id];
      expect(ids, isNot(contains('org.jetbrains.kotlin:kotlin-stdlib-common')));
      expect(ids, isNot(contains('org.jetbrains.kotlin:kotlin-stdlib-jdk8')));
      expect(ids.where((id) => id.startsWith('io.flutter')), isEmpty);
    });
  });

  group(
    'a library built from source (scripts/build-native-deps.sh, -Pwambito.nativeFromSource)',
    () {
      test(
        'is listed at the release it was built from, and its POM looked up at its own version',
        () {
          final libraries = resolvedLibraries('''
releaseRuntimeClasspath - Runtime classpath of '/release'.
+--- com.alphacephei:vosk-android:0.3.75-src
+--- net.java.dev.jna:jna:5.18.1-src
\\--- androidx.core:core:1.15.0
''');
          expect(
            [for (final l in libraries) '${l.id} ${l.version} ${l.release}'],
            [
              'androidx.core:core 1.15.0 1.15.0',
              'com.alphacephei:vosk-android 0.3.75-src 0.3.75',
              'net.java.dev.jna:jna 5.18.1-src 5.18.1',
            ],
          );
        },
      );

      test('has its POM in the local repository, android/third_party/m2', () {
        expect(
          localRepositoryPom('net.java.dev.jna', 'jna', '5.18.1-src'),
          'android/third_party/m2/net/java/dev/jna/jna/5.18.1-src/jna-5.18.1-src.pom',
        );
      });
    },
  );

  group('a POM\'s licence', () {
    test('is read from its <licenses>, not from its parent\'s declaration', () {
      expect(pomLicenses(_pom(['The Apache Software License, Version 2.0'], parent: 'p')), [
        'The Apache Software License, Version 2.0',
      ]);
    });

    test('with none of its own, the parent decides; the caller is told by null', () {
      expect(pomLicenses(_pom([], parent: 'p')), isEmpty);
      expect(pomParent(_pom([], parent: 'p')), ('g', 'p', '1'));
      expect(pomParent(_pom([])), isNull);
    });

    test('all the spellings of Apache 2.0 in the real POMs are one licence', () {
      for (final name in [
        'The Apache Software License, Version 2.0',
        'The Apache License, Version 2.0',
        'Apache License, Version 2.0',
        'Apache-2.0',
        'Apache 2.0',
      ]) {
        expect(normalizeLicenses([name]), 'Apache-2.0', reason: name);
      }
    });

    test('BSD-3-Clause stays BSD-3-Clause; a dual licence names both, in a fixed order', () {
      expect(normalizeLicenses(['BSD-3-Clause']), 'BSD-3-Clause');
      expect(
        normalizeLicenses(['LGPL-2.1-or-later', 'Apache-2.0']),
        'Apache-2.0 OR LGPL-2.1-or-later',
      );
    });

    test('a licence nobody has looked at is an error, not a guess', () {
      expect(() => normalizeLicenses(['Some Custom Licence']), throwsA(isA<UnknownLicense>()));
      expect(() => normalizeLicenses([]), throwsA(isA<UnknownLicense>()));
    });
  });

  test('the generated file reads back as the same libraries', () {
    final libraries = [
      const AndroidLibrary('androidx.core:core', '1.15.0', 'Apache-2.0'),
      const AndroidLibrary('x:y', '2', 'BSD-3-Clause'),
    ];
    final json = renderLibraries(libraries);
    expect(json.endsWith('\n'), isTrue);
    expect(parseLibraries(json).map((l) => '${l.id} ${l.version} ${l.license}'), [
      'androidx.core:core 1.15.0 Apache-2.0',
      'x:y 2 BSD-3-Clause',
    ]);
  });
}
