//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'migration_source_merchants_inner.g.dart';

/// MigrationSourceMerchantsInner
///
/// Properties:
/// * [id]
/// * [merchantKey]
/// * [categoryId]
/// * [createdAt] - ISO 8601 timestamp
/// * [updatedAt] - ISO 8601 timestamp
@BuiltValue()
abstract class MigrationSourceMerchantsInner
    implements Built<MigrationSourceMerchantsInner, MigrationSourceMerchantsInnerBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'merchantKey')
  String get merchantKey;

  @BuiltValueField(wireName: r'categoryId')
  String get categoryId;

  /// ISO 8601 timestamp
  @BuiltValueField(wireName: r'createdAt')
  String get createdAt;

  /// ISO 8601 timestamp
  @BuiltValueField(wireName: r'updatedAt')
  String get updatedAt;

  MigrationSourceMerchantsInner._();

  factory MigrationSourceMerchantsInner([void updates(MigrationSourceMerchantsInnerBuilder b)]) =
      _$MigrationSourceMerchantsInner;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MigrationSourceMerchantsInnerBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<MigrationSourceMerchantsInner> get serializer =>
      _$MigrationSourceMerchantsInnerSerializer();
}

class _$MigrationSourceMerchantsInnerSerializer
    implements PrimitiveSerializer<MigrationSourceMerchantsInner> {
  @override
  final Iterable<Type> types = const [
    MigrationSourceMerchantsInner,
    _$MigrationSourceMerchantsInner,
  ];

  @override
  final String wireName = r'MigrationSourceMerchantsInner';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MigrationSourceMerchantsInner object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(object.id, specifiedType: const FullType(String));
    yield r'merchantKey';
    yield serializers.serialize(object.merchantKey, specifiedType: const FullType(String));
    yield r'categoryId';
    yield serializers.serialize(object.categoryId, specifiedType: const FullType(String));
    yield r'createdAt';
    yield serializers.serialize(object.createdAt, specifiedType: const FullType(String));
    yield r'updatedAt';
    yield serializers.serialize(object.updatedAt, specifiedType: const FullType(String));
  }

  @override
  Object serialize(
    Serializers serializers,
    MigrationSourceMerchantsInner object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required MigrationSourceMerchantsInnerBuilder result,
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
        case r'merchantKey':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.merchantKey = valueDes;
          break;
        case r'categoryId':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.categoryId = valueDes;
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
  MigrationSourceMerchantsInner deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MigrationSourceMerchantsInnerBuilder();
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
