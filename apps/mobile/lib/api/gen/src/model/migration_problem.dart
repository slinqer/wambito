//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:wambito/api/gen/src/model/migration_problem_errors.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'migration_problem.g.dart';

/// MigrationProblem
///
/// Properties:
/// * [type]
/// * [title]
/// * [status]
/// * [code]
/// * [detail]
/// * [errors]
@BuiltValue()
abstract class MigrationProblem implements Built<MigrationProblem, MigrationProblemBuilder> {
  @BuiltValueField(wireName: r'type')
  String get type;

  @BuiltValueField(wireName: r'title')
  String get title;

  @BuiltValueField(wireName: r'status')
  int get status;

  @BuiltValueField(wireName: r'code')
  String get code;

  @BuiltValueField(wireName: r'detail')
  String? get detail;

  @BuiltValueField(wireName: r'errors')
  MigrationProblemErrors? get errors;

  MigrationProblem._();

  factory MigrationProblem([void updates(MigrationProblemBuilder b)]) = _$MigrationProblem;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MigrationProblemBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<MigrationProblem> get serializer => _$MigrationProblemSerializer();
}

class _$MigrationProblemSerializer implements PrimitiveSerializer<MigrationProblem> {
  @override
  final Iterable<Type> types = const [MigrationProblem, _$MigrationProblem];

  @override
  final String wireName = r'MigrationProblem';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MigrationProblem object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'type';
    yield serializers.serialize(object.type, specifiedType: const FullType(String));
    yield r'title';
    yield serializers.serialize(object.title, specifiedType: const FullType(String));
    yield r'status';
    yield serializers.serialize(object.status, specifiedType: const FullType(int));
    yield r'code';
    yield serializers.serialize(object.code, specifiedType: const FullType(String));
    if (object.detail != null) {
      yield r'detail';
      yield serializers.serialize(object.detail, specifiedType: const FullType(String));
    }
    if (object.errors != null) {
      yield r'errors';
      yield serializers.serialize(
        object.errors,
        specifiedType: const FullType(MigrationProblemErrors),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    MigrationProblem object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required MigrationProblemBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'type':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.type = valueDes;
          break;
        case r'title':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.title = valueDes;
          break;
        case r'status':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(int)) as int;
          result.status = valueDes;
          break;
        case r'code':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.code = valueDes;
          break;
        case r'detail':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.detail = valueDes;
          break;
        case r'errors':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(MigrationProblemErrors),
          ) as MigrationProblemErrors?;
          if (valueDes == null) continue;
          result.errors.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  MigrationProblem deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MigrationProblemBuilder();
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
