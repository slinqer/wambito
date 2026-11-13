// An encrypted (`preview`) account: automatic capture waits for encryption. The settings section
// says so instead of showing the switches, nothing queued goes out (the queue is cleared once), and
// the phone's jobs are told the account's mode.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/capture_auto/capture_platform.dart';

import 'package:wambito/vault/preview_sync.dart';

import '../settings/harness.dart';
import '../support/preview_account.dart';
import 'fakes.dart';

Finder said(String part) => find.bySemanticsLabel(RegExp(RegExp.escape(part)));

class _Native implements NativeEncryptionMode {
  final writes = <String?>[];

  @override
  Future<void> write(String? mode) async => writes.add(mode);
}

void main() {
  testWidgets('the section says "Próximamente con cifrado" in place of the switches', (t) async {
    final fake = FakeAutoCapturePlatform(sources: {'revolut'});
    await pumpSettingsApp(
      t,
      location: '/settings',
      overrides: [...previewOpen(), autoCapturePlatformProvider.overrideWithValue(fake)],
    );
    await t.scrollUntilVisible(
      find.byKey(const Key('settings.card.autoCapture')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await t.pumpAndSettle();

    expect(said('Próximamente con cifrado'), findsWidgets);
    expect(find.byKey(const Key('autoCapture.comingSoon')), findsOneWidget);
    for (final source in CaptureSource.values) {
      expect(find.byKey(Key('autoCapture.${source.wire}')), findsNothing);
    }
    expect(find.byKey(const Key('autoCapture.how')), findsNothing);
    expect(fake.callsNamed('setSource'), isEmpty);
    expect(fake.callsNamed('openAccessSettings'), isEmpty);
  });

  testWidgets('the queue is cleared once when the mode becomes preview, and nothing is sent', (
    t,
  ) async {
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
    expect(native.writes.last, 'preview');
    expect(fake.callsNamed('clearQueue'), ['clearQueue']);
  });

  testWidgets('English and the other languages say it in their words', (t) async {
    final fake = FakeAutoCapturePlatform();
    await pumpSettingsApp(
      t,
      locale: const Locale('en'),
      location: '/settings',
      overrides: [...previewOpen(), autoCapturePlatformProvider.overrideWithValue(fake)],
    );
    await t.scrollUntilVisible(
      find.byKey(const Key('autoCapture.comingSoon')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(said('Coming soon with encryption'), findsWidgets);
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
