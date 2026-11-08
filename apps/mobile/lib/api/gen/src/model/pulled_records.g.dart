// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pulled_records.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PulledRecords extends PulledRecords {
  @override
  final BuiltList<SyncRecord> records;
  @override
  final int? next;
  @override
  final int latest;

  factory _$PulledRecords([void Function(PulledRecordsBuilder)? updates]) =>
      (PulledRecordsBuilder()..update(updates))._build();

  _$PulledRecords._({required this.records, this.next, required this.latest}) : super._();
  @override
  PulledRecords rebuild(void Function(PulledRecordsBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PulledRecordsBuilder toBuilder() => PulledRecordsBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PulledRecords &&
        records == other.records &&
        next == other.next &&
        latest == other.latest;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, records.hashCode);
    _$hash = $jc(_$hash, next.hashCode);
    _$hash = $jc(_$hash, latest.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PulledRecords')
          ..add('records', records)
          ..add('next', next)
          ..add('latest', latest))
        .toString();
  }
}

class PulledRecordsBuilder implements Builder<PulledRecords, PulledRecordsBuilder> {
  _$PulledRecords? _$v;

  ListBuilder<SyncRecord>? _records;
  ListBuilder<SyncRecord> get records => _$this._records ??= ListBuilder<SyncRecord>();
  set records(ListBuilder<SyncRecord>? records) => _$this._records = records;

  int? _next;
  int? get next => _$this._next;
  set next(int? next) => _$this._next = next;

  int? _latest;
  int? get latest => _$this._latest;
  set latest(int? latest) => _$this._latest = latest;

  PulledRecordsBuilder() {
    PulledRecords._defaults(this);
  }

  PulledRecordsBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _records = $v.records.toBuilder();
      _next = $v.next;
      _latest = $v.latest;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PulledRecords other) {
    _$v = other as _$PulledRecords;
  }

  @override
  void update(void Function(PulledRecordsBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PulledRecords build() => _build();

  _$PulledRecords _build() {
    _$PulledRecords _$result;
    try {
      _$result =
          _$v ??
          _$PulledRecords._(
            records: records.build(),
            next: next,
            latest: BuiltValueNullFieldError.checkNotNull(latest, r'PulledRecords', 'latest'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'records';
        records.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(r'PulledRecords', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
