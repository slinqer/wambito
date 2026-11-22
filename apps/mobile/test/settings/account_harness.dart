// The Settings page with the account's export and deletion faked: what the server answers, the
// phone's files, and everything the app keeps that a deletion must clear.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/files/files_channel.dart';
import 'package:wambito/home/home_cache.dart';
import 'package:wambito/home/widget_snapshot.dart';
import 'package:wambito/notices/notice_platform.dart';
import 'package:wambito/settings/account_repository.dart';
import 'package:wambito/welcome/onboarding_repository.dart';

import '../home/fakes.dart';
import '../home/fixtures.dart';
import '../import/fakes.dart';
import '../notices/fakes.dart';
import 'fakes.dart';
import 'harness.dart';

/// The server's side of the account in memory: the export it makes and the deletion it does.
class FakeAccountRepository implements AccountRepository {
  /// Every export asked for.
  final exports = <ExportFormat>[];
  int deletes = 0;

  /// The next export / delete throws this (then cleared).
  Object? exportFailure;
  Object? deleteFailure;

  /// While set, the export / delete waits for it.
  Completer<void>? holdExport;
  Completer<void>? holdDelete;

  /// The file name the server gives, per format.
  String stamp = '2026-10-21';

  @override
  Future<ExportFile> export(ExportFormat format) async {
    exports.add(format);
    await holdExport?.future;
    final failure = exportFailure;
    if (failure != null) {
      exportFailure = null;
      throw failure;
    }
    final body = format == ExportFormat.csv
        ? 'date,name,amount\n2026-10-20,Arriendo,-1500\n'
        : '{"user":{"id":"user-1"}}';
    return ExportFile(
      name: 'wambito-export-$stamp.${format.name}',
      bytes: Uint8List.fromList(utf8.encode(body)),
      mime: format.mime,
    );
  }

  @override
  Future<void> deleteAccount() async {
    deletes++;
    await holdDelete?.future;
    final failure = deleteFailure;
    if (failure != null) {
      deleteFailure = null;
      throw failure;
    }
  }
}

class AccountEnv {
  AccountEnv(this.app, this.accounts, this.files, this.platform, this.cache, this.widgets);

  final SettingsEnv app;
  final FakeAccountRepository accounts;
  final FakeFilesChannel files;
  final FakeNoticePlatform platform;
  final FakeCacheStore cache;
  final FakeWidgetStore widgets;
}

/// Settings, signed in as `ana@example.com` (id `user-1`) unless [guest], with a cached home, a
/// signed-in widget snapshot, a draft of the welcome, the passkey offer answered, a card put away
/// and a voice model downloaded: what a deletion has to clear.
Future<AccountEnv> pumpAccount(
  WidgetTester t, {
  bool guest = false,
  Locale locale = const Locale('es'),
  String location = '/settings/account',
}) async {
  final accounts = FakeAccountRepository();
  final files = FakeFilesChannel();
  final platform = FakeNoticePlatform(permissionState: NoticePermission.granted);
  final cache = FakeCacheStore()..value = '{"v":1,"owner":"x"}';
  final widgets = FakeWidgetStore();
  widgets.saved[widgetSnapshotKey] = jsonEncode(
    signedInSnapshot(
      summary(budgetTotal: 100000, spent: 40000),
      currency: 'COP',
      locale: 'es',
      hideAmount: false,
      theme: 'dark',
      updatedAt: DateTime.utc(2026, 10, 21, 15),
      timezone: 'America/Bogota',
    ),
  );
  final home = FakeHomeRepository(email: guest ? '' : 'ana@example.com');
  final settings = FakeSettingsStore({
    'onboarding.draft.user-1': '{"currency":"EUR"}',
    'onboarding.draft.other': '{"currency":"USD"}',
    'passkey.offered': '["user-1","other"]',
    'wambito.unlock.no_prf.user-1': '1',
    'wambito.unlock.no_prf.other': '1',
  });
  final app = await pumpSettingsApp(
    t,
    guest: guest,
    locale: locale,
    homeRepo: home,
    settings: settings,
    overrides: [
      accountRepositoryProvider.overrideWithValue(accounts),
      filesChannelProvider.overrideWithValue(files),
      noticePlatformProvider.overrideWithValue(platform),
      homeCacheStoreProvider.overrideWithValue(cache),
      widgetStoreProvider.overrideWithValue(widgets),
      onboardingRepositoryProvider.overrideWithValue(FakeProfileServer(home)),
    ],
  );
  app.flags.putIfAbsent('home.dismissed.user-1.budgets', FakeFlagStore.new).value = true;
  app.flags.putIfAbsent('home.dismissed.user-1.import', FakeFlagStore.new).value = true;
  app.flags.putIfAbsent('home.dismissed.other.budgets', FakeFlagStore.new).value = true;
  app.router.go(location);
  await t.pumpAndSettle();
  return AccountEnv(app, accounts, files, platform, cache, widgets);
}

/// Brings the widget with [key] into view.
Future<void> scrollToKey(WidgetTester t, String key) async {
  await t.scrollUntilVisible(find.byKey(Key(key)), 200, scrollable: find.byType(Scrollable).first);
  await t.pumpAndSettle();
}
