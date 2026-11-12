import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/gen/wambito_api.dart';
import '../api/session.dart';
import '../storage/secure_storage.dart';

/// Where the cache is kept: one string. The app uses `flutter_secure_storage` (app-private, and
/// encrypted with a Keystore key, like the session token); tests use memory.
abstract interface class HomeCacheStore {
  Future<String?> read();
  Future<void> write(String json);
  Future<void> clear();
}

/// [HomeCacheStore] over `flutter_secure_storage`.
class SecureHomeCacheStore implements HomeCacheStore {
  const SecureHomeCacheStore([this._storage = appSecureStorage]);

  static const key = 'home.cache';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: key);

  @override
  Future<void> write(String json) => _storage.write(key: key, value: json);

  @override
  Future<void> clear() => _storage.delete(key: key);
}

/// What binds a document kept on the phone to the session that wrote it: a hash of the token,
/// never the token.
String sessionOwnerOf(String token) => sha256.convert(utf8.encode(token)).toString();

final homeCacheStoreProvider = Provider<HomeCacheStore>((ref) => const SecureHomeCacheStore());

/// Forgets the cache, when the session ends: it holds a person's figures, which the next person on
/// this phone must never see. Ignored when it cannot happen (the Keystore key is gone anyway).
Future<void> clearHomeCache(HomeCacheStore store) async {
  try {
    await store.clear();
  } catch (_) {
    // Nothing more to do.
  }
}

/// The last good month, kept for a start with no network (spec section 6.3: the last loaded summary
/// and list stay visible while offline).
class CachedHome {
  const CachedHome({
    required this.userId,
    required this.currency,
    required this.timezone,
    required this.month,
    required this.summary,
    required this.categories,
    required this.items,
  });

  final String userId;
  final String currency;
  final String timezone;

  /// `YYYY-MM`, the month the figures are of.
  final String month;
  final Summary summary;
  final List<Category> categories;

  /// The first page of the month's movements, newest first.
  final List<Transaction> items;
}

/// The home cache of one session. It is a single JSON document, version 1:
///
/// ```json
/// {"v": 1, "owner": "<sha-256 of the session token>", "userId": "...", "currency": "COP", "timezone": "America/Bogota",
///  "month": "2026-10", "summary": {...}, "categories": [...], "items": [...]}
/// ```
///
/// with the API's own JSON for the summary, categories and transactions. It is bound to the user
/// ([CachedHome.userId]) and to the session it was written in (`owner`, a SHA-256 of the token, so
/// the token itself stays only in the session store): another session, such as
/// another person signing in on this phone, reads nothing, and sign-out deletes it
/// ([clearHomeCache]). A cache that is missing, unreadable or of another version reads as nothing,
/// and a write that fails is ignored: it only ever makes home better, never worse.
class HomeCache {
  const HomeCache(this.store, {required this.token});

  static const version = 1;

  final HomeCacheStore store;

  /// The session's token; null when signed out (nothing is read or written then).
  final String? token;

  Future<CachedHome?> read() async {
    final token = this.token;
    if (token == null) return null;
    final owner = sessionOwnerOf(token);
    try {
      final raw = await store.read();
      if (raw == null) return null;
      final doc = jsonDecode(raw) as Map<String, Object?>;
      if (doc['v'] != version || doc['owner'] != owner) return null;
      return CachedHome(
        userId: doc['userId']! as String,
        currency: doc['currency']! as String,
        timezone: doc['timezone']! as String,
        month: doc['month']! as String,
        summary: standardSerializers.deserializeWith(Summary.serializer, doc['summary'])!,
        categories: [
          for (final c in doc['categories']! as List<Object?>)
            standardSerializers.deserializeWith(Category.serializer, c)!,
        ],
        items: [
          for (final t in doc['items']! as List<Object?>)
            // Rows cached before the field existed are not waiting for review.
            standardSerializers.deserializeWith(Transaction.serializer, {
              'needsReview': false,
              ...(t! as Map<String, Object?>),
            })!,
        ],
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> write(CachedHome home) async {
    final token = this.token;
    if (token == null) return;
    final owner = sessionOwnerOf(token);
    try {
      await store.write(
        jsonEncode({
          'v': version,
          'owner': owner,
          'userId': home.userId,
          'currency': home.currency,
          'timezone': home.timezone,
          'month': home.month,
          'summary': standardSerializers.serializeWith(Summary.serializer, home.summary),
          'categories': [
            for (final c in home.categories)
              standardSerializers.serializeWith(Category.serializer, c),
          ],
          'items': [
            for (final t in home.items)
              standardSerializers.serializeWith(Transaction.serializer, t),
          ],
        }),
      );
    } catch (_) {
      // The cache is a convenience.
    }
  }
}

/// The cache of the signed-in session (rebuilt when the token changes).
final homeCacheProvider = Provider<HomeCache>(
  (ref) => HomeCache(
    ref.watch(homeCacheStoreProvider),
    token: ref.watch(sessionProvider.select((s) => s.stored?.token)),
  ),
);
