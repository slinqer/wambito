// An encrypted (`preview`) account: automatic capture works (D8). The settings section shows the
// switches, what is queued is kept and handed to the vault through `sendQueued`, and the phone's
// jobs are told the account's mode.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/capture_auto/capture_platform.dart';

import 'package:wambito/vault/preview_sync.dart';

import '../settings/harness.dart';
import '../support/preview_account.dart';
import 'fakes.dart';

class _Native implements NativeEncryptionMode {
  final writes = <String?>[];

  @override
  Future<void> write(String? mode, String? owner) async => writes.add(mode);
}

void main() {
  testWidgets('an encrypted account has the capture switches, no "coming soon"', (t) async {
    final fake = FakeAutoCapturePlatform(sources: {'revolut'});
    await pumpSettingsApp(
      t,
      location: '/settings',
      overrides: [...previewOpen(), autoCapturePlatformProvider.overrideWithValue(fake)],
    );
    await t.scrollUntilVisible(
      find.byKey(const Key('autoCapture.revolut')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await t.pumpAndSettle();

    expect(find.byKey(const Key('autoCapture.comingSoon')), findsNothing);
    for (final source in CaptureSource.values) {
      expect(find.byKey(Key('autoCapture.${source.wire}')), findsOneWidget);
    }
  });

  testWidgets('becoming preview sends what is queued and never clears it', (t) async {
    final fake = FakeAutoCapturePlatform(sources: {'revolut'});
    final native = _Native();
    await pumpSettingsApp(
      t,
      location: '/settings',
      overrides: [
        ...previewOpen(),
        autoCapturePlatformProvider.overrideWithValue(fake),
        nativeEncryptionModeProvider.overrideWithValue(native),
      ],
    );
    await t.pumpAndSettle();
    expect(native.writes.last, 'preview');
    // The session's own sign-in call and the mode's: both hand the queue over, neither clears it.
    expect(fake.callsNamed('sendQueued'), isNotEmpty);
    expect(fake.callsNamed('clearQueue'), isEmpty);
  });

  testWidgets('a plain account keeps its switches and clears nothing', (t) async {
    final fake = FakeAutoCapturePlatform();
    await pumpSettingsApp(
      t,
      location: '/settings',
      overrides: [autoCapturePlatformProvider.overrideWithValue(fake)],
    );
    await t.scrollUntilVisible(
      find.byKey(const Key('autoCapture.revolut')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('autoCapture.comingSoon')), findsNothing);
    expect(fake.callsNamed('clearQueue'), isEmpty);
  });
}
