// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'admin_metrics_daily_active_inner.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AdminMetricsDailyActiveInner extends AdminMetricsDailyActiveInner {
  @override
  final String day;
  @override
  final int count;

  factory _$AdminMetricsDailyActiveInner([
    void Function(AdminMetricsDailyActiveInnerBuilder)? updates,
  ]) => (AdminMetricsDailyActiveInnerBuilder()..update(updates))._build();

  _$AdminMetricsDailyActiveInner._({required this.day, required this.count}) : super._();
  @override
  AdminMetricsDailyActiveInner rebuild(
    void Function(AdminMetricsDailyActiveInnerBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  AdminMetricsDailyActiveInnerBuilder toBuilder() =>
      AdminMetricsDailyActiveInnerBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AdminMetricsDailyActiveInner && day == other.day && count == other.count;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, day.hashCode);
    _$hash = $jc(_$hash, count.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AdminMetricsDailyActiveInner')
          ..add('day', day)
          ..add('count', count))
        .toString();
  }
}

class AdminMetricsDailyActiveInnerBuilder
    implements Builder<AdminMetricsDailyActiveInner, AdminMetricsDailyActiveInnerBuilder> {
  _$AdminMetricsDailyActiveInner? _$v;

  String? _day;
  String? get day => _$this._day;
  set day(String? day) => _$this._day = day;

  int? _count;
  int? get count => _$this._count;
  set count(int? count) => _$this._count = count;

  AdminMetricsDailyActiveInnerBuilder() {
    AdminMetricsDailyActiveInner._defaults(this);
  }

  AdminMetricsDailyActiveInnerBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _day = $v.day;
      _count = $v.count;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AdminMetricsDailyActiveInner other) {
    _$v = other as _$AdminMetricsDailyActiveInner;
  }

  @override
  void update(void Function(AdminMetricsDailyActiveInnerBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AdminMetricsDailyActiveInner build() => _build();

  _$AdminMetricsDailyActiveInner _build() {
    final _$result =
        _$v ??
        _$AdminMetricsDailyActiveInner._(
          day: BuiltValueNullFieldError.checkNotNull(day, r'AdminMetricsDailyActiveInner', 'day'),
          count: BuiltValueNullFieldError.checkNotNull(
            count,
            r'AdminMetricsDailyActiveInner',
            'count',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
