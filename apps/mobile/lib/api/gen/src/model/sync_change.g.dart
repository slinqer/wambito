// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_change.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const SyncChangeTypeEnum _$syncChangeTypeEnum_transaction = const SyncChangeTypeEnum._(
  'transaction',
);
const SyncChangeTypeEnum _$syncChangeTypeEnum_category = const SyncChangeTypeEnum._('category');
const SyncChangeTypeEnum _$syncChangeTypeEnum_budget = const SyncChangeTypeEnum._('budget');
const SyncChangeTypeEnum _$syncChangeTypeEnum_recurrence = const SyncChangeTypeEnum._('recurrence');
const SyncChangeTypeEnum _$syncChangeTypeEnum_merchant = const SyncChangeTypeEnum._('merchant');
const SyncChangeTypeEnum _$syncChangeTypeEnum_settings = const SyncChangeTypeEnum._('settings');
const SyncChangeTypeEnum _$syncChangeTypeEnum_account = const SyncChangeTypeEnum._('account');

SyncChangeTypeEnum _$syncChangeTypeEnumValueOf(String name) {
  switch (name) {
    case 'transaction':
      return _$syncChangeTypeEnum_transaction;
    case 'category':
      return _$syncChangeTypeEnum_category;
    case 'budget':
      return _$syncChangeTypeEnum_budget;
    case 'recurrence':
      return _$syncChangeTypeEnum_recurrence;
    case 'merchant':
      return _$syncChangeTypeEnum_merchant;
    case 'settings':
      return _$syncChangeTypeEnum_settings;
    case 'account':
      return _$syncChangeTypeEnum_account;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<SyncChangeTypeEnum> _$syncChangeTypeEnumValues = BuiltSet<SyncChangeTypeEnum>(
  const <SyncChangeTypeEnum>[
    _$syncChangeTypeEnum_transaction,
    _$syncChangeTypeEnum_category,
    _$syncChangeTypeEnum_budget,
    _$syncChangeTypeEnum_recurrence,
    _$syncChangeTypeEnum_merchant,
    _$syncChangeTypeEnum_settings,
    _$syncChangeTypeEnum_account,
  ],
);

Serializer<SyncChangeTypeEnum> _$syncChangeTypeEnumSerializer = _$SyncChangeTypeEnumSerializer();

class _$SyncChangeTypeEnumSerializer implements PrimitiveSerializer<SyncChangeTypeEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'transaction': 'transaction',
    'category': 'category',
    'budget': 'budget',
    'recurrence': 'recurrence',
    'merchant': 'merchant',
    'settings': 'settings',
    'account': 'account',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'transaction': 'transaction',
    'category': 'category',
    'budget': 'budget',
    'recurrence': 'recurrence',
    'merchant': 'merchant',
    'settings': 'settings',
    'account': 'account',
  };

  @override
  final Iterable<Type> types = const <Type>[SyncChangeTypeEnum];
  @override
  final String wireName = 'SyncChangeTypeEnum';

  @override
  Object serialize(
    Serializers serializers,
    SyncChangeTypeEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  SyncChangeTypeEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) =>
      SyncChangeTypeEnum.valueOf(_fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$SyncChange extends SyncChange {
  @override
  final String id;
  @override
  final SyncChangeTypeEnum type;
  @override
  final bool deleted;
  @override
  final int keyV;
  @override
  final int encV;
  @override
  final int? baseVersion;
  @override
  final String? body;

  factory _$SyncChange([void Function(SyncChangeBuilder)? updates]) =>
      (SyncChangeBuilder()..update(updates))._build();

  _$SyncChange._({
    required this.id,
    required this.type,
    required this.deleted,
    required this.keyV,
    required this.encV,
    this.baseVersion,
    this.body,
  }) : super._();
  @override
  SyncChange rebuild(void Function(SyncChangeBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SyncChangeBuilder toBuilder() => SyncChangeBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SyncChange &&
        id == other.id &&
        type == other.type &&
        deleted == other.deleted &&
        keyV == other.keyV &&
        encV == other.encV &&
        baseVersion == other.baseVersion &&
        body == other.body;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, type.hashCode);
    _$hash = $jc(_$hash, deleted.hashCode);
    _$hash = $jc(_$hash, keyV.hashCode);
    _$hash = $jc(_$hash, encV.hashCode);
    _$hash = $jc(_$hash, baseVersion.hashCode);
    _$hash = $jc(_$hash, body.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SyncChange')
          ..add('id', id)
          ..add('type', type)
          ..add('deleted', deleted)
          ..add('keyV', keyV)
          ..add('encV', encV)
          ..add('baseVersion', baseVersion)
          ..add('body', body))
        .toString();
  }
}

class SyncChangeBuilder implements Builder<SyncChange, SyncChangeBuilder> {
  _$SyncChange? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  SyncChangeTypeEnum? _type;
  SyncChangeTypeEnum? get type => _$this._type;
  set type(SyncChangeTypeEnum? type) => _$this._type = type;

  bool? _deleted;
  bool? get deleted => _$this._deleted;
  set deleted(bool? deleted) => _$this._deleted = deleted;

  int? _keyV;
  int? get keyV => _$this._keyV;
  set keyV(int? keyV) => _$this._keyV = keyV;

  int? _encV;
  int? get encV => _$this._encV;
  set encV(int? encV) => _$this._encV = encV;

  int? _baseVersion;
  int? get baseVersion => _$this._baseVersion;
  set baseVersion(int? baseVersion) => _$this._baseVersion = baseVersion;

  String? _body;
  String? get body => _$this._body;
  set body(String? body) => _$this._body = body;

  SyncChangeBuilder() {
    SyncChange._defaults(this);
  }

  SyncChangeBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _type = $v.type;
      _deleted = $v.deleted;
      _keyV = $v.keyV;
      _encV = $v.encV;
      _baseVersion = $v.baseVersion;
      _body = $v.body;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SyncChange other) {
    _$v = other as _$SyncChange;
  }

  @override
  void update(void Function(SyncChangeBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SyncChange build() => _build();

  _$SyncChange _build() {
    final _$result =
        _$v ??
        _$SyncChange._(
          id: BuiltValueNullFieldError.checkNotNull(id, r'SyncChange', 'id'),
          type: BuiltValueNullFieldError.checkNotNull(type, r'SyncChange', 'type'),
          deleted: BuiltValueNullFieldError.checkNotNull(deleted, r'SyncChange', 'deleted'),
          keyV: BuiltValueNullFieldError.checkNotNull(keyV, r'SyncChange', 'keyV'),
          encV: BuiltValueNullFieldError.checkNotNull(encV, r'SyncChange', 'encV'),
          baseVersion: baseVersion,
          body: body,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
