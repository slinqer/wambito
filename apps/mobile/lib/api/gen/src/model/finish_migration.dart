//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:wambito/api/gen/src/model/migration_counts.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'finish_migration.g.dart';

/// FinishMigration
///
/// Properties:
/// * [counts]
@BuiltValue()
abstract class FinishMigration implements Built<FinishMigration, FinishMigrationBuilder> {
  @BuiltValueField(wireName: r'counts')
  MigrationCounts get counts;

  FinishMigration._();

  factory FinishMigration([void updates(FinishMigrationBuilder b)]) = _$FinishMigration;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(FinishMigrationBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<FinishMigration> get serializer => _$FinishMigrationSerializer();
}

class _$FinishMigrationSerializer implements PrimitiveSerializer<FinishMigration> {
  @override
  final Iterable<Type> types = const [FinishMigration, _$FinishMigration];

  @override
  final String wireName = r'FinishMigration';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    FinishMigration object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'counts';
    yield serializers.serialize(object.counts, specifiedType: const FullType(MigrationCounts));
  }

  @override
  Object serialize(
    Serializers serializers,
    FinishMigration object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required FinishMigrationBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'counts':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(MigrationCounts),
          ) as MigrationCounts;
          result.counts.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  FinishMigration deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = FinishMigrationBuilder();
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
