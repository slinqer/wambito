import '../core/records.dart' show Json;
import '../crypto/records.dart' show RecordType;
import 'store.dart';

class _Entry {
  _Entry(this.body, this.deleted);
  final Json body;
  final bool deleted;
}

typedef _Table = Map<String, _Entry>;
typedef _Overlay = Map<RecordType, _Table>;

Object? _cloneValue(Object? v) {
  if (v is Map) return {for (final e in v.entries) e.key as String: _cloneValue(e.value)};
  if (v is List) return [for (final e in v) _cloneValue(e)];
  return v;
}

Json _clone(Json body) => _cloneValue(body)! as Json;

/// The demo's state behind [FinanceStore]: plain maps, no persistence, no outbox. A transaction
/// stages its writes in an overlay and merges it on success. Maps keep insertion order, so a
/// replaced key keeps its position.
FinanceStore createMemoryStore() => _MemoryStore();

class _MemoryStore implements FinanceStore {
  final Map<RecordType, _Table> _tables = {};
  final Set<void Function()> _listeners = {};
  Future<void> _queue = Future<void>.value();

  _Table _table(RecordType type) => _tables.putIfAbsent(type, () => {});

  @override
  Future<R> transaction<R>(Future<R> Function(StoreOps tx) fn) {
    Future<R> run() async {
      final overlay = <RecordType, _Table>{};
      final result = await fn(_Ops(this, overlay));
      if (_commit(overlay)) {
        for (final listener in List.of(_listeners)) {
          listener();
        }
      }
      return result;
    }

    final next = _queue.then((_) => run());
    _queue = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  bool _commit(_Overlay overlay) {
    var changed = false;
    for (final entry in overlay.entries) {
      final t = _table(entry.key);
      for (final change in entry.value.entries) {
        changed = true;
        t[change.key] = change.value;
      }
    }
    return changed;
  }

  // Each bare operation is a transaction of its own, so it queues and notifies like one.
  @override
  Future<StoredRecord?> get(RecordType type, String id, [ReadOptions opts = const ReadOptions()]) =>
      transaction((tx) => tx.get(type, id, opts));

  @override
  Future<List<StoredRecord>> list(RecordType type, [ReadOptions opts = const ReadOptions()]) =>
      transaction((tx) => tx.list(type, opts));

  @override
  Future<void> put(
    RecordType type,
    String id,
    Json body, [
    WriteOptions opts = const WriteOptions(),
  ]) => transaction((tx) => tx.put(type, id, body, opts));

  @override
  Future<void> delete(RecordType type, String id, [WriteOptions opts = const WriteOptions()]) =>
      transaction((tx) => tx.delete(type, id, opts));

  @override
  void Function() subscribe(void Function() listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }
}

class _Ops implements StoreOps {
  _Ops(this._store, this._overlay);

  final _MemoryStore _store;
  final _Overlay _overlay;

  _Table _staged(RecordType type) => _overlay.putIfAbsent(type, () => {});

  _Entry? _lookup(RecordType type, String id) {
    final o = _overlay[type];
    if (o != null && o.containsKey(id)) return o[id];
    return _store._table(type)[id];
  }

  StoredRecord _record(String id, _Entry e) =>
      StoredRecord(id: id, body: _clone(e.body), deleted: e.deleted);

  @override
  Future<StoredRecord?> get(
    RecordType type,
    String id, [
    ReadOptions opts = const ReadOptions(),
  ]) async {
    final entry = _lookup(type, id);
    if (entry == null || (entry.deleted && !opts.includeDeleted)) return null;
    return _record(id, entry);
  }

  @override
  Future<List<StoredRecord>> list(RecordType type, [ReadOptions opts = const ReadOptions()]) async {
    final o = _overlay[type];
    final base = _store._table(type);
    final out = <StoredRecord>[];
    void add(String id, _Entry? entry) {
      if (entry == null || (entry.deleted && !opts.includeDeleted)) return;
      out.add(_record(id, entry));
    }

    for (final e in base.entries) {
      add(e.key, o != null && o.containsKey(e.key) ? o[e.key] : e.value);
    }
    if (o != null) {
      for (final e in o.entries) {
        if (!base.containsKey(e.key)) add(e.key, e.value);
      }
    }
    return out;
  }

  @override
  Future<void> put(
    RecordType type,
    String id,
    Json body, [
    WriteOptions opts = const WriteOptions(),
  ]) async {
    _staged(type)[id] = _Entry(_clone(body), false);
  }

  @override
  Future<void> delete(
    RecordType type,
    String id, [
    WriteOptions opts = const WriteOptions(),
  ]) async {
    final entry = _lookup(type, id);
    if (entry == null) return;
    _staged(type)[id] = _Entry(entry.body, true);
  }
}
