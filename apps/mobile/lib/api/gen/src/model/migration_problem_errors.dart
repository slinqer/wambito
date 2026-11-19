//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:wambito/api/gen/src/model/migration_counts.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'migration_problem_errors.g.dart';

/// MigrationProblemErrors
///
/// Properties:
/// * [server]
/// * [records]
/// * [client]
@BuiltValue()
abstract class MigrationProblemErrors
    implements Built<MigrationProblemErrors, MigrationProblemErrorsBuilder> {
  @BuiltValueField(wireName: r'server')
  MigrationCounts get server;

  @BuiltValueField(wireName: r'records')
  MigrationCounts get records;

  @BuiltValueField(wireName: r'client')
  MigrationCounts get client;

  MigrationProblemErrors._();

  factory MigrationProblemErrors([void updates(MigrationProblemErrorsBuilder b)]) =
      _$MigrationProblemErrors;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MigrationProblemErrorsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<MigrationProblemErrors> get serializer => _$MigrationProblemErrorsSerializer();
}

class _$MigrationProblemErrorsSerializer implements PrimitiveSerializer<MigrationProblemErrors> {
  @override
  final Iterable<Type> types = const [MigrationProblemErrors, _$MigrationProblemErrors];

  @override
  final String wireName = r'MigrationProblemErrors';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MigrationProblemErrors object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'server';
    yield serializers.serialize(object.server, specifiedType: const FullType(MigrationCounts));
    yield r'records';
    yield serializers.serialize(object.records, specifiedType: const FullType(MigrationCounts));
    yield r'client';
    yield serializers.serialize(object.client, specifiedType: const FullType(MigrationCounts));
  }

  @override
  Object serialize(
    Serializers serializers,
    MigrationProblemErrors object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required MigrationProblemErrorsBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'server':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(MigrationCounts),
          ) as MigrationCounts;
          result.server.replace(valueDes);
          break;
        case r'records':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(MigrationCounts),
          ) as MigrationCounts;
          result.records.replace(valueDes);
          break;
        case r'client':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(MigrationCounts),
          ) as MigrationCounts;
          result.client.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  MigrationProblemErrors deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MigrationProblemErrorsBuilder();
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
