//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'push_rejected.g.dart';

/// PushRejected
///
/// Properties:
/// * [id]
/// * [error]
@BuiltValue()
abstract class PushRejected implements Built<PushRejected, PushRejectedBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'error')
  PushRejectedErrorEnum get error;
  // enum errorEnum {  id_taken,  };

  PushRejected._();

  factory PushRejected([void updates(PushRejectedBuilder b)]) = _$PushRejected;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PushRejectedBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PushRejected> get serializer => _$PushRejectedSerializer();
}

class _$PushRejectedSerializer implements PrimitiveSerializer<PushRejected> {
  @override
  final Iterable<Type> types = const [PushRejected, _$PushRejected];

  @override
  final String wireName = r'PushRejected';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PushRejected object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(object.id, specifiedType: const FullType(String));
    yield r'error';
    yield serializers.serialize(object.error, specifiedType: const FullType(PushRejectedErrorEnum));
  }

  @override
  Object serialize(
    Serializers serializers,
    PushRejected object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PushRejectedBuilder result,
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
        case r'error':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PushRejectedErrorEnum),
          ) as PushRejectedErrorEnum;
          result.error = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PushRejected deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PushRejectedBuilder();
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

class PushRejectedErrorEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'id_taken')
  static const PushRejectedErrorEnum idTaken = _$pushRejectedErrorEnum_idTaken;

  static Serializer<PushRejectedErrorEnum> get serializer => _$pushRejectedErrorEnumSerializer;

  const PushRejectedErrorEnum._(String name) : super(name);

  static BuiltSet<PushRejectedErrorEnum> get values => _$pushRejectedErrorEnumValues;
  static PushRejectedErrorEnum valueOf(String name) => _$pushRejectedErrorEnumValueOf(name);
}
