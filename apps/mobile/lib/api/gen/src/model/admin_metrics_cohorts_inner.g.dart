// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'admin_metrics_cohorts_inner.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AdminMetricsCohortsInner extends AdminMetricsCohortsInner {
  @override
  final String weekStart;
  @override
  final int size;
  @override
  final int? week1;
  @override
  final int? week4;
  @override
  final int? week12;

  factory _$AdminMetricsCohortsInner([void Function(AdminMetricsCohortsInnerBuilder)? updates]) =>
      (AdminMetricsCohortsInnerBuilder()..update(updates))._build();

  _$AdminMetricsCohortsInner._({
    required this.weekStart,
    required this.size,
    this.week1,
    this.week4,
    this.week12,
  }) : super._();
  @override
  AdminMetricsCohortsInner rebuild(void Function(AdminMetricsCohortsInnerBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AdminMetricsCohortsInnerBuilder toBuilder() => AdminMetricsCohortsInnerBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AdminMetricsCohortsInner &&
        weekStart == other.weekStart &&
        size == other.size &&
        week1 == other.week1 &&
        week4 == other.week4 &&
        week12 == other.week12;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, weekStart.hashCode);
    _$hash = $jc(_$hash, size.hashCode);
    _$hash = $jc(_$hash, week1.hashCode);
    _$hash = $jc(_$hash, week4.hashCode);
    _$hash = $jc(_$hash, week12.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AdminMetricsCohortsInner')
          ..add('weekStart', weekStart)
          ..add('size', size)
          ..add('week1', week1)
          ..add('week4', week4)
          ..add('week12', week12))
        .toString();
  }
}

class AdminMetricsCohortsInnerBuilder
    implements Builder<AdminMetricsCohortsInner, AdminMetricsCohortsInnerBuilder> {
  _$AdminMetricsCohortsInner? _$v;

  String? _weekStart;
  String? get weekStart => _$this._weekStart;
  set weekStart(String? weekStart) => _$this._weekStart = weekStart;

  int? _size;
  int? get size => _$this._size;
  set size(int? size) => _$this._size = size;

  int? _week1;
  int? get week1 => _$this._week1;
  set week1(int? week1) => _$this._week1 = week1;

  int? _week4;
  int? get week4 => _$this._week4;
  set week4(int? week4) => _$this._week4 = week4;

  int? _week12;
  int? get week12 => _$this._week12;
  set week12(int? week12) => _$this._week12 = week12;

  AdminMetricsCohortsInnerBuilder() {
    AdminMetricsCohortsInner._defaults(this);
  }

  AdminMetricsCohortsInnerBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _weekStart = $v.weekStart;
      _size = $v.size;
      _week1 = $v.week1;
      _week4 = $v.week4;
      _week12 = $v.week12;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AdminMetricsCohortsInner other) {
    _$v = other as _$AdminMetricsCohortsInner;
  }

  @override
  void update(void Function(AdminMetricsCohortsInnerBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AdminMetricsCohortsInner build() => _build();

  _$AdminMetricsCohortsInner _build() {
    final _$result =
        _$v ??
        _$AdminMetricsCohortsInner._(
          weekStart: BuiltValueNullFieldError.checkNotNull(
            weekStart,
            r'AdminMetricsCohortsInner',
            'weekStart',
          ),
          size: BuiltValueNullFieldError.checkNotNull(size, r'AdminMetricsCohortsInner', 'size'),
          week1: week1,
          week4: week4,
          week12: week12,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
