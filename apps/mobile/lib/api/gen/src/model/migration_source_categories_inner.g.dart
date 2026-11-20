// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'migration_source_categories_inner.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const MigrationSourceCategoriesInnerKindEnum _$migrationSourceCategoriesInnerKindEnum_expense =
    const MigrationSourceCategoriesInnerKindEnum._('expense');
const MigrationSourceCategoriesInnerKindEnum _$migrationSourceCategoriesInnerKindEnum_income =
    const MigrationSourceCategoriesInnerKindEnum._('income');

MigrationSourceCategoriesInnerKindEnum _$migrationSourceCategoriesInnerKindEnumValueOf(
  String name,
) {
  switch (name) {
    case 'expense':
      return _$migrationSourceCategoriesInnerKindEnum_expense;
    case 'income':
      return _$migrationSourceCategoriesInnerKindEnum_income;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<MigrationSourceCategoriesInnerKindEnum>
_$migrationSourceCategoriesInnerKindEnumValues = BuiltSet<MigrationSourceCategoriesInnerKindEnum>(
  const <MigrationSourceCategoriesInnerKindEnum>[
    _$migrationSourceCategoriesInnerKindEnum_expense,
    _$migrationSourceCategoriesInnerKindEnum_income,
  ],
);

Serializer<MigrationSourceCategoriesInnerKindEnum>
_$migrationSourceCategoriesInnerKindEnumSerializer =
    _$MigrationSourceCategoriesInnerKindEnumSerializer();

class _$MigrationSourceCategoriesInnerKindEnumSerializer
    implements PrimitiveSerializer<MigrationSourceCategoriesInnerKindEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'expense': 'expense',
    'income': 'income',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'expense': 'expense',
    'income': 'income',
  };

  @override
  final Iterable<Type> types = const <Type>[MigrationSourceCategoriesInnerKindEnum];
  @override
  final String wireName = 'MigrationSourceCategoriesInnerKindEnum';

  @override
  Object serialize(
    Serializers serializers,
    MigrationSourceCategoriesInnerKindEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  MigrationSourceCategoriesInnerKindEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => MigrationSourceCategoriesInnerKindEnum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$MigrationSourceCategoriesInner extends MigrationSourceCategoriesInner {
  @override
  final String id;
  @override
  final String name;
  @override
  final MigrationSourceCategoriesInnerKindEnum kind;
  @override
  final String icon;
  @override
  final String color;
  @override
  final int sortOrder;
  @override
  final String? archivedAt;
  @override
  final String? systemKey;
  @override
  final String createdAt;
  @override
  final String updatedAt;

  factory _$MigrationSourceCategoriesInner([
    void Function(MigrationSourceCategoriesInnerBuilder)? updates,
  ]) => (MigrationSourceCategoriesInnerBuilder()..update(updates))._build();

  _$MigrationSourceCategoriesInner._({
    required this.id,
    required this.name,
    required this.kind,
    required this.icon,
    required this.color,
    required this.sortOrder,
    this.archivedAt,
    this.systemKey,
    required this.createdAt,
    required this.updatedAt,
  }) : super._();
  @override
  MigrationSourceCategoriesInner rebuild(
    void Function(MigrationSourceCategoriesInnerBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  MigrationSourceCategoriesInnerBuilder toBuilder() =>
      MigrationSourceCategoriesInnerBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MigrationSourceCategoriesInner &&
        id == other.id &&
        name == other.name &&
        kind == other.kind &&
        icon == other.icon &&
        color == other.color &&
        sortOrder == other.sortOrder &&
        archivedAt == other.archivedAt &&
        systemKey == other.systemKey &&
        createdAt == other.createdAt &&
        updatedAt == other.updatedAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, kind.hashCode);
    _$hash = $jc(_$hash, icon.hashCode);
    _$hash = $jc(_$hash, color.hashCode);
    _$hash = $jc(_$hash, sortOrder.hashCode);
    _$hash = $jc(_$hash, archivedAt.hashCode);
    _$hash = $jc(_$hash, systemKey.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jc(_$hash, updatedAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MigrationSourceCategoriesInner')
          ..add('id', id)
          ..add('name', name)
          ..add('kind', kind)
          ..add('icon', icon)
          ..add('color', color)
          ..add('sortOrder', sortOrder)
          ..add('archivedAt', archivedAt)
          ..add('systemKey', systemKey)
          ..add('createdAt', createdAt)
          ..add('updatedAt', updatedAt))
        .toString();
  }
}

class MigrationSourceCategoriesInnerBuilder
    implements Builder<MigrationSourceCategoriesInner, MigrationSourceCategoriesInnerBuilder> {
  _$MigrationSourceCategoriesInner? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  MigrationSourceCategoriesInnerKindEnum? _kind;
  MigrationSourceCategoriesInnerKindEnum? get kind => _$this._kind;
  set kind(MigrationSourceCategoriesInnerKindEnum? kind) => _$this._kind = kind;

  String? _icon;
  String? get icon => _$this._icon;
  set icon(String? icon) => _$this._icon = icon;

  String? _color;
  String? get color => _$this._color;
  set color(String? color) => _$this._color = color;

  int? _sortOrder;
  int? get sortOrder => _$this._sortOrder;
  set sortOrder(int? sortOrder) => _$this._sortOrder = sortOrder;

  String? _archivedAt;
  String? get archivedAt => _$this._archivedAt;
  set archivedAt(String? archivedAt) => _$this._archivedAt = archivedAt;

  String? _systemKey;
  String? get systemKey => _$this._systemKey;
  set systemKey(String? systemKey) => _$this._systemKey = systemKey;

  String? _createdAt;
  String? get createdAt => _$this._createdAt;
  set createdAt(String? createdAt) => _$this._createdAt = createdAt;

  String? _updatedAt;
  String? get updatedAt => _$this._updatedAt;
  set updatedAt(String? updatedAt) => _$this._updatedAt = updatedAt;

  MigrationSourceCategoriesInnerBuilder() {
    MigrationSourceCategoriesInner._defaults(this);
  }

  MigrationSourceCategoriesInnerBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _name = $v.name;
      _kind = $v.kind;
      _icon = $v.icon;
      _color = $v.color;
      _sortOrder = $v.sortOrder;
      _archivedAt = $v.archivedAt;
      _systemKey = $v.systemKey;
      _createdAt = $v.createdAt;
      _updatedAt = $v.updatedAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(MigrationSourceCategoriesInner other) {
    _$v = other as _$MigrationSourceCategoriesInner;
  }

  @override
  void update(void Function(MigrationSourceCategoriesInnerBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MigrationSourceCategoriesInner build() => _build();

  _$MigrationSourceCategoriesInner _build() {
    final _$result =
        _$v ??
        _$MigrationSourceCategoriesInner._(
          id: BuiltValueNullFieldError.checkNotNull(id, r'MigrationSourceCategoriesInner', 'id'),
          name: BuiltValueNullFieldError.checkNotNull(
            name,
            r'MigrationSourceCategoriesInner',
            'name',
          ),
          kind: BuiltValueNullFieldError.checkNotNull(
            kind,
            r'MigrationSourceCategoriesInner',
            'kind',
          ),
          icon: BuiltValueNullFieldError.checkNotNull(
            icon,
            r'MigrationSourceCategoriesInner',
            'icon',
          ),
          color: BuiltValueNullFieldError.checkNotNull(
            color,
            r'MigrationSourceCategoriesInner',
            'color',
          ),
          sortOrder: BuiltValueNullFieldError.checkNotNull(
            sortOrder,
            r'MigrationSourceCategoriesInner',
            'sortOrder',
          ),
          archivedAt: archivedAt,
          systemKey: systemKey,
          createdAt: BuiltValueNullFieldError.checkNotNull(
            createdAt,
            r'MigrationSourceCategoriesInner',
            'createdAt',
          ),
          updatedAt: BuiltValueNullFieldError.checkNotNull(
            updatedAt,
            r'MigrationSourceCategoriesInner',
            'updatedAt',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
