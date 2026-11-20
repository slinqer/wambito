//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'migration_source_categories_inner.g.dart';

/// MigrationSourceCategoriesInner
///
/// Properties:
/// * [id]
/// * [name]
/// * [kind]
/// * [icon]
/// * [color]
/// * [sortOrder]
/// * [archivedAt] - ISO 8601 timestamp
/// * [systemKey]
/// * [createdAt] - ISO 8601 timestamp
/// * [updatedAt] - ISO 8601 timestamp
@BuiltValue()
abstract class MigrationSourceCategoriesInner
    implements Built<MigrationSourceCategoriesInner, MigrationSourceCategoriesInnerBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'name')
  String get name;

  @BuiltValueField(wireName: r'kind')
  MigrationSourceCategoriesInnerKindEnum get kind;
  // enum kindEnum {  expense,  income,  };

  @BuiltValueField(wireName: r'icon')
  String get icon;

  @BuiltValueField(wireName: r'color')
  String get color;

  @BuiltValueField(wireName: r'sortOrder')
  int get sortOrder;

  /// ISO 8601 timestamp
  @BuiltValueField(wireName: r'archivedAt')
  String? get archivedAt;

  @BuiltValueField(wireName: r'systemKey')
  String? get systemKey;

  /// ISO 8601 timestamp
  @BuiltValueField(wireName: r'createdAt')
  String get createdAt;

  /// ISO 8601 timestamp
  @BuiltValueField(wireName: r'updatedAt')
  String get updatedAt;

  MigrationSourceCategoriesInner._();

  factory MigrationSourceCategoriesInner([void updates(MigrationSourceCategoriesInnerBuilder b)]) =
      _$MigrationSourceCategoriesInner;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MigrationSourceCategoriesInnerBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<MigrationSourceCategoriesInner> get serializer =>
      _$MigrationSourceCategoriesInnerSerializer();
}

class _$MigrationSourceCategoriesInnerSerializer
    implements PrimitiveSerializer<MigrationSourceCategoriesInner> {
  @override
  final Iterable<Type> types = const [
    MigrationSourceCategoriesInner,
    _$MigrationSourceCategoriesInner,
  ];

  @override
  final String wireName = r'MigrationSourceCategoriesInner';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MigrationSourceCategoriesInner object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(object.id, specifiedType: const FullType(String));
    yield r'name';
    yield serializers.serialize(object.name, specifiedType: const FullType(String));
    yield r'kind';
    yield serializers.serialize(
      object.kind,
      specifiedType: const FullType(MigrationSourceCategoriesInnerKindEnum),
    );
    yield r'icon';
    yield serializers.serialize(object.icon, specifiedType: const FullType(String));
    yield r'color';
    yield serializers.serialize(object.color, specifiedType: const FullType(String));
    yield r'sortOrder';
    yield serializers.serialize(object.sortOrder, specifiedType: const FullType(int));
    yield r'archivedAt';
    yield object.archivedAt == null
        ? null
        : serializers.serialize(object.archivedAt, specifiedType: const FullType.nullable(String));
    yield r'systemKey';
    yield object.systemKey == null
        ? null
        : serializers.serialize(object.systemKey, specifiedType: const FullType.nullable(String));
    yield r'createdAt';
    yield serializers.serialize(object.createdAt, specifiedType: const FullType(String));
    yield r'updatedAt';
    yield serializers.serialize(object.updatedAt, specifiedType: const FullType(String));
  }

  @override
  Object serialize(
    Serializers serializers,
    MigrationSourceCategoriesInner object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required MigrationSourceCategoriesInnerBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'id':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.id = valueDes;
          break;
        case r'name':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.name = valueDes;
          break;
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(MigrationSourceCategoriesInnerKindEnum),
          ) as MigrationSourceCategoriesInnerKindEnum;
          result.kind = valueDes;
          break;
        case r'icon':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.icon = valueDes;
          break;
        case r'color':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.color = valueDes;
          break;
        case r'sortOrder':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(int)) as int;
          result.sortOrder = valueDes;
          break;
        case r'archivedAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.archivedAt = valueDes;
          break;
        case r'systemKey':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.systemKey = valueDes;
          break;
        case r'createdAt':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.createdAt = valueDes;
          break;
        case r'updatedAt':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.updatedAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  MigrationSourceCategoriesInner deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MigrationSourceCategoriesInnerBuilder();
    final serializedList = (serialized as Iterable<Object?>).toList();
    final unhandled = <Object?>[];
    _deserializeProperties(
      serializers,
      serialized,
      specifiedType: specifiedType,
      serializedList: serializedList,
      unhandled: unhandled,
      result: result,
    );
    return result.build();
  }
}

class MigrationSourceCategoriesInnerKindEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'expense')
  static const MigrationSourceCategoriesInnerKindEnum expense =
      _$migrationSourceCategoriesInnerKindEnum_expense;
  @BuiltValueEnumConst(wireName: r'income')
  static const MigrationSourceCategoriesInnerKindEnum income =
      _$migrationSourceCategoriesInnerKindEnum_income;

  static Serializer<MigrationSourceCategoriesInnerKindEnum> get serializer =>
      _$migrationSourceCategoriesInnerKindEnumSerializer;

  const MigrationSourceCategoriesInnerKindEnum._(String name) : super(name);

  static BuiltSet<MigrationSourceCategoriesInnerKindEnum> get values =>
      _$migrationSourceCategoriesInnerKindEnumValues;
  static MigrationSourceCategoriesInnerKindEnum valueOf(String name) =>
      _$migrationSourceCategoriesInnerKindEnumValueOf(name);
}
