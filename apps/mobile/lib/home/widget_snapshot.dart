import 'dart:convert';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import '../api/gen/wambito_api.dart';

/// The key the home snapshot is stored under (see [signedInSnapshot]).
const widgetSnapshotKey = 'wambito.widget.snapshot';

/// The snapshot's shape version. The Kotlin widget draws "Abre Wambito para empezar" for any other
/// (`android/.../widget/WidgetSnapshot.kt`), so a phone that still holds an older snapshot never
/// shows it as figures. Version 3 added `timezone`.
const widgetSnapshotVersion = 3;

/// The two widgets' receivers (`android/.../widget/`), which `updateWidgets` asks to redraw.
const widgetReceivers = [
  'com.wambito.app.widget.WambitoSmallWidgetReceiver',
  'com.wambito.app.widget.WambitoMediumWidgetReceiver',
];

/// Where the snapshot is kept. The app stores it with `home_widget`, which writes Android's
/// SharedPreferences; tests replace it.
abstract interface class WidgetStore {
  Future<void> save(String key, String value);

  /// What is stored under [key], or null.
  Future<String?> read(String key);

  /// Removes what is stored under [key].
  Future<void> remove(String key);

  /// Asks Android to redraw the widgets on the home screen from what is stored.
  Future<void> updateWidgets();
}

/// Where the snapshot is kept (replaced in tests).
final widgetStoreProvider = Provider<WidgetStore>((ref) => const HomeWidgetStore());

/// [WidgetStore] over `home_widget` (BSD-3, AndroidX only: no Google Play Services).
class HomeWidgetStore implements WidgetStore {
  const HomeWidgetStore();

  @override
  Future<void> save(String key, String value) async {
    await HomeWidget.saveWidgetData<String>(key, value);
  }

  @override
  Future<String?> read(String key) => HomeWidget.getWidgetData<String>(key);

  @override
  Future<void> remove(String key) async {
    // home_widget removes a key saved as null.
    await HomeWidget.saveWidgetData<String>(key, null);
  }

  @override
  Future<void> updateWidgets() async {
    // The widgets are Android's (Glance); iOS has none, and `home_widget` would only look for them.
    if (defaultTargetPlatform != TargetPlatform.android) return;
    for (final receiver in widgetReceivers) {
      await HomeWidget.updateWidget(qualifiedAndroidName: receiver);
    }
  }
}

/// What the home-screen widget shows (spec section 7.1) for a signed-in person, so the Kotlin
/// widget (Jetpack Glance) and its refresh job (`RefreshWorker.kt`) read it without starting
/// Flutter. The refresh job writes the same shape from `GET /v1/summary`.
///
/// **Where.** One JSON string under the key [widgetSnapshotKey] (`wambito.widget.snapshot`) in the
/// Android SharedPreferences file `HomeWidgetPreferences`, which is where `home_widget` keeps its
/// values.
///
/// **Shape**, version 3 (a reader ignores unknown fields and draws "Abre Wambito para empezar" for
/// a `v` it does not know, or when `signedIn` is not true):
///
/// ```json
/// {
///   "v": 3,
///   "signedIn": true,
///   "remaining": 150000000,    // cents, like the API: budgetTotal - spent, negative when over
///   "spent": 50000000,         // cents spent this month
///   "budgetTotal": 200000000,  // cents; 0 means no budgets ("Gastado este mes")
///   "currency": "COP",
///   "locale": "es",            // "es" | "en" | "it" | "pt": the widget's words and how the amount is written
///   "month": "2026-10",        // the month of the figures
///   "mood": "happy",           // Wambi's face: "happy" | "worried" (a category near or over)
///   "updatedAt": "2026-10-22T15:30:00.000Z",  // UTC, when these figures came from the server
///   "hideAmount": false,       // Settings' "Ocultar el monto en el widget": draw "••••"
///   "theme": "dark",           // the app's theme choice: "dark" | "light" | "system"
///   "timezone": "America/Bogota"  // the profile's IANA zone: "this month" and midnight are read
///                                 // in it, as the app reads its figures (the phone's without one)
/// }
/// ```
///
/// The refresh job may add `"refreshFailedAt"` (UTC) when it could not reach the server, so the
/// widget marks the figures "hace un rato"; the app's writes drop it (their figures are fresh) and
/// [withChoices] keeps it.
///
/// Amounts stay in cents so the widget and its refresh job write money one way
/// (`android/.../widget/Money.kt`, the same rules as lib/money/format.dart).
Map<String, Object?> signedInSnapshot(
  Summary summary, {
  required String currency,
  required String locale,
  required bool hideAmount,
  required String theme,
  required DateTime updatedAt,
  required String timezone,
}) {
  final worried = summary.categories.any((c) => c.state != SummaryCategoriesInnerStateEnum.ok);
  return {
    'v': widgetSnapshotVersion,
    'signedIn': true,
    'remaining': summary.remaining,
    'spent': summary.spent,
    'budgetTotal': summary.budgetTotal,
    'currency': currency,
    'locale': locale,
    'month': summary.month,
    'mood': worried ? 'worried' : 'happy',
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'hideAmount': hideAmount,
    'theme': theme,
    'timezone': timezone,
  };
}

/// What the widget shows with nobody signed in: "Abre Wambito para empezar", in the app's theme
/// and language. It holds no figure at all, so after a sign-out nothing of the previous person is
/// left for the widget (or its refresh job) to draw (Review Focus 4).
Map<String, Object?> signedOutSnapshot({
  required bool hideAmount,
  required String theme,
  String? locale,
}) => {
  'v': widgetSnapshotVersion,
  'signedIn': false,
  'hideAmount': hideAmount,
  'theme': theme,
  'locale': ?locale,
};

/// The stored snapshot [json] with the person's new choices, its figures and their time
/// unchanged; null when there is nothing of this version to patch.
Map<String, Object?>? withChoices(String? json, {required bool hideAmount, required String theme}) {
  if (json == null) return null;
  final Object? doc;
  try {
    doc = jsonDecode(json);
  } on FormatException {
    return null;
  }
  if (doc is! Map<String, Object?> || doc['v'] != widgetSnapshotVersion) return null;
  return {...doc, 'hideAmount': hideAmount, 'theme': theme};
}

/// Stores [snapshot] and asks the widgets to redraw. A store that cannot be reached (no plugin, a
/// storage error) is ignored: the widget keeps what it had.
Future<void> saveWidgetSnapshot(WidgetStore store, Map<String, Object?> snapshot) async {
  try {
    await store.save(widgetSnapshotKey, jsonEncode(snapshot));
    await store.updateWidgets();
  } on MissingPluginException {
    // No plugin (tests, a desktop run): nothing to update.
  } on PlatformException {
    // The widget keeps what it had.
  }
}
