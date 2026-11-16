// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'admin_metrics.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AdminMetrics extends AdminMetrics {
  @override
  final int total;
  @override
  final int withEmail;
  @override
  final int guests;
  @override
  final int active30d;
  @override
  final int suspended;
  @override
  final int signups7d;
  @override
  final int signupsPrev7d;
  @override
  final BuiltList<AdminMetricsWeeklyInner> weekly;
  @override
  final BuiltList<AdminMetricsDailyActiveInner> dailyActive;
  @override
  final BuiltList<AdminMetricsCohortsInner> cohorts;
  @override
  final BuiltList<AdminMetricsInstallsByPlatformInner> installsByPlatform;
  @override
  final BuiltList<AdminMetricsVersionsInner> versions;

  factory _$AdminMetrics([void Function(AdminMetricsBuilder)? updates]) =>
      (AdminMetricsBuilder()..update(updates))._build();

  _$AdminMetrics._({
    required this.total,
    required this.withEmail,
    required this.guests,
    required this.active30d,
    required this.suspended,
    required this.signups7d,
    required this.signupsPrev7d,
    required this.weekly,
    required this.dailyActive,
    required this.cohorts,
    required this.installsByPlatform,
    required this.versions,
  }) : super._();
  @override
  AdminMetrics rebuild(void Function(AdminMetricsBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AdminMetricsBuilder toBuilder() => AdminMetricsBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AdminMetrics &&
        total == other.total &&
        withEmail == other.withEmail &&
        guests == other.guests &&
        active30d == other.active30d &&
        suspended == other.suspended &&
        signups7d == other.signups7d &&
        signupsPrev7d == other.signupsPrev7d &&
        weekly == other.weekly &&
        dailyActive == other.dailyActive &&
        cohorts == other.cohorts &&
        installsByPlatform == other.installsByPlatform &&
        versions == other.versions;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, total.hashCode);
    _$hash = $jc(_$hash, withEmail.hashCode);
    _$hash = $jc(_$hash, guests.hashCode);
    _$hash = $jc(_$hash, active30d.hashCode);
    _$hash = $jc(_$hash, suspended.hashCode);
    _$hash = $jc(_$hash, signups7d.hashCode);
    _$hash = $jc(_$hash, signupsPrev7d.hashCode);
    _$hash = $jc(_$hash, weekly.hashCode);
    _$hash = $jc(_$hash, dailyActive.hashCode);
    _$hash = $jc(_$hash, cohorts.hashCode);
    _$hash = $jc(_$hash, installsByPlatform.hashCode);
    _$hash = $jc(_$hash, versions.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AdminMetrics')
          ..add('total', total)
          ..add('withEmail', withEmail)
          ..add('guests', guests)
          ..add('active30d', active30d)
          ..add('suspended', suspended)
          ..add('signups7d', signups7d)
          ..add('signupsPrev7d', signupsPrev7d)
          ..add('weekly', weekly)
          ..add('dailyActive', dailyActive)
          ..add('cohorts', cohorts)
          ..add('installsByPlatform', installsByPlatform)
          ..add('versions', versions))
        .toString();
  }
}

class AdminMetricsBuilder implements Builder<AdminMetrics, AdminMetricsBuilder> {
  _$AdminMetrics? _$v;

  int? _total;
  int? get total => _$this._total;
  set total(int? total) => _$this._total = total;

  int? _withEmail;
  int? get withEmail => _$this._withEmail;
  set withEmail(int? withEmail) => _$this._withEmail = withEmail;

  int? _guests;
  int? get guests => _$this._guests;
  set guests(int? guests) => _$this._guests = guests;

  int? _active30d;
  int? get active30d => _$this._active30d;
  set active30d(int? active30d) => _$this._active30d = active30d;

  int? _suspended;
  int? get suspended => _$this._suspended;
  set suspended(int? suspended) => _$this._suspended = suspended;

  int? _signups7d;
  int? get signups7d => _$this._signups7d;
  set signups7d(int? signups7d) => _$this._signups7d = signups7d;

  int? _signupsPrev7d;
  int? get signupsPrev7d => _$this._signupsPrev7d;
  set signupsPrev7d(int? signupsPrev7d) => _$this._signupsPrev7d = signupsPrev7d;

  ListBuilder<AdminMetricsWeeklyInner>? _weekly;
  ListBuilder<AdminMetricsWeeklyInner> get weekly =>
      _$this._weekly ??= ListBuilder<AdminMetricsWeeklyInner>();
  set weekly(ListBuilder<AdminMetricsWeeklyInner>? weekly) => _$this._weekly = weekly;

  ListBuilder<AdminMetricsDailyActiveInner>? _dailyActive;
  ListBuilder<AdminMetricsDailyActiveInner> get dailyActive =>
      _$this._dailyActive ??= ListBuilder<AdminMetricsDailyActiveInner>();
  set dailyActive(ListBuilder<AdminMetricsDailyActiveInner>? dailyActive) =>
      _$this._dailyActive = dailyActive;

  ListBuilder<AdminMetricsCohortsInner>? _cohorts;
  ListBuilder<AdminMetricsCohortsInner> get cohorts =>
      _$this._cohorts ??= ListBuilder<AdminMetricsCohortsInner>();
  set cohorts(ListBuilder<AdminMetricsCohortsInner>? cohorts) => _$this._cohorts = cohorts;

  ListBuilder<AdminMetricsInstallsByPlatformInner>? _installsByPlatform;
  ListBuilder<AdminMetricsInstallsByPlatformInner> get installsByPlatform =>
      _$this._installsByPlatform ??= ListBuilder<AdminMetricsInstallsByPlatformInner>();
  set installsByPlatform(ListBuilder<AdminMetricsInstallsByPlatformInner>? installsByPlatform) =>
      _$this._installsByPlatform = installsByPlatform;

  ListBuilder<AdminMetricsVersionsInner>? _versions;
  ListBuilder<AdminMetricsVersionsInner> get versions =>
      _$this._versions ??= ListBuilder<AdminMetricsVersionsInner>();
  set versions(ListBuilder<AdminMetricsVersionsInner>? versions) => _$this._versions = versions;

  AdminMetricsBuilder() {
    AdminMetrics._defaults(this);
  }

  AdminMetricsBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _total = $v.total;
      _withEmail = $v.withEmail;
      _guests = $v.guests;
      _active30d = $v.active30d;
      _suspended = $v.suspended;
      _signups7d = $v.signups7d;
      _signupsPrev7d = $v.signupsPrev7d;
      _weekly = $v.weekly.toBuilder();
      _dailyActive = $v.dailyActive.toBuilder();
      _cohorts = $v.cohorts.toBuilder();
      _installsByPlatform = $v.installsByPlatform.toBuilder();
      _versions = $v.versions.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AdminMetrics other) {
    _$v = other as _$AdminMetrics;
  }

  @override
  void update(void Function(AdminMetricsBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AdminMetrics build() => _build();

  _$AdminMetrics _build() {
    _$AdminMetrics _$result;
    try {
      _$result =
          _$v ??
          _$AdminMetrics._(
            total: BuiltValueNullFieldError.checkNotNull(total, r'AdminMetrics', 'total'),
            withEmail: BuiltValueNullFieldError.checkNotNull(
              withEmail,
              r'AdminMetrics',
              'withEmail',
            ),
            guests: BuiltValueNullFieldError.checkNotNull(guests, r'AdminMetrics', 'guests'),
            active30d: BuiltValueNullFieldError.checkNotNull(
              active30d,
              r'AdminMetrics',
              'active30d',
            ),
            suspended: BuiltValueNullFieldError.checkNotNull(
              suspended,
              r'AdminMetrics',
              'suspended',
            ),
            signups7d: BuiltValueNullFieldError.checkNotNull(
              signups7d,
              r'AdminMetrics',
              'signups7d',
            ),
            signupsPrev7d: BuiltValueNullFieldError.checkNotNull(
              signupsPrev7d,
              r'AdminMetrics',
              'signupsPrev7d',
            ),
            weekly: weekly.build(),
            dailyActive: dailyActive.build(),
            cohorts: cohorts.build(),
            installsByPlatform: installsByPlatform.build(),
            versions: versions.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'weekly';
        weekly.build();
        _$failedField = 'dailyActive';
        dailyActive.build();
        _$failedField = 'cohorts';
        cohorts.build();
        _$failedField = 'installsByPlatform';
        installsByPlatform.build();
        _$failedField = 'versions';
        versions.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(r'AdminMetrics', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
