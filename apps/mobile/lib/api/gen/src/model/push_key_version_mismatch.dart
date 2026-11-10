//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'push_key_version_mismatch.g.dart';

/// The change's `keyV` is not the account's current key version (accounts with key wraps only); nothing was written. Re-seal it under the current key and push again.
///
/// Properties:
/// * [id]
/// * [error]
/// * [keyV] - The account's current key version
@BuiltValue()
abstract class PushKeyVersionMismatch
    implements Built<PushKeyVersionMismatch, PushKeyVersionMismatchBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'error')
  PushKeyVersionMismatchErrorEnum get error;
  // enum errorEnum {  key_version_mismatch,  };

  /// The account's current key version
  @BuiltValueField(wireName: r'keyV')
  int get keyV;

  PushKeyVersionMismatch._();

  factory PushKeyVersionMismatch([void updates(PushKeyVersionMismatchBuilder b)]) =
      _$PushKeyVersionMismatch;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PushKeyVersionMismatchBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PushKeyVersionMismatch> get serializer => _$PushKeyVersionMismatchSerializer();
}

class _$PushKeyVersionMismatchSerializer implements PrimitiveSerializer<PushKeyVersionMismatch> {
  @override
  final Iterable<Type> types = const [PushKeyVersionMismatch, _$PushKeyVersionMismatch];

  @override
  final String wireName = r'PushKeyVersionMismatch';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PushKeyVersionMismatch object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(object.id, specifiedType: const FullType(String));
    yield r'error';
    yield serializers.serialize(
      object.error,
      specifiedType: const FullType(PushKeyVersionMismatchErrorEnum),
    );
    yield r'keyV';
    yield serializers.serialize(object.keyV, specifiedType: const FullType(int));
  }

  @override
  Object serialize(
    Serializers serializers,
    PushKeyVersionMismatch object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PushKeyVersionMismatchBuilder result,
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
            specifiedType: const FullType(PushKeyVersionMismatchErrorEnum),
          ) as PushKeyVersionMismatchErrorEnum;
          result.error = valueDes;
          break;
        case r'keyV':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(int)) as int;
          result.keyV = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PushKeyVersionMismatch deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PushKeyVersionMismatchBuilder();
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

class PushKeyVersionMismatchErrorEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'key_version_mismatch')
  static const PushKeyVersionMismatchErrorEnum keyVersionMismatch =
      _$pushKeyVersionMismatchErrorEnum_keyVersionMismatch;

  static Serializer<PushKeyVersionMismatchErrorEnum> get serializer =>
      _$pushKeyVersionMismatchErrorEnumSerializer;

  const PushKeyVersionMismatchErrorEnum._(String name) : super(name);

  static BuiltSet<PushKeyVersionMismatchErrorEnum> get values =>
      _$pushKeyVersionMismatchErrorEnumValues;
  static PushKeyVersionMismatchErrorEnum valueOf(String name) =>
      _$pushKeyVersionMismatchErrorEnumValueOf(name);
}
