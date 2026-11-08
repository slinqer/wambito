// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'push_records.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PushRecords extends PushRecords {
  @override
  final BuiltList<SyncChange> changes;

  factory _$PushRecords([void Function(PushRecordsBuilder)? updates]) =>
      (PushRecordsBuilder()..update(updates))._build();

  _$PushRecords._({required this.changes}) : super._();
  @override
  PushRecords rebuild(void Function(PushRecordsBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PushRecordsBuilder toBuilder() => PushRecordsBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PushRecords && changes == other.changes;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, changes.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PushRecords')..add('changes', changes)).toString();
  }
}

class PushRecordsBuilder implements Builder<PushRecords, PushRecordsBuilder> {
  _$PushRecords? _$v;

  ListBuilder<SyncChange>? _changes;
  ListBuilder<SyncChange> get changes => _$this._changes ??= ListBuilder<SyncChange>();
  set changes(ListBuilder<SyncChange>? changes) => _$this._changes = changes;

  PushRecordsBuilder() {
    PushRecords._defaults(this);
  }

  PushRecordsBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _changes = $v.changes.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PushRecords other) {
    _$v = other as _$PushRecords;
  }

  @override
  void update(void Function(PushRecordsBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PushRecords build() => _build();

  _$PushRecords _build() {
    _$PushRecords _$result;
    try {
      _$result = _$v ?? _$PushRecords._(changes: changes.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'changes';
        changes.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(r'PushRecords', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
