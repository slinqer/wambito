// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_record.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const SyncRecordTypeEnum _$syncRecordTypeEnum_transaction = const SyncRecordTypeEnum._(
  'transaction',
);
const SyncRecordTypeEnum _$syncRecordTypeEnum_category = const SyncRecordTypeEnum._('category');
const SyncRecordTypeEnum _$syncRecordTypeEnum_budget = const SyncRecordTypeEnum._('budget');
const SyncRecordTypeEnum _$syncRecordTypeEnum_recurrence = const SyncRecordTypeEnum._('recurrence');
const SyncRecordTypeEnum _$syncRecordTypeEnum_merchant = const SyncRecordTypeEnum._('merchant');
const SyncRecordTypeEnum _$syncRecordTypeEnum_settings = const SyncRecordTypeEnum._('settings');
const SyncRecordTypeEnum _$syncRecordTypeEnum_account = const SyncRecordTypeEnum._('account');

SyncRecordTypeEnum _$syncRecordTypeEnumValueOf(String name) {
  switch (name) {
    case 'transaction':
      return _$syncRecordTypeEnum_transaction;
    case 'category':
      return _$syncRecordTypeEnum_category;
    case 'budget':
      return _$syncRecordTypeEnum_budget;
    case 'recurrence':
      return _$syncRecordTypeEnum_recurrence;
    case 'merchant':
      return _$syncRecordTypeEnum_merchant;
    case 'settings':
      return _$syncRecordTypeEnum_settings;
    case 'account':
      return _$syncRecordTypeEnum_account;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<SyncRecordTypeEnum> _$syncRecordTypeEnumValues = BuiltSet<SyncRecordTypeEnum>(
  const <SyncRecordTypeEnum>[
    _$syncRecordTypeEnum_transaction,
    _$syncRecordTypeEnum_category,
    _$syncRecordTypeEnum_budget,
    _$syncRecordTypeEnum_recurrence,
    _$syncRecordTypeEnum_merchant,
    _$syncRecordTypeEnum_settings,
    _$syncRecordTypeEnum_account,
  ],
);

Serializer<SyncRecordTypeEnum> _$syncRecordTypeEnumSerializer = _$SyncRecordTypeEnumSerializer();

class _$SyncRecordTypeEnumSerializer implements PrimitiveSerializer<SyncRecordTypeEnum> {
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
  final Iterable<Type> types = const <Type>[SyncRecordTypeEnum];
  @override
  final String wireName = 'SyncRecordTypeEnum';

  @override
  Object serialize(
    Serializers serializers,
    SyncRecordTypeEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  SyncRecordTypeEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) =>
      SyncRecordTypeEnum.valueOf(_fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$SyncRecord extends SyncRecord {
  @override
  final String id;
  @override
  final SyncRecordTypeEnum type;
  @override
  final bool deleted;
  @override
  final int keyV;
  @override
  final int encV;
  @override
  final int version;
  @override
  final String? body;

  factory _$SyncRecord([void Function(SyncRecordBuilder)? updates]) =>
      (SyncRecordBuilder()..update(updates))._build();

  _$SyncRecord._({
    required this.id,
    required this.type,
    required this.deleted,
    required this.keyV,
    required this.encV,
    required this.version,
    this.body,
  }) : super._();
  @override
  SyncRecord rebuild(void Function(SyncRecordBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SyncRecordBuilder toBuilder() => SyncRecordBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SyncRecord &&
        id == other.id &&
        type == other.type &&
        deleted == other.deleted &&
        keyV == other.keyV &&
        encV == other.encV &&
        version == other.version &&
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
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jc(_$hash, body.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SyncRecord')
          ..add('id', id)
          ..add('type', type)
          ..add('deleted', deleted)
          ..add('keyV', keyV)
          ..add('encV', encV)
          ..add('version', version)
          ..add('body', body))
        .toString();
  }
}

class SyncRecordBuilder implements Builder<SyncRecord, SyncRecordBuilder> {
  _$SyncRecord? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  SyncRecordTypeEnum? _type;
  SyncRecordTypeEnum? get type => _$this._type;
  set type(SyncRecordTypeEnum? type) => _$this._type = type;

  bool? _deleted;
  bool? get deleted => _$this._deleted;
  set deleted(bool? deleted) => _$this._deleted = deleted;

  int? _keyV;
  int? get keyV => _$this._keyV;
  set keyV(int? keyV) => _$this._keyV = keyV;

  int? _encV;
  int? get encV => _$this._encV;
  set encV(int? encV) => _$this._encV = encV;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  String? _body;
  String? get body => _$this._body;
  set body(String? body) => _$this._body = body;

  SyncRecordBuilder() {
    SyncRecord._defaults(this);
  }

  SyncRecordBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _type = $v.type;
      _deleted = $v.deleted;
      _keyV = $v.keyV;
      _encV = $v.encV;
      _version = $v.version;
      _body = $v.body;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SyncRecord other) {
    _$v = other as _$SyncRecord;
  }

  @override
  void update(void Function(SyncRecordBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SyncRecord build() => _build();

  _$SyncRecord _build() {
    final _$result =
        _$v ??
        _$SyncRecord._(
          id: BuiltValueNullFieldError.checkNotNull(id, r'SyncRecord', 'id'),
          type: BuiltValueNullFieldError.checkNotNull(type, r'SyncRecord', 'type'),
          deleted: BuiltValueNullFieldError.checkNotNull(deleted, r'SyncRecord', 'deleted'),
          keyV: BuiltValueNullFieldError.checkNotNull(keyV, r'SyncRecord', 'keyV'),
          encV: BuiltValueNullFieldError.checkNotNull(encV, r'SyncRecord', 'encV'),
          version: BuiltValueNullFieldError.checkNotNull(version, r'SyncRecord', 'version'),
          body: body,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
