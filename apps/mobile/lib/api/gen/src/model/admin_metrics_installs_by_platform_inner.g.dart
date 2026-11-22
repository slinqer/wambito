// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'admin_metrics_installs_by_platform_inner.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const AdminMetricsInstallsByPlatformInnerPlatformEnum
_$adminMetricsInstallsByPlatformInnerPlatformEnum_android =
    const AdminMetricsInstallsByPlatformInnerPlatformEnum._('android');
const AdminMetricsInstallsByPlatformInnerPlatformEnum
_$adminMetricsInstallsByPlatformInnerPlatformEnum_ios =
    const AdminMetricsInstallsByPlatformInnerPlatformEnum._('ios');
const AdminMetricsInstallsByPlatformInnerPlatformEnum
_$adminMetricsInstallsByPlatformInnerPlatformEnum_web =
    const AdminMetricsInstallsByPlatformInnerPlatformEnum._('web');
const AdminMetricsInstallsByPlatformInnerPlatformEnum
_$adminMetricsInstallsByPlatformInnerPlatformEnum_unknown =
    const AdminMetricsInstallsByPlatformInnerPlatformEnum._('unknown');

AdminMetricsInstallsByPlatformInnerPlatformEnum
_$adminMetricsInstallsByPlatformInnerPlatformEnumValueOf(String name) {
  switch (name) {
    case 'android':
      return _$adminMetricsInstallsByPlatformInnerPlatformEnum_android;
    case 'ios':
      return _$adminMetricsInstallsByPlatformInnerPlatformEnum_ios;
    case 'web':
      return _$adminMetricsInstallsByPlatformInnerPlatformEnum_web;
    case 'unknown':
      return _$adminMetricsInstallsByPlatformInnerPlatformEnum_unknown;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<AdminMetricsInstallsByPlatformInnerPlatformEnum>
_$adminMetricsInstallsByPlatformInnerPlatformEnumValues =
    BuiltSet<AdminMetricsInstallsByPlatformInnerPlatformEnum>(
      const <AdminMetricsInstallsByPlatformInnerPlatformEnum>[
        _$adminMetricsInstallsByPlatformInnerPlatformEnum_android,
        _$adminMetricsInstallsByPlatformInnerPlatformEnum_ios,
        _$adminMetricsInstallsByPlatformInnerPlatformEnum_web,
        _$adminMetricsInstallsByPlatformInnerPlatformEnum_unknown,
      ],
    );

Serializer<AdminMetricsInstallsByPlatformInnerPlatformEnum>
_$adminMetricsInstallsByPlatformInnerPlatformEnumSerializer =
    _$AdminMetricsInstallsByPlatformInnerPlatformEnumSerializer();

class _$AdminMetricsInstallsByPlatformInnerPlatformEnumSerializer
    implements PrimitiveSerializer<AdminMetricsInstallsByPlatformInnerPlatformEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'android': 'android',
    'ios': 'ios',
    'web': 'web',
    'unknown': 'unknown',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'android': 'android',
    'ios': 'ios',
    'web': 'web',
    'unknown': 'unknown',
  };

  @override
  final Iterable<Type> types = const <Type>[AdminMetricsInstallsByPlatformInnerPlatformEnum];
  @override
  final String wireName = 'AdminMetricsInstallsByPlatformInnerPlatformEnum';

  @override
  Object serialize(
    Serializers serializers,
    AdminMetricsInstallsByPlatformInnerPlatformEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  AdminMetricsInstallsByPlatformInnerPlatformEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => AdminMetricsInstallsByPlatformInnerPlatformEnum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$AdminMetricsInstallsByPlatformInner extends AdminMetricsInstallsByPlatformInner {
  @override
  final AdminMetricsInstallsByPlatformInnerPlatformEnum platform;
  @override
  final int count;

  factory _$AdminMetricsInstallsByPlatformInner([
    void Function(AdminMetricsInstallsByPlatformInnerBuilder)? updates,
  ]) => (AdminMetricsInstallsByPlatformInnerBuilder()..update(updates))._build();

  _$AdminMetricsInstallsByPlatformInner._({required this.platform, required this.count})
    : super._();
  @override
  AdminMetricsInstallsByPlatformInner rebuild(
    void Function(AdminMetricsInstallsByPlatformInnerBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  AdminMetricsInstallsByPlatformInnerBuilder toBuilder() =>
      AdminMetricsInstallsByPlatformInnerBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AdminMetricsInstallsByPlatformInner &&
        platform == other.platform &&
        count == other.count;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, platform.hashCode);
    _$hash = $jc(_$hash, count.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AdminMetricsInstallsByPlatformInner')
          ..add('platform', platform)
          ..add('count', count))
        .toString();
  }
}

class AdminMetricsInstallsByPlatformInnerBuilder
    implements
        Builder<AdminMetricsInstallsByPlatformInner, AdminMetricsInstallsByPlatformInnerBuilder> {
  _$AdminMetricsInstallsByPlatformInner? _$v;

  AdminMetricsInstallsByPlatformInnerPlatformEnum? _platform;
  AdminMetricsInstallsByPlatformInnerPlatformEnum? get platform => _$this._platform;
  set platform(AdminMetricsInstallsByPlatformInnerPlatformEnum? platform) =>
      _$this._platform = platform;

  int? _count;
  int? get count => _$this._count;
  set count(int? count) => _$this._count = count;

  AdminMetricsInstallsByPlatformInnerBuilder() {
    AdminMetricsInstallsByPlatformInner._defaults(this);
  }

  AdminMetricsInstallsByPlatformInnerBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _platform = $v.platform;
      _count = $v.count;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AdminMetricsInstallsByPlatformInner other) {
    _$v = other as _$AdminMetricsInstallsByPlatformInner;
  }

  @override
  void update(void Function(AdminMetricsInstallsByPlatformInnerBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AdminMetricsInstallsByPlatformInner build() => _build();

  _$AdminMetricsInstallsByPlatformInner _build() {
    final _$result =
        _$v ??
        _$AdminMetricsInstallsByPlatformInner._(
          platform: BuiltValueNullFieldError.checkNotNull(
            platform,
            r'AdminMetricsInstallsByPlatformInner',
            'platform',
          ),
          count: BuiltValueNullFieldError.checkNotNull(
            count,
            r'AdminMetricsInstallsByPlatformInner',
            'count',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
