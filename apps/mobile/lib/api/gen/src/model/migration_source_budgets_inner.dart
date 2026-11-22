//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'migration_source_budgets_inner.g.dart';

/// MigrationSourceBudgetsInner
///
/// Properties:
/// * [id]
/// * [categoryId]
/// * [amount]
/// * [effectiveFrom] - `YYYY-MM-DD`, the first day of the month
/// * [createdAt] - ISO 8601 timestamp
/// * [updatedAt] - ISO 8601 timestamp
@BuiltValue()
abstract class MigrationSourceBudgetsInner
    implements Built<MigrationSourceBudgetsInner, MigrationSourceBudgetsInnerBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'categoryId')
  String get categoryId;

  @BuiltValueField(wireName: r'amount')
  int get amount;

  /// `YYYY-MM-DD`, the first day of the month
  @BuiltValueField(wireName: r'effectiveFrom')
  String get effectiveFrom;

  /// ISO 8601 timestamp
  @BuiltValueField(wireName: r'createdAt')
  String get createdAt;

  /// ISO 8601 timestamp
  @BuiltValueField(wireName: r'updatedAt')
  String get updatedAt;

  MigrationSourceBudgetsInner._();

  factory MigrationSourceBudgetsInner([void updates(MigrationSourceBudgetsInnerBuilder b)]) =
      _$MigrationSourceBudgetsInner;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MigrationSourceBudgetsInnerBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<MigrationSourceBudgetsInner> get serializer =>
      _$MigrationSourceBudgetsInnerSerializer();
}

class _$MigrationSourceBudgetsInnerSerializer
    implements PrimitiveSerializer<MigrationSourceBudgetsInner> {
  @override
  final Iterable<Type> types = const [MigrationSourceBudgetsInner, _$MigrationSourceBudgetsInner];

  @override
  final String wireName = r'MigrationSourceBudgetsInner';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MigrationSourceBudgetsInner object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(object.id, specifiedType: const FullType(String));
    yield r'categoryId';
    yield serializers.serialize(object.categoryId, specifiedType: const FullType(String));
    yield r'amount';
    yield serializers.serialize(object.amount, specifiedType: const FullType(int));
    yield r'effectiveFrom';
    yield serializers.serialize(object.effectiveFrom, specifiedType: const FullType(String));
    yield r'createdAt';
    yield serializers.serialize(object.createdAt, specifiedType: const FullType(String));
    yield r'updatedAt';
    yield serializers.serialize(object.updatedAt, specifiedType: const FullType(String));
  }

  @override
  Object serialize(
    Serializers serializers,
    MigrationSourceBudgetsInner object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required MigrationSourceBudgetsInnerBuilder result,
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
        case r'categoryId':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.categoryId = valueDes;
          break;
        case r'amount':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(int)) as int;
          result.amount = valueDes;
          break;
        case r'effectiveFrom':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.effectiveFrom = valueDes;
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
  MigrationSourceBudgetsInner deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MigrationSourceBudgetsInnerBuilder();
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
