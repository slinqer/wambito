// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'finish_migration.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$FinishMigration extends FinishMigration {
  @override
  final MigrationCounts counts;

  factory _$FinishMigration([void Function(FinishMigrationBuilder)? updates]) =>
      (FinishMigrationBuilder()..update(updates))._build();

  _$FinishMigration._({required this.counts}) : super._();
  @override
  FinishMigration rebuild(void Function(FinishMigrationBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  FinishMigrationBuilder toBuilder() => FinishMigrationBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is FinishMigration && counts == other.counts;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, counts.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'FinishMigration')..add('counts', counts)).toString();
  }
}

class FinishMigrationBuilder implements Builder<FinishMigration, FinishMigrationBuilder> {
  _$FinishMigration? _$v;

  MigrationCountsBuilder? _counts;
  MigrationCountsBuilder get counts => _$this._counts ??= MigrationCountsBuilder();
  set counts(MigrationCountsBuilder? counts) => _$this._counts = counts;

  FinishMigrationBuilder() {
    FinishMigration._defaults(this);
  }

  FinishMigrationBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _counts = $v.counts.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(FinishMigration other) {
    _$v = other as _$FinishMigration;
  }

  @override
  void update(void Function(FinishMigrationBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  FinishMigration build() => _build();

  _$FinishMigration _build() {
    _$FinishMigration _$result;
    try {
      _$result = _$v ?? _$FinishMigration._(counts: counts.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'counts';
        counts.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(r'FinishMigration', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
