//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'migration_counts.g.dart';

/// Per type, the live rows (records), and the soft-deleted transactions apart. The one `settings` record is checked apart.
///
/// Properties:
/// * [transaction]
/// * [deletedTransaction] - Soft-deleted transactions (dismissed months among them): records deleted with a body
/// * [category]
/// * [budget]
/// * [recurrence]
/// * [merchant]
@BuiltValue()
abstract class MigrationCounts implements Built<MigrationCounts, MigrationCountsBuilder> {
  @BuiltValueField(wireName: r'transaction')
  int get transaction;

  /// Soft-deleted transactions (dismissed months among them): records deleted with a body
  @BuiltValueField(wireName: r'deletedTransaction')
  int get deletedTransaction;

  @BuiltValueField(wireName: r'category')
  int get category;

  @BuiltValueField(wireName: r'budget')
  int get budget;

  @BuiltValueField(wireName: r'recurrence')
  int get recurrence;

  @BuiltValueField(wireName: r'merchant')
  int get merchant;

  MigrationCounts._();

  factory MigrationCounts([void updates(MigrationCountsBuilder b)]) = _$MigrationCounts;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MigrationCountsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<MigrationCounts> get serializer => _$MigrationCountsSerializer();
}

class _$MigrationCountsSerializer implements PrimitiveSerializer<MigrationCounts> {
  @override
  final Iterable<Type> types = const [MigrationCounts, _$MigrationCounts];

  @override
  final String wireName = r'MigrationCounts';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MigrationCounts object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'transaction';
    yield serializers.serialize(object.transaction, specifiedType: const FullType(int));
    yield r'deletedTransaction';
    yield serializers.serialize(object.deletedTransaction, specifiedType: const FullType(int));
    yield r'category';
    yield serializers.serialize(object.category, specifiedType: const FullType(int));
    yield r'budget';
    yield serializers.serialize(object.budget, specifiedType: const FullType(int));
    yield r'recurrence';
    yield serializers.serialize(object.recurrence, specifiedType: const FullType(int));
    yield r'merchant';
    yield serializers.serialize(object.merchant, specifiedType: const FullType(int));
  }

  @override
  Object serialize(
    Serializers serializers,
    MigrationCounts object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required MigrationCountsBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'transaction':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(int)) as int;
          result.transaction = valueDes;
          break;
        case r'deletedTransaction':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(int)) as int;
          result.deletedTransaction = valueDes;
          break;
        case r'category':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(int)) as int;
          result.category = valueDes;
          break;
        case r'budget':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(int)) as int;
          result.budget = valueDes;
          break;
        case r'recurrence':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(int)) as int;
          result.recurrence = valueDes;
          break;
        case r'merchant':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(int)) as int;
          result.merchant = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  MigrationCounts deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MigrationCountsBuilder();
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
