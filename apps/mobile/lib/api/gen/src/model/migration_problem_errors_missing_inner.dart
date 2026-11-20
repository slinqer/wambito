//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'migration_problem_errors_missing_inner.g.dart';

/// MigrationProblemErrorsMissingInner
///
/// Properties:
/// * [type]
/// * [id]
@BuiltValue()
abstract class MigrationProblemErrorsMissingInner
    implements
        Built<MigrationProblemErrorsMissingInner, MigrationProblemErrorsMissingInnerBuilder> {
  @BuiltValueField(wireName: r'type')
  String get type;

  @BuiltValueField(wireName: r'id')
  String get id;

  MigrationProblemErrorsMissingInner._();

  factory MigrationProblemErrorsMissingInner([
    void updates(MigrationProblemErrorsMissingInnerBuilder b),
  ]) = _$MigrationProblemErrorsMissingInner;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MigrationProblemErrorsMissingInnerBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<MigrationProblemErrorsMissingInner> get serializer =>
      _$MigrationProblemErrorsMissingInnerSerializer();
}

class _$MigrationProblemErrorsMissingInnerSerializer
    implements PrimitiveSerializer<MigrationProblemErrorsMissingInner> {
  @override
  final Iterable<Type> types = const [
    MigrationProblemErrorsMissingInner,
    _$MigrationProblemErrorsMissingInner,
  ];

  @override
  final String wireName = r'MigrationProblemErrorsMissingInner';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MigrationProblemErrorsMissingInner object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'type';
    yield serializers.serialize(object.type, specifiedType: const FullType(String));
    yield r'id';
    yield serializers.serialize(object.id, specifiedType: const FullType(String));
  }

  @override
  Object serialize(
    Serializers serializers,
    MigrationProblemErrorsMissingInner object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required MigrationProblemErrorsMissingInnerBuilder result,
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
        case r'id':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.id = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  MigrationProblemErrorsMissingInner deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MigrationProblemErrorsMissingInnerBuilder();
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
