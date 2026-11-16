// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'admin_metrics_versions_inner.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AdminMetricsVersionsInner extends AdminMetricsVersionsInner {
  @override
  final String platform;
  @override
  final String appVersion;
  @override
  final int users;

  factory _$AdminMetricsVersionsInner([void Function(AdminMetricsVersionsInnerBuilder)? updates]) =>
      (AdminMetricsVersionsInnerBuilder()..update(updates))._build();

  _$AdminMetricsVersionsInner._({
    required this.platform,
    required this.appVersion,
    required this.users,
  }) : super._();
  @override
  AdminMetricsVersionsInner rebuild(void Function(AdminMetricsVersionsInnerBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AdminMetricsVersionsInnerBuilder toBuilder() => AdminMetricsVersionsInnerBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AdminMetricsVersionsInner &&
        platform == other.platform &&
        appVersion == other.appVersion &&
        users == other.users;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, platform.hashCode);
    _$hash = $jc(_$hash, appVersion.hashCode);
    _$hash = $jc(_$hash, users.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AdminMetricsVersionsInner')
          ..add('platform', platform)
          ..add('appVersion', appVersion)
          ..add('users', users))
        .toString();
  }
}

class AdminMetricsVersionsInnerBuilder
    implements Builder<AdminMetricsVersionsInner, AdminMetricsVersionsInnerBuilder> {
  _$AdminMetricsVersionsInner? _$v;

  String? _platform;
  String? get platform => _$this._platform;
  set platform(String? platform) => _$this._platform = platform;

  String? _appVersion;
  String? get appVersion => _$this._appVersion;
  set appVersion(String? appVersion) => _$this._appVersion = appVersion;

  int? _users;
  int? get users => _$this._users;
  set users(int? users) => _$this._users = users;

  AdminMetricsVersionsInnerBuilder() {
    AdminMetricsVersionsInner._defaults(this);
  }

  AdminMetricsVersionsInnerBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _platform = $v.platform;
      _appVersion = $v.appVersion;
      _users = $v.users;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AdminMetricsVersionsInner other) {
    _$v = other as _$AdminMetricsVersionsInner;
  }

  @override
  void update(void Function(AdminMetricsVersionsInnerBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AdminMetricsVersionsInner build() => _build();

  _$AdminMetricsVersionsInner _build() {
    final _$result =
        _$v ??
        _$AdminMetricsVersionsInner._(
          platform: BuiltValueNullFieldError.checkNotNull(
            platform,
            r'AdminMetricsVersionsInner',
            'platform',
          ),
          appVersion: BuiltValueNullFieldError.checkNotNull(
            appVersion,
            r'AdminMetricsVersionsInner',
            'appVersion',
          ),
          users: BuiltValueNullFieldError.checkNotNull(
            users,
            r'AdminMetricsVersionsInner',
            'users',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
